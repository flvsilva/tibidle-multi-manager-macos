import Foundation

/// Read-only summary of the daily invasion schedule the game reports in `meta.invasao`.
public enum InvasionAdvisor {
    /// - Returns: nil when the game reported no invasion for the day.
    public static func evaluate(_ invasion: [String: Any]?, now: Double) -> [String: Any]? {
        guard let invasion, let windows = invasion["janelas"] as? [[String: Any]], !windows.isEmpty else { return nil }
        let joined = invasion["inscrito"] as? Bool == true
        let finished = invasion["encerrada"] as? Bool == true
        let upcoming = windows
            .filter { $0["cancelada"] as? Bool != true }
            .compactMap { w -> (idx: Int, start: Double, live: Bool)? in
                guard let start = number(w["startAtMs"]) else { return nil }
                return (Int(number(w["idx"]) ?? 0), start, w["estado"] as? String == "ao_vivo")
            }
            .filter { $0.live || $0.start > now }
            .sorted { $0.start < $1.start }
        var out: [String: Any] = [
            "name": invasion["invasionNome"] as? String ?? "Invasão",
            "boss": invasion["bossName"] as? String ?? "",
            "joined": joined, "finished": finished,
            "windows": windows.compactMap { number($0["startAtMs"]) },
        ]
        if let next = upcoming.first, !finished {
            out["next"] = ["idx": next.idx, "startAt": next.start, "live": next.live] as [String: Any]
        }
        return out
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
