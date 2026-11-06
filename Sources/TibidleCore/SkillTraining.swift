import Foundation

/// How fast each skill goes up: the party's skill levels and their progress (0–100%, as the game shows it) over the
/// last 10 minutes, and when the next level comes at that pace. The game shows the progress in whole percents, so a
/// slow skill looks further back (up to 2 hours) until it moved at least 2%.
public struct SkillTraining {
    struct Point { let date: Date; let progress: Double }

    static let skills = ["melee", "distance", "magic", "shielding"]
    static let window = 10 * 60.0
    static let keep = 2 * 3600.0
    static let minSteps = 2.0
    /// Less than this and the pace says nothing yet.
    static let minSeconds = 3 * 60.0

    private var points: [Int: [String: [Point]]] = [:]
    private var members: [Int: (name: String, vocation: String)] = [:]

    public init() {}

    /// One posted frame. Progress is the level times 100 plus the percent, so a level up keeps it going up.
    public mutating func add(party: [[String: Any]], at date: Date) {
        for (position, member) in party.enumerated() {
            guard let levels = member["skillLevels"] as? [String: Any], let pcts = member["skillProgress"] as? [String: Any] else { continue }
            members[position] = (member["name"] as? String ?? "", member["vocation"] as? String ?? "")
            for skill in Self.skills {
                guard let level = HuntInsights.number(levels[skill]), let pct = HuntInsights.number(pcts[skill]) else { continue }
                let progress = level * 100 + min(100, max(0, pct))
                var list = points[position]?[skill] ?? []
                // A loss (a death takes skill) starts over; otherwise a point per change, or per minute while it stays.
                if let last = list.last, progress < last.progress { list = [] }
                if list.count > 1, list[list.count - 1].progress == progress, list[list.count - 2].progress == progress,
                   date.timeIntervalSince(list[list.count - 2].date) < 60 {
                    list[list.count - 1] = Point(date: date, progress: progress)
                } else {
                    list.append(Point(date: date, progress: progress))
                }
                list.removeAll { date.timeIntervalSince($0.date) > Self.keep }
                points[position, default: [:]][skill] = list
            }
        }
    }

    /// The pace of one skill: progress points per hour, over the seconds looked at. Nil while it did not move.
    /// Measured between the moments the percent changed, so a percent that just ticked (or is about to) does not
    /// read as faster (or slower); a skill stopped since then counts the time it stood still.
    static func pace(_ list: [Point]) -> (perHour: Double, seconds: Double, gained: Double)? {
        guard let latest = list.last else { return nil }
        let changes = zip(list, list.dropFirst()).filter { $1.progress > $0.progress }.map(\.1)
        var window = window
        while true {
            let recent = changes.filter { latest.date.timeIntervalSince($0.date) <= window }
            if let first = recent.first, let last = recent.last, last.progress - first.progress >= minSteps || window >= keep {
                let gained = last.progress - first.progress
                guard gained > 0 else { return nil }
                let between = last.date.timeIntervalSince(first.date), step = between / gained
                let seconds = max(between, latest.date.timeIntervalSince(first.date) - step)
                guard seconds >= minSeconds else { return nil }
                return (gained / seconds * 3600, latest.date.timeIntervalSince(first.date), gained)
            }
            guard window < keep else { return nil }
            window *= 2
        }
    }

    /// Per member, the skills going up: level, percent, percent per hour, the minutes looked at and the time to the next level.
    public func summary() -> [[String: Any]]? {
        var out: [[String: Any]] = []
        for (position, skills) in points.sorted(by: { $0.key < $1.key }) {
            var rows: [[String: Any]] = []
            for skill in Self.skills {
                guard let list = skills[skill], let latest = list.last, let pace = Self.pace(list) else { continue }
                let level = (latest.progress / 100).rounded(.down), pct = latest.progress - level * 100
                rows.append(["skill": skill, "level": Int(level), "pct": pct, "perHour": pace.perHour,
                             "minutes": Int((pace.seconds / 60).rounded()), "gained": pace.gained,
                             "nextInSec": (100 - pct) / pace.perHour * 3600])
            }
            guard !rows.isEmpty else { continue }
            let member = members[position]
            out.append(["position": position, "name": member?.name ?? "", "vocation": member?.vocation ?? "", "skills": rows])
        }
        return out.isEmpty ? nil : out
    }
}
