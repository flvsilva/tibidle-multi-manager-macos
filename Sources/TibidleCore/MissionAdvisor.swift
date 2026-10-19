import Foundation

/// Combines an account's daily missions with its current hunt and the hunt catalog.
public enum MissionAdvisor {
    /// - Parameters:
    ///   - eventos: last missions state (`{serverDay, nextDailyResetAt, diarias:{slots}, semanais}`).
    ///   - live: progress seen in the last `frame` (`{serverDay, slots:{taskId: shown}}`).
    public static func evaluate(eventos: [String: Any], live: [String: Any]?, hunting: Bool, training: Bool,
                                currentHuntId: Int?, catalog: HuntCatalog) -> [String: Any] {
        let serverDay = eventos["serverDay"] as? String
        let liveSlots = (live?["serverDay"] as? String) == serverDay ? live?["slots"] as? [String: Double] : nil
        let current = currentHuntId.flatMap { catalog.hunt(id: $0) }
        let rawSlots = ((eventos["diarias"] as? [String: Any])?["slots"] as? [Any]) ?? []

        let missions: [[String: Any]] = rawSlots.compactMap { raw in
            guard let task = raw as? [String: Any], let id = task["id"] as? String else { return nil }
            let kind = task["kind"] as? String ?? ""
            let quantity = Int(number(task["quantity"]))
            let progress = Int(max(number(task["progresso"]), liveSlots?[id] ?? 0))
            let claimed = task["resgatado"] as? Bool ?? false
            let targets = (task["targets"] as? [String]) ?? []
            var out: [String: Any] = [
                "id": id, "kind": kind, "title": task["title"] as? String ?? "", "quantity": quantity,
                "progress": progress, "claimed": claimed, "targets": targets, "rewards": task["rewards"] ?? [],
            ]
            let counts = current.map { hunt in
                let present = Set(hunt.monsters.map(HuntCatalog.key))
                return targets.contains { present.contains(HuntCatalog.key($0)) }
            }
            switch kind {
            case "monster":
                out["candidates"] = catalog.candidates(targets: targets, missionTitle: task["title"] as? String ?? "").map {
                    ["id": $0.hunt.id, "title": $0.hunt.title, "island": $0.hunt.island, "full": $0.full] as [String: Any]
                }
            default:
                break
            }
            if claimed {
                out["state"] = "claimed"
            } else if quantity > 0, progress >= quantity {
                out["state"] = "ready"
            } else if kind == "elite" {
                out["state"] = "elite"
            } else if kind != "monster" {
                out["state"] = "forge"
            } else if !hunting || training {
                out["state"] = "pending"
            } else if let counts {
                out["state"] = counts ? "on_track" : "off_track"
            } else {
                out["state"] = "unknown"
            }
            return out
        }

        var result: [String: Any] = ["missions": missions]
        if let current { result["currentHunt"] = ["id": current.id, "title": current.title] as [String: Any] }
        if let reset = number(eventos["nextDailyResetAt"]) as Double?, reset > 0 {
            result["dailyResetAt"] = reset < 100_000_000_000 ? reset * 1000 : reset
        }
        if let weekly = eventos["semanais"] as? [String: Any] {
            result["weekly"] = ["done": Int(number(weekly["concluidas"])), "needed": Int(number(weekly["necessarias"]))]
        }
        return result
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
}
