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
    /// Hunts of the same setup needed before that setup sets the bar (and before a drop is blamed on leaving it).
    static let minRuns = 2

    struct Run {
        let id: Int
        let summary: [String: Any]
        /// The median profit per hour of the setup this run stands for, and how many hunts that took (`reference`).
        var baseline: Double? = nil
        var runs = 1
        var endedAt: Double { number(summary["endedAt"]) ?? 0 }
        var hours: Double { (number(summary["elapsedSec"]) ?? 0) / 3600 }
        var profitPerHour: Double { (number(summary["balance"]) ?? 0) / hours }
        var levelMid: Double? {
            guard let range = summary["level"] as? [String: Any], let end = number(range["end"]) else { return nil }
            return ((number(range["start"]) ?? end) + end) / 2
        }
        var setup: [String: [String: Any]]? { (summary["setup"] as? [String: Any])?.compactMapValues { $0 as? [String: Any] } }
    }

    /// What the account usually makes here with its best setup. Profit per hour swings about 25% between hunts with
    /// nothing changed, so the single best hunt is a lucky one and a normal hunt reads as a drop: the comparable
    /// hunts (same map, near the level, recent, long enough, setup kept) are grouped by battle setup, each group
    /// valued by its median, and the best group with `minRuns` hunts or more wins, its hunt closest to the median
    /// standing for it. Without such a group, the median of all of them (no setup is then to blame).
    static func reference(runs: [Run], huntId: Int, level: Double, now: Double) -> Run? {
        let pool = runs.filter { run in
            number(run.summary["huntId"]).map { Int($0) } == huntId && run.hours * 3600 >= minSeconds && run.setup != nil
                && now - run.endedAt <= window && run.levelMid.map { abs($0 - level) <= levelRange } == true
        }.sorted { $0.endedAt > $1.endedAt }
        guard !pool.isEmpty else { return nil }
        var groups: [[Run]] = []
        for run in pool {
            if let index = groups.firstIndex(where: { sameSetup($0[0], run) }) { groups[index].append(run) } else { groups.append([run]) }
        }
        let ranked = groups.filter { $0.count >= minRuns }.map { ($0, median($0.map(\.profitPerHour))) }
        let (members, baseline) = ranked.max { $0.1 < $1.1 } ?? (pool, median(pool.map(\.profitPerHour)))
        // Closest to the median; the most recent of a tie (the pool is newest first).
        var reference = members.enumerated().min {
            (abs($0.element.profitPerHour - baseline), $0.offset) < (abs($1.element.profitPerHour - baseline), $1.offset)
        }!.element
        reference.baseline = baseline
        reference.runs = ranked.isEmpty ? 1 : members.count
        return reference
    }

    static func sameSetup(_ a: Run, _ b: Run) -> Bool {
        guard let x = a.setup, let y = b.setup, Set(x.keys) == Set(y.keys) else { return false }
        return x.allSatisfy { vocation, config in
            BattlePreset(vocation: vocation, huntId: nil, huntTitle: "", config: config).differences(from: y[vocation] ?? [:]).isEmpty
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// - Parameters:
    ///   - setup: the current battle configuration per base vocation (KNIGHT, PALADIN…).
    ///   - party: the party now, whose `suppliesGold` is what each member spent so far in this hunt.
    static func evaluate(reference: Run, analyzer: [String: Any]?, setup: [String: [String: Any]], party: [[String: Any]] = []) -> [String: Any] {
        var out: [String: Any] = [:]
        let range = reference.summary["level"] as? [String: Any]
        let low = Int(number(range?["start"]) ?? 0), high = Int(number(range?["end"]) ?? 0)
        let baseline = reference.baseline ?? reference.profitPerHour
        // `profitPerHour` is what the setup usually makes (the median of `runs` hunts); the other fields are its hunt's.
        var summary: [String: Any] = ["id": reference.id, "endedAt": reference.endedAt, "hours": (reference.hours * 10).rounded() / 10,
                                      "profitPerHour": Int(baseline.rounded()), "runs": reference.runs,
                                      "levels": low == high ? "\(low)" : "\(low)–\(high)"]
        summary["takenPerKill"] = takenPerKill(reference.summary)
        out["reference"] = summary
        let before = reference.setup ?? [:]
        out["changes"] = ["KNIGHT", "PALADIN", "SORCERER", "DRUID", "MONK"].compactMap { vocation -> [String: Any]? in
            guard let now = setup[vocation], let then = before[vocation] else { return nil }
            let differences = BattlePreset(vocation: vocation, huntId: nil, huntTitle: "", config: now).differences(from: then)
            return differences.isEmpty ? nil : ["vocation": vocation, "label": BattlePreset.vocationLabel(vocation), "differences": differences]
        }
        if let analyzer, let elapsed = number(analyzer["elapsedMs"]), elapsed >= minElapsedMs {
            let profit = ((number(analyzer["lootGold"]) ?? 0) - (number(analyzer["suppliesGold"]) ?? 0)) / (elapsed / 3_600_000)
            out["profitPerHour"] = Int(profit.rounded())
            out["takenPerKill"] = takenPerKill(analyzer)
            if baseline > 0 { out["drop"] = (baseline - profit) / baseline }
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

    /// Total experience at the start of a level (the game uses Tibia's table).
    static func experience(level: Int) -> Double {
        let l = Double(level - 1)
        return (50 * l * l * l - 150 * l * l + 400 * l) / 3
    }

    /// Time to the next level on this hunt, and on the other maps this account hunted near this level,
    /// with the gold made (or spent) on the way: how much leveling faster costs.
    static func levelPlan(level: Int, xp: Double, xpPerHour: Double, huntId: Int?, runs: [Run], now: Double,
                          title: (Int) -> String) -> [String: Any]? {
        let needed = experience(level: level + 1) - xp
        guard needed > 0 else { return nil }
        var out: [String: Any] = ["next": level + 1, "needed": Int(needed.rounded())]
        if xpPerHour > 0 { out["etaMs"] = needed / xpPerHour * 3_600_000 }
        struct Total { var seconds = 0.0, xp = 0.0, balance = 0.0, limited = false }
        var totals: [Int: Total] = [:]
        for run in runs where run.hours * 3600 >= minSeconds && now - run.endedAt <= window
            && run.levelMid.map({ abs($0 - Double(level)) <= levelRange }) == true {
            guard let id = number(run.summary["huntId"]).map({ Int($0) }) else { continue }
            var total = totals[id] ?? Total()
            total.seconds += run.hours * 3600
            total.xp += number(run.summary["xp"]) ?? 0
            total.balance += number(run.summary["balance"]) ?? 0
            total.limited = total.limited || run.summary["reason"] as? String == "access_over"
            totals[id] = total
        }
        let maps = totals.filter { $0.value.xp > 0 }.map { id, total -> [String: Any] in
            let hours = total.seconds / 3600, perHour = total.xp / hours, profit = total.balance / hours
            let eta = needed / perHour
            return ["huntId": id, "title": title(id), "current": id == huntId, "hours": (hours * 10).rounded() / 10,
                    "xpPerHour": Int(perHour.rounded()), "profitPerHour": Int(profit.rounded()),
                    "etaMs": eta * 3_600_000, "goldToLevel": Int((profit * eta).rounded()), "limited": total.limited]
        }.sorted { ($0["xpPerHour"] as? Int ?? 0) > ($1["xpPerHour"] as? Int ?? 0) }
        if !maps.isEmpty { out["maps"] = Array(maps.prefix(4)) }
        return out
    }

    /// Damage taken per kill: damage dealt per kill is the monster's health, so this separates defense from kill speed.
    static func takenPerKill(_ totals: [String: Any]) -> Int? {
        guard let kills = number(totals["killsTotal"]), kills >= 50, let taken = number(totals["damageTaken"]) else { return nil }
        return Int((taken / kills).rounded())
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
