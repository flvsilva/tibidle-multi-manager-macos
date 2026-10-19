import Foundation

/// Per-hunt bestiary milestones from the game's public `/hunts/select`: every map has three kill
/// thresholds that unlock a permanent bonus. Also carries each map's monsters with their resistances.
public struct HuntBestiaryCatalog {
    public struct Entry: Equatable {
        public let id: Int
        public let title: String
        public let bonus: String
        public let stages: [(kills: Double, value: Double)]

        public static func == (a: Entry, b: Entry) -> Bool {
            a.id == b.id && a.bonus == b.bonus && a.stages.map(\.kills) == b.stages.map(\.kills)
        }
    }

    public static let url = URL(string: "https://play.tibidle.com/hunts/select")!
    public static let empty = HuntBestiaryCatalog(entries: [:], creatures: CreatureCatalog())

    public let entries: [Int: Entry]
    public let creatures: CreatureCatalog

    public init(entries: [Int: Entry], creatures: CreatureCatalog) {
        self.entries = entries
        self.creatures = creatures
    }

    public init?(json: Data) {
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]], !list.isEmpty else { return nil }
        var entries: [Int: Entry] = [:]
        var creatures = CreatureCatalog()
        for hunt in list {
            guard let id = (hunt["id"] as? NSNumber)?.intValue else { continue }
            if let bestiary = hunt["bestiary"] as? [String: Any], let bonus = bestiary["bonus"] as? String,
               let stages = bestiary["stages"] as? [[String: Any]] {
                let parsed = stages.compactMap { stage -> (kills: Double, value: Double)? in
                    guard let kills = (stage["kills"] as? NSNumber)?.doubleValue else { return nil }
                    return (kills, (stage["value"] as? NSNumber)?.doubleValue ?? 0)
                }
                if !parsed.isEmpty, parsed.contains(where: { $0.value != 0 }) {
                    entries[id] = Entry(id: id, title: hunt["title"] as? String ?? "", bonus: bonus, stages: parsed)
                }
            }
            for monster in hunt["monsters"] as? [[String: Any]] ?? [] {
                if let name = monster["name"] as? String, let elements = monster["elements"] as? [[String: Any]] {
                    creatures.add(name: name, elements: elements)
                }
            }
        }
        guard !entries.isEmpty else { return nil }
        self.init(entries: entries, creatures: creatures)
    }
}

public enum BestiaryAdvisor {
    /// - Parameters:
    ///   - counted: kills the server has recorded for this map (`meta.huntBestiary[huntId]`).
    ///   - session: kills of the hunt in progress (not yet in `counted`).
    ///   - elapsedMs: duration of the hunt in progress, used for the kill rate.
    public static func evaluate(_ entry: HuntBestiaryCatalog.Entry, counted: Double, session: Double, elapsedMs: Double) -> [String: Any] {
        let kills = counted + session
        let stages = entry.stages.map { ["kills": $0.kills, "value": $0.value, "done": kills >= $0.kills] as [String: Any] }
        var result: [String: Any] = ["bonus": entry.bonus, "kills": kills, "counted": counted, "stages": stages,
                                     "reached": entry.stages.filter { kills >= $0.kills }.count]
        let final = entry.stages.last?.kills ?? 0
        result["done"] = kills >= final
        // Kill rate of the current hunt; needs a few minutes of data to be meaningful.
        guard elapsedMs >= 5 * 60_000, session > 0 else { return result }
        let perHour = session / (elapsedMs / 3_600_000)
        result["perHour"] = perHour
        if let next = entry.stages.first(where: { kills < $0.kills }) {
            result["next"] = ["kills": next.kills, "value": next.value, "remaining": next.kills - kills,
                              "etaMs": (next.kills - kills) / perHour * 3_600_000] as [String: Any]
        }
        if kills < final { result["etaMs"] = (final - kills) / perHour * 3_600_000 }
        return result
    }
}
