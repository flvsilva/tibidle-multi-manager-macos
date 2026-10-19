import Foundation

/// The game's public hunt list (`https://play.tibidle.com/hunts`): which monsters live on which map.
public struct HuntCatalog: Equatable {
    public struct Hunt: Equatable {
        public let id: Int
        public let title: String
        public let island: String
        public let monsters: [String]
    }

    public let hunts: [Hunt]

    public static let empty = HuntCatalog(hunts: [])
    public static let url = URL(string: "https://play.tibidle.com/hunts")!

    public init(hunts: [Hunt]) { self.hunts = hunts }

    public init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let list = root["hunts"] as? [[String: Any]], !list.isEmpty else { return nil }
        hunts = list.compactMap { item in
            guard let id = item["id"] as? Int, let title = item["title"] as? String else { return nil }
            return Hunt(id: id, title: title, island: item["island"] as? String ?? "",
                        monsters: (item["monsters"] as? [String]) ?? [])
        }
        if hunts.isEmpty { return nil }
    }

    public func hunt(id: Int) -> Hunt? { hunts.first { $0.id == id } }

    static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    public struct Candidate: Equatable {
        public let hunt: Hunt
        /// True when the map holds every target monster of the mission.
        public let full: Bool
    }

    /// Maps a monster mission to maps, following the game's own "Explorar" rule: maps holding every
    /// target come first (a map named after the mission title, "Caçada: <map>", leads); with none,
    /// the maps sharing the most targets.
    public func candidates(targets: [String], missionTitle: String, limit: Int = 4) -> [Candidate] {
        let wanted = targets.map(Self.key).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return [] }
        let scored = hunts.map { hunt -> (Hunt, Int) in
            let present = Set(hunt.monsters.map(Self.key))
            return (hunt, wanted.filter(present.contains).count)
        }
        var chosen = scored.filter { $0.1 == wanted.count }
        let full = !chosen.isEmpty
        if !full {
            let best = scored.map(\.1).max() ?? 0
            guard best > 0 else { return [] }
            chosen = scored.filter { $0.1 == best }
        }
        var hint: String?
        if let colon = missionTitle.firstIndex(of: ":") {
            hint = Self.key(String(missionTitle[missionTitle.index(after: colon)...]))
        }
        let ordered = chosen.sorted { a, b in
            let ah = a.0.title.lowercased() == hint, bh = b.0.title.lowercased() == hint
            return ah != bh ? ah : false
        }
        return ordered.prefix(limit).map { Candidate(hunt: $0.0, full: full) }
    }
}
