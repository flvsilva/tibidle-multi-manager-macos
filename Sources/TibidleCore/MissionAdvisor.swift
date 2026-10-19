import Foundation

/// Combines an account's daily missions with its current hunt and the hunt catalog.
public enum MissionAdvisor {
    /// - Parameters:
    ///   - eventos: last missions state (`{serverDay, nextDailyResetAt, diarias:{slots}, semanais}`).
    ///   - live: progress seen in the last `frame` (`{serverDay, slots:{taskId: shown}}`).
    public static func evaluate(eventos: [String: Any], live: [String: Any]?, hunting: Bool, training: Bool,
                                currentHuntId: Int?, catalog: HuntCatalog, analyzer: [String: Any]? = nil,
                                weekLive: Double? = nil, now: Double = Date().timeIntervalSince1970 * 1000) -> [String: Any] {
        let serverDay = eventos["serverDay"] as? String
        let liveSlots = (live?["serverDay"] as? String) == serverDay ? live?["slots"] as? [String: Double] : nil
        let current = currentHuntId.flatMap { catalog.hunt(id: $0) }
        var resetAt = number(eventos["nextDailyResetAt"])
        if resetAt > 0, resetAt < 100_000_000_000 { resetAt *= 1000 }
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
            } else if current == nil, currentHuntId != nil, !catalog.hunts.isEmpty {
                // Only regular hunts are listed; Tower, Elite and Boss fights don't advance creature missions.
                out["state"] = "no_count"
            } else {
                out["state"] = "unknown"
            }
            if out["state"] as? String == "on_track", let eta = forecast(targets: targets, remaining: quantity - progress,
                                                                        analyzer: analyzer, resetAt: resetAt, now: now) {
                out["eta"] = eta
            }
            return out
        }

        var result: [String: Any] = ["missions": missions]
        let open = missions.filter { $0["claimed"] as? Bool != true }.count
        if !missions.isEmpty {
            result["claimsLeft"] = open
        }
        if let streak = streak(eventos["sequencia"] as? [String: Any], open: missions.isEmpty ? nil : open,
                               resetAt: resetAt, now: now) {
            result["streak"] = streak
        }
        let goals = weeklyGoals(eventos["semanais"] as? [String: Any], live: weekLive)
        if !goals.isEmpty { result["weeklyGoals"] = goals }
        if let current { result["currentHunt"] = ["id": current.id, "title": current.title] as [String: Any] }
        if resetAt > 0 { result["dailyResetAt"] = resetAt }
        if let weekly = eventos["semanais"] as? [String: Any] {
            result["weekly"] = ["done": Int(number(weekly["concluidas"])), "needed": Int(number(weekly["necessarias"]))]
        }
        return result
    }

    /// Kill rate of the mission's targets in the running hunt → time left, and whether it ends before the reset.
    static func forecast(targets: [String], remaining: Int, analyzer: [String: Any]?, resetAt: Double, now: Double) -> [String: Any]? {
        guard remaining > 0, let analyzer, let kills = analyzer["kills"] as? [String: Any] else { return nil }
        let elapsed = number(analyzer["elapsedMs"])
        let wanted = Set(targets.map(HuntCatalog.key))
        let killed = kills.reduce(0.0) { $0 + (wanted.contains(HuntCatalog.key($1.key)) ? number($1.value) : 0) }
        guard elapsed >= 120_000, killed >= 5 else { return nil }
        let perHour = killed / (elapsed / 3_600_000)
        let etaMs = Double(remaining) / perHour * 3_600_000
        var out: [String: Any] = ["perHour": Int(perHour.rounded()), "etaMs": Int(etaMs.rounded()), "remaining": remaining]
        if resetAt > now { out["fits"] = now + etaMs <= resetAt }
        return out
    }

    /// Weekly streak: the day only closes once the last daily mission is claimed; a missed day breaks the week.
    static func streak(_ raw: [String: Any]?, open: Int?, resetAt: Double, now: Double) -> [String: Any]? {
        guard let raw else { return nil }
        let days = ((raw["dias"] as? [[String: Any]]) ?? []).map { $0["estado"] as? String ?? "" }
        var out: [String: Any] = [
            "day": Int(number(raw["diaAtual"])), "closed": Int(number(raw["fechados"])), "days": days,
            "recoverCost": Int(number(raw["custoRecuperar"])),
        ]
        let toRecover = days.filter { $0 == "recuperar" }.count
        if toRecover > 0 { out["toRecover"] = toRecover }
        if let open, open > 0, resetAt > now {
            out["atRisk"] = resetAt - now <= 4 * 3_600_000
            out["open"] = open
        }
        return out
    }

    static func weeklyGoals(_ weekly: [String: Any]?, live: Double?) -> [[String: Any]] {
        ((weekly?["tarefas"] as? [[String: Any]]) ?? []).compactMap { goal in
            guard let id = goal["id"] as? String else { return nil }
            let target = Int(number(goal["meta"]))
            var progress = Int(number(goal["progresso"]))
            if id == "monstros", let live { progress = max(progress, Int(live)) }
            return ["id": id, "progress": progress, "goal": target]
        }
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
}


/// Warnings about resources that are lost while hunting: a full backpack ends the hunt, a full key bag drops keys.
public enum HuntAlerts {
    public static func evaluate(state: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        var alerts: [[String: String]] = []
        if let cap = state["cap"] as? [String: Any] {
            let used = number(cap["used"]), total = number(cap["total"])
            if total > 0 {
                let pct = used / total
                out["cap"] = ["used": Int(used), "total": Int(total)]
                if pct >= 1 { alerts.append(["kind": "cap", "level": "bad", "text": "Mochila cheia: o loot novo se perde e a hunt termina."]) }
                else if pct >= 0.9 { alerts.append(["kind": "cap", "level": "warn", "text": "Mochila a \(Int(pct * 100))% — venda ou esvazie antes que a hunt termine."]) }
            }
        }
        let capacity = number(state["keyBagMax"])
        if capacity > 0 {
            let used = number(state["keyBagUsed"])
            var keys: [String: Any] = ["used": Int(used), "max": Int(capacity)]
            if let clock = state["keyClock"] as? [String: Any], number(clock["everyMs"]) > 0 {
                keys["nextKeyMs"] = Int(number(clock["everyMs"]) - number(clock["tierMs"]).truncatingRemainder(dividingBy: number(clock["everyMs"])))
            }
            out["keys"] = keys
            if used >= capacity { alerts.append(["kind": "keys", "level": "bad", "text": "Bolsa de chaves cheia: as próximas chaves se perdem. Gaste em Elites."]) }
            else if used >= capacity - 1 { alerts.append(["kind": "keys", "level": "warn", "text": "Bolsa de chaves quase cheia (\(Int(used))/\(Int(capacity)))."]) }
        }
        out["alerts"] = alerts
        return out
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
}
