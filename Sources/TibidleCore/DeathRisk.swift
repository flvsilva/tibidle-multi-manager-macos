import Foundation

/// Chance that someone in the party dies, from the hunt's own health: every posted frame (about 3 s apart) gives,
/// per party position, the health at the start of the window and how much of it was lost by the end, healing
/// included (a knight can take 1600 in 3 s and heal most of it, so the hits alone say too much). The largest are
/// fitted with an exponential tail (peaks over a threshold), which tells how likely a window bigger than any seen
/// so far is; the chance that a window outdoes the health the member had at its start, summed over an hour of
/// windows, is the risk. Before there is enough of the hunt, the map's deaths per hour stand in.
public struct DeathRisk {
    struct Window { let date: Date; let health: Double; let lost: Double }

    /// The windows weighed: the last 20 minutes, the latest counting most (half-life of 5 minutes).
    static let keep = 20 * 60.0
    static let halfLife = 5 * 60.0
    /// Enough of the hunt to say something: 10 minutes of windows, some of them losing health.
    static let minWindows = 200
    static let minHurt = 20
    /// Windows above this quantile of health lost make the tail.
    static let tailQuantile = 0.9
    /// Above these the hunt is flagged, and notified.
    public static let warnPerHour = 0.05
    public static let alertPerHour = 0.10

    private var windows: [Int: [Window]] = [:]
    private var health: [Int: Double] = [:]
    private var maxHealth: [Int: Double] = [:]
    private var vocations: [Int: String] = [:]
    private var last: Date?
    /// Deaths the uncalibrated estimate expected over the hunt so far (rate × time), for the calibration.
    private(set) var expected = 0.0
    private(set) var covered = 0.0
    private var accrued: Date?

    public init() {}

    /// Adds the estimate's expected deaths since the last call (about once a minute), for the hunt summary.
    mutating func accrue(now: Date) {
        guard let accrued else { accrued = now; return }
        guard now.timeIntervalSince(accrued) >= 60 else { return }
        self.accrued = now
        let seconds = min(now.timeIntervalSince(accrued), 300)
        guard let rate = estimate(now: now)?["rate"] as? Double else { return }
        expected += rate * seconds / 3600
        covered += seconds
    }

    /// One posted frame: the party as it is now. The window since the last frame is the health lost in between.
    public mutating func add(party: [[String: Any]], at date: Date) {
        let elapsed = last.map { date.timeIntervalSince($0) } ?? 0
        last = date
        // A gap (app paused, reconnect) is not one window: only frames about 3 s apart count.
        let counts = elapsed > 0 && elapsed <= 10
        for (position, member) in party.enumerated() {
            guard let hp = HuntInsights.number(member["hp"]), let maxHp = HuntInsights.number(member["maxHp"]), maxHp > 0 else { continue }
            if counts, let start = health[position] {
                windows[position, default: []].append(Window(date: date, health: start, lost: max(0, start - hp)))
            }
            health[position] = hp
            maxHealth[position] = maxHp
            vocations[position] = member["vocation"] as? String
        }
        for position in windows.keys { windows[position]?.removeAll { date.timeIntervalSince($0.date) > Self.keep } }
    }

    /// Chance, per window, that the health lost is at least `x`: the measured share below the threshold, the fitted
    /// exponential tail above it. Nil until there are enough windows.
    static func exceeds(_ windows: [Window], now: Date) -> ((Double) -> Double)? {
        guard windows.count >= minWindows, windows.filter({ $0.lost > 0 }).count >= minHurt else { return nil }
        // Damage sorted with its weight, and the weight from each one up: "at least x" is one binary search.
        let weighed = windows.map { ($0.lost, pow(0.5, now.timeIntervalSince($0.date) / halfLife)) }.sorted { $0.0 < $1.0 }
        var from = [Double](repeating: 0, count: weighed.count + 1)
        for i in stride(from: weighed.count - 1, through: 0, by: -1) { from[i] = from[i + 1] + weighed[i].1 }
        let total = from[0]
        let threshold = weighed[Int(Double(weighed.count - 1) * tailQuantile)].0
        let above = weighed.filter { $0.0 > threshold }
        guard !above.isEmpty else { return { x in x <= threshold ? 1 : 0 } }
        let share = above.reduce(0) { $0 + $1.1 } / total
        // Mean excess over the threshold, weighed like the windows: the exponential tail's scale. With few
        // excesses, the largest one sets a floor, so a single big hit is not averaged away.
        let mean = above.reduce(0) { $0 + ($1.0 - threshold) * $1.1 } / above.reduce(0) { $0 + $1.1 }
        let scale = max(mean, (above.last!.0 - threshold) / Double(above.count).squareRoot(), 1)
        return { x in
            guard x > threshold else {
                var low = 0, high = weighed.count
                while low < high { let mid = (low + high) / 2; if weighed[mid].0 < x { low = mid + 1 } else { high = mid } }
                return from[low] / total
            }
            return share * exp(-(x - threshold) / scale)
        }
    }

    /// Per member, the chance of dying in the next hour, and the party's; nil before there is enough of the hunt.
    public func estimate(now: Date) -> [String: Any]? {
        var members: [[String: Any]] = []
        var rate = 0.0
        for (position, list) in windows.sorted(by: { $0.key < $1.key }) {
            guard let tail = Self.exceeds(list, now: now) else { continue }
            // The health each window started from, as it happened: dips count where they were. Windows that
            // started dead are not a new risk.
            let alive = list.filter { $0.health > 0 }
            let weights = alive.map { pow(0.5, now.timeIntervalSince($0.date) / Self.halfLife) }
            let total = max(1e-9, weights.reduce(0, +))
            let perWindow = zip(alive, weights).reduce(0) { $0 + tail($1.0.health) * $1.1 } / total
            let seconds = list.count > 1 ? list.last!.date.timeIntervalSince(list.first!.date) / Double(list.count - 1) : 3
            let perHour = perWindow * 3600 / max(1, seconds)
            rate += perHour
            let lowest = list.map(\.health).min() ?? 0
            members.append(["position": position, "vocation": vocations[position] ?? "", "perHour": 1 - exp(-perHour),
                            "biggestWindow": Int(list.map(\.lost).max() ?? 0), "lowestHealth": Int(lowest),
                            "maxHealth": Int(maxHealth[position] ?? 0)])
        }
        guard !members.isEmpty else { return nil }
        return ["perHour": 1 - exp(-rate), "rate": rate, "source": "live",
                "minutes": Int(((windows.values.map { $0.count }.max() ?? 0) * 3) / 60),
                "members": members.sorted { ($0["perHour"] as? Double ?? 0) > ($1["perHour"] as? Double ?? 0) }]
    }

    /// Before the live estimate: deaths per hour on this map near the level, all accounts, pulled towards
    /// the overall rate so a death in a short hunt does not read as 50% (10 hours of the overall rate as a prior).
    static func fromHistory(deaths: Double, hours: Double, overallRate: Double) -> [String: Any]? {
        guard hours > 0 || overallRate > 0 else { return nil }
        let rate = (deaths + 10 * overallRate) / (hours + 10)
        return ["perHour": 1 - exp(-rate), "rate": rate, "source": "history", "deaths": Int(deaths), "hours": (hours * 10).rounded() / 10]
    }

    /// Calibration from finished hunts: deaths seen over deaths predicted (rate × hours), smoothed by one death
    /// on each side, within 1/4 and 4; 1 until 10 hunts carry a prediction.
    static func calibration(_ runs: [(predicted: Double, deaths: Double)]) -> (factor: Double, runs: Int) {
        guard runs.count >= 10 else { return (1, runs.count) }
        let predicted = runs.reduce(0) { $0 + $1.predicted }, seen = runs.reduce(0) { $0 + $1.deaths }
        return (min(4, max(0.25, (seen + 1) / (predicted + 1))), runs.count)
    }
}
