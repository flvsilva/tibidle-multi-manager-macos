import Foundation

/// Compares the hunt in progress with the account's own earlier hunts on the same map, so a drop in
/// profit can be traced to what changed since (the battle setup, who spends the supplies).
public enum HuntInsights {
    /// Shorter hunts say little about a map's yield; older ones were made with other gear and levels.
    static let minSeconds = 1800.0
    static let levelRange = 5.0
    static let window = 14.0 * 86_400_000
    /// The hunt in progress needs this long before its rates are compared.
    static let minElapsedMs = 30.0 * 60_000
    static let dropWarning = 0.2

    struct Run {
        let id: Int
        let summary: [String: Any]
        var endedAt: Double { number(summary["endedAt"]) ?? 0 }
        var hours: Double { (number(summary["elapsedSec"]) ?? 0) / 3600 }
        var profitPerHour: Double { (number(summary["balance"]) ?? 0) / hours }
        var levelMid: Double? {
            guard let range = summary["level"] as? [String: Any], let end = number(range["end"]) else { return nil }
            return ((number(range["start"]) ?? end) + end) / 2
        }
        var setup: [String: [String: Any]]? { (summary["setup"] as? [String: Any])?.compactMapValues { $0 as? [String: Any] } }
    }

    /// The account's most profitable recent hunt on this map, near this level, that kept its battle setup.
    static func reference(runs: [Run], huntId: Int, level: Double, now: Double) -> Run? {
        runs.filter { run in
            number(run.summary["huntId"]).map { Int($0) } == huntId && run.hours * 3600 >= minSeconds && run.setup != nil
                && now - run.endedAt <= window && run.levelMid.map { abs($0 - level) <= levelRange } == true
        }.max { $0.profitPerHour < $1.profitPerHour }
    }

    /// - Parameters:
    ///   - setup: the current battle configuration per base vocation (KNIGHT, PALADIN…).
    ///   - party: the party now, whose `suppliesGold` is what each member spent so far in this hunt.
    static func evaluate(reference: Run, analyzer: [String: Any]?, setup: [String: [String: Any]], party: [[String: Any]] = []) -> [String: Any] {
        var out: [String: Any] = [:]
        let range = reference.summary["level"] as? [String: Any]
        let low = Int(number(range?["start"]) ?? 0), high = Int(number(range?["end"]) ?? 0)
        out["reference"] = ["id": reference.id, "endedAt": reference.endedAt, "hours": (reference.hours * 10).rounded() / 10,
                            "profitPerHour": Int(reference.profitPerHour.rounded()), "levels": low == high ? "\(low)" : "\(low)–\(high)"]
        let before = reference.setup ?? [:]
        out["changes"] = ["KNIGHT", "PALADIN", "SORCERER", "DRUID", "MONK"].compactMap { vocation -> [String: Any]? in
            guard let now = setup[vocation], let then = before[vocation] else { return nil }
            let differences = BattlePreset(vocation: vocation, huntId: nil, huntTitle: "", config: now).differences(from: then)
            return differences.isEmpty ? nil : ["vocation": vocation, "label": BattlePreset.vocationLabel(vocation), "differences": differences]
        }
        if let analyzer, let elapsed = number(analyzer["elapsedMs"]), elapsed >= minElapsedMs {
            let profit = ((number(analyzer["lootGold"]) ?? 0) - (number(analyzer["suppliesGold"]) ?? 0)) / (elapsed / 3_600_000)
            out["profitPerHour"] = Int(profit.rounded())
            if reference.profitPerHour > 0 { out["drop"] = (reference.profitPerHour - profit) / reference.profitPerHour }
            out["members"] = members(party: party, hours: elapsed / 3_600_000, reference: reference, setup: setup)
        }
        return out
    }

    /// Supplies per hour of each member now and in the reference hunt, with the setup changes that touch the bill.
    static func members(party: [[String: Any]], hours: Double, reference: Run, setup: [String: [String: Any]]) -> [[String: Any]] {
        let before = (reference.summary["members"] as? [[String: Any]]) ?? []
        return party.compactMap { member -> [String: Any]? in
            guard let raw = member["vocation"] as? String else { return nil }
            let vocation = SkillAdvisor.baseVocation(raw).uppercased()
            var row: [String: Any] = ["vocation": vocation, "label": BattlePreset.vocationLabel(vocation),
                                      "perHour": Int(((number(member["suppliesGold"]) ?? 0) / hours).rounded())]
            if let then = before.first(where: { SkillAdvisor.baseVocation($0["vocation"] as? String ?? "").uppercased() == vocation }) {
                row["before"] = Int(((number(then["suppliesGold"]) ?? 0) / reference.hours).rounded())
            }
            if let now = setup[vocation], let then = reference.setup?[vocation] {
                let changes = BattlePreset(vocation: vocation, huntId: nil, huntTitle: "", config: now).costDifferences(from: then)
                if !changes.isEmpty { row["changes"] = changes }
            }
            return row
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
