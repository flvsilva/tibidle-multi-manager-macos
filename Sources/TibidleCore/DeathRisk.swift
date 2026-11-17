import Foundation

/// Chance that someone in the party dies, from the hunt's own health: every posted frame (about 3 s apart) gives,
/// per party member, the health at the start of the window and how much of it was lost by the end, healing
/// included (a knight can take 1600 in 3 s and heal most of it, so the hits alone say too much). The largest are
/// fitted with a tail (peaks over a threshold), which tells how likely a window bigger than any seen
/// so far is; the chance that a window outdoes the health the member had at its start, summed over an hour of
/// windows, is the risk. It is put together with the map's deaths per hour near the level, which stand in alone
/// before there is enough of the hunt.
/// Who a party slot holds: the character's name and vocation when the game gives them (the accounts name their
/// members alike, the vocation tells them apart), so another member taking a slot starts a record of its own instead
/// of reading as a loss or a gain; the position otherwise.
enum PartyKey {
    static func keyed(_ party: [[String: Any]]) -> [(position: Int, key: String, member: [String: Any])] {
        var used = Set<String>()
        return party.enumerated().map { position, member in
            var key = "#\(position)"
            if let name = member["name"] as? String, !name.isEmpty {
                key = "\(name)|\(SkillAdvisor.baseVocation(member["vocation"] as? String ?? ""))"
                if used.contains(key) { key += "#\(position)" }
            }
            used.insert(key)
            return (position, key, member)
        }
    }
}

public struct DeathRisk {
    struct Window { let date: Date; let health: Double; let lost: Double; let seconds: Double }

    /// The windows weighed: the last 20 minutes, the latest counting most (half-life of 5 minutes).
    static let keep = 20 * 60.0
    static let halfLife = 5 * 60.0
    /// Enough of the hunt to say something: 10 minutes of windows, some of them losing health.
    static let minWindows = 200
    static let minHurt = 20
    /// The largest tenth of the losses make the tail, and never fewer than `minExceedances` of them.
    static let tailQuantile = 0.9
    static let minExceedances = 10
    /// Stored with each hunt's prediction, so the calibration only weighs hunts predicted the same way
    /// (3: shape fitted on all windows, windows timed as they happened, live weight growing with the hunt).
    static let model = 3
    /// Above these the hunt is flagged, and notified.
    public static let warnPerHour = 0.05
    public static let alertPerHour = 0.10

    private var windows: [String: [Window]] = [:]
    private var health: [String: Double] = [:]
    private var maxHealth: [String: Double] = [:]
    private var vocations: [String: String] = [:]
    private var positions: [String: Int] = [:]
    private var seen: [String: Date] = [:]
    private var last: Date?
    /// Deaths the uncalibrated estimate expected over the hunt so far (rate × time), for the calibration.
    private(set) var expected = 0.0
    private(set) var covered = 0.0
    private var accrued: Date?
    /// Since when the live estimate has stayed at the warning level or above (checked with `accrue`).
    private(set) var highSince: Date?

    public init() {}

    /// Adds the estimate's expected deaths since the last call (about once a minute), for the hunt summary.
    mutating func accrue(now: Date) {
        guard let accrued else { accrued = now; return }
        guard now.timeIntervalSince(accrued) >= 60 else { return }
        self.accrued = now
        let seconds = min(now.timeIntervalSince(accrued), 300)
        guard let rate = estimate(now: now)?["rate"] as? Double else { highSince = nil; return }
        expected += rate * seconds / 3600
        covered += seconds
        if 1 - exp(-rate) >= Self.warnPerHour { highSince = highSince ?? now } else { highSince = nil }
    }

    /// One posted frame: the party as it is now. The window since the last frame is the health lost in between.
    public mutating func add(party: [[String: Any]], at date: Date) {
        let previous = last
        let elapsed = previous.map { date.timeIntervalSince($0) } ?? 0
        last = date
        // A gap (app paused, reconnect) is not one window: only frames about 3 s apart count, and only for a member
        // who was in the previous frame too.
        let counts = elapsed > 0 && elapsed <= 10
        for (position, key, member) in PartyKey.keyed(party) {
            guard let hp = HuntInsights.number(member["hp"]), let maxHp = HuntInsights.number(member["maxHp"]), maxHp > 0 else { continue }
            if counts, seen[key] == previous, let start = health[key] {
                windows[key, default: []].append(Window(date: date, health: start, lost: max(0, start - hp), seconds: elapsed))
            }
            health[key] = hp
            maxHealth[key] = maxHp
            vocations[key] = member["vocation"] as? String
            positions[key] = position
            seen[key] = date
        }
        for key in windows.keys { windows[key]?.removeAll { date.timeIntervalSince($0.date) > Self.keep } }
        windows = windows.filter { !$0.value.isEmpty }
    }

    /// The largest losses: the top tenth, or `minExceedances` if that is more, as excesses over the largest loss
    /// left out. A loss equal to that one is an excess of zero, so many equal losses still leave a tail.
    struct Excess { let threshold: Double; let weight: Double; let mean: Double; let variance: Double; let count: Int }
    static func excess(_ weighed: [(loss: Double, weight: Double)]) -> Excess? {
        let n = weighed.count
        guard n > 0 else { return nil }
        let k = min(n, max(minExceedances, Int((Double(n) * (1 - tailQuantile)).rounded(.up))))
        let top = weighed[(n - k)...]
        let threshold = n > k ? weighed[n - k - 1].loss : 0
        let weight = top.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        let mean = top.reduce(0) { $0 + ($1.loss - threshold) * $1.weight } / weight
        guard mean > 0 else { return nil }
        let variance = top.reduce(0) { $0 + pow($1.loss - threshold - mean, 2) * $1.weight } / weight
        return Excess(threshold: threshold, weight: weight, mean: mean, variance: variance, count: k)
    }

    static func weighed(_ windows: [Window], now: Date) -> [(loss: Double, weight: Double)] {
        windows.map { ($0.lost, pow(0.5, now.timeIntervalSince($0.date) / halfLife)) }.sorted { $0.loss < $1.loss }
    }

    /// The tail's shape, from all of a member's windows: how heavy the biggest losses run is a matter of what hits
    /// the party, not of the health a window started from, and it takes many excesses to tell. Fitted by moments and
    /// kept between -0.5 (a hard ceiling not far past the largest loss, as when a few monsters can only hit so much)
    /// and 0.25 (heavier than exponential); exponential while there are too few excesses, a ceiling when all alike.
    static func shape(_ windows: [Window], now: Date) -> Double {
        guard let excess = excess(weighed(windows, now: now)), excess.count >= minExceedances else { return 0 }
        guard excess.variance > 0 else { return -0.5 }
        return min(0.25, max(-0.5, 0.5 * (1 - excess.mean * excess.mean / excess.variance)))
    }

    /// Chance, per window, that the health lost is at least `x`: the measured share below the threshold, and above
    /// it a generalized Pareto tail with the member's shape and these windows' own scale (the mean excess of the
    /// distribution is scale / (1 − shape)).
    static func tail(_ windows: [Window], now: Date, shape: Double) -> (Double) -> Double {
        // Losses sorted with their weight, and the weight from each one up: "at least x" is one binary search.
        let weighed = weighed(windows, now: now)
        guard !weighed.isEmpty else { return { _ in 0 } }
        var from = [Double](repeating: 0, count: weighed.count + 1)
        for i in stride(from: weighed.count - 1, through: 0, by: -1) { from[i] = from[i + 1] + weighed[i].weight }
        let total = from[0]
        let measured = { (x: Double) -> Double in
            var low = 0, high = weighed.count
            while low < high { let mid = (low + high) / 2; if weighed[mid].loss < x { low = mid + 1 } else { high = mid } }
            return from[low] / total
        }
        guard let excess = excess(weighed) else { return measured }
        let share = excess.weight / total
        let scale = max(1, excess.mean * (1 - shape))
        return { x in
            guard x > excess.threshold else { return measured(x) }
            let z = (x - excess.threshold) / scale
            if abs(shape) < 1e-9 { return share * exp(-z) }
            let base = 1 + shape * z
            return base <= 0 ? 0 : share * pow(base, -1 / shape)
        }
    }

    /// How much is lost in 3 s depends on the health at the start: a party at 40% is being healed hard and rarely
    /// loses more, the big losses come from near full health. So each window is judged against the windows that
    /// started in the same tenth of the health (and the next ones, until there are `minBand` of them).
    static let minBand = 80

    /// Per member, the chance of dying in the next hour, and the party's; nil before there is enough of the hunt.
    public func estimate(now: Date) -> [String: Any]? {
        var members: [[String: Any]] = []
        var rate = 0.0
        for (key, list) in windows {
            guard list.count >= Self.minWindows, list.filter({ $0.lost > 0 }).count >= Self.minHurt,
                  let maxHp = maxHealth[key], maxHp > 0 else { continue }
            let shape = Self.shape(list, now: now)
            let band = { (w: Window) in min(9, max(0, Int(10 * w.health / maxHp))) }
            let bands = Dictionary(grouping: list, by: band)
            var tails: [Int: (Double) -> Double] = [:]
            for b in bands.keys {
                var near: [Window] = []
                for width in 0...9 {
                    near = bands.filter { abs($0.key - b) <= width }.flatMap(\.value)
                    if near.count >= Self.minBand { break }
                }
                tails[b] = Self.tail(near, now: now, shape: shape)
            }
            // The health each window started from, as it happened. Windows that started dead are not a new risk.
            let alive = list.filter { $0.health > 0 }
            let weights = alive.map { pow(0.5, now.timeIntervalSince($0.date) / Self.halfLife) }
            let total = max(1e-9, weights.reduce(0, +))
            let perWindow = zip(alive, weights).reduce(0) { $0 + tails[band($1.0)]!($1.0.health) * $1.1 } / total
            // Each window as long as it was: pauses never make a window, so they do not stretch the hour either.
            let seconds = zip(alive, weights).reduce(0) { $0 + $1.0.seconds * $1.1 } / total
            let perHour = perWindow * 3600 / max(1, seconds)
            rate += perHour
            let lowest = list.map(\.health).min() ?? 0
            members.append(["position": positions[key] ?? 0, "vocation": vocations[key] ?? "", "perHour": 1 - exp(-perHour),
                            "biggestWindow": Int(list.map(\.lost).max() ?? 0), "lowestHealth": Int(lowest),
                            "maxHealth": Int(maxHp)])
        }
        guard !members.isEmpty else { return nil }
        let measured = windows.values.map { $0.reduce(0) { $0 + $1.seconds } }.max() ?? 0
        return ["perHour": 1 - exp(-rate), "rate": rate, "source": "live", "minutes": Int(measured / 60),
                "members": members.sorted {
                    ($0["perHour"] as? Double ?? 0, -($0["position"] as? Int ?? 0)) > ($1["perHour"] as? Double ?? 0, -($1["position"] as? Int ?? 0))
                }]
    }

    /// The live estimate is a fit over the last minutes; the map's deaths near this level are hours of what
    /// happened. Both are put together as deaths over hours, the live rate counting as `liveHours` of hunting. The
    /// overall rate stands in for a map's own history (10 h of it, as in `fromHistory`) only while there is little of
    /// it: on a map never hunted, the hunt in progress is what there is (2 h of the overall rate is left as a prior).
    static let liveHours = 10.0
    static let maxLiveHours = 30.0
    static func combined(live rate: Double, deaths: Double, hours: Double, overallRate: Double, liveHours: Double = liveHours) -> Double {
        let prior = 2 + 8 * min(1, hours / 10)
        return (deaths + prior * overallRate + rate * liveHours) / (hours + prior + liveHours)
    }

    /// A live rate this long at the warning level or above is no scare: the map's quiet history does not bury it.
    static let sustained = 30 * 60.0

    /// `combined` for this hunt: the live rate weighs 10 h to begin with and three times the hours it has been
    /// measured once that is more, up to 30 h (a party measured all afternoon is known); and a rate that has stayed
    /// at the warning level for 30 minutes keeps a third of itself at least, however many quiet hours the map has.
    public func combined(live rate: Double, deaths: Double, hours: Double, overallRate: Double, now: Date) -> Double {
        let weight = min(Self.maxLiveHours, max(Self.liveHours, 3 * covered / 3600))
        let blend = Self.combined(live: rate, deaths: deaths, hours: hours, overallRate: overallRate, liveHours: weight)
        guard let highSince, now.timeIntervalSince(highSince) >= Self.sustained else { return blend }
        return max(blend, rate / 3)
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

/// The moments someone fell below 40% of the health this hunt: when, how low, how long until back above 60%, and
/// what was hitting the party in the seconds before the lowest point. Shows why the death risk is what it is.
public struct DangerTracker {
    static let below = 0.40, recovered = 0.60
    static let keep = 30
    struct Dip {
        var start: Date; var at: Date; var lowest: Double; var health: Double; var maxHealth: Double; var vocation: String
        var hits: [String: Any]?; var position: Int
    }
    /// Open dips per member (`PartyKey`): another member taking the slot does not inherit a dip.
    private var open: [String: Dip] = [:]
    private(set) var moments: [[String: Any]] = []
    private(set) var count = 0

    public init() {}

    /// One posted frame; `hits` gives what hit the party just before (asked only when a member is at a new low).
    public mutating func add(party: [[String: Any]], at date: Date, hits: () -> [String: Any]?) {
        let keyed = PartyKey.keyed(party)
        // A member who left the party mid-dip: how it ended is unknown.
        let present = Set(keyed.map(\.key))
        for (key, dip) in open where !present.contains(key) { close(dip, end: nil, left: true); open[key] = nil }
        for (position, key, member) in keyed {
            guard let hp = HuntInsights.number(member["hp"]), let maxHp = HuntInsights.number(member["maxHp"]), maxHp > 0 else { continue }
            let share = hp / maxHp
            if var dip = open[key] {
                dip.position = position
                if share < dip.lowest { dip.lowest = share; dip.health = hp; dip.at = date; dip.hits = hits() }
                if share >= Self.recovered { close(dip, end: date); open[key] = nil } else { open[key] = dip }
            } else if share < Self.below {
                open[key] = Dip(start: date, at: date, lowest: share, health: hp, maxHealth: maxHp,
                                vocation: member["vocation"] as? String ?? "", hits: hits(), position: position)
            }
        }
    }

    private mutating func close(_ dip: Dip, end: Date?, left: Bool = false) {
        count += 1
        var moment = Self.json(dip, end: end)
        if left { moment["ongoing"] = nil; moment["left"] = true }
        moments.append(moment)
        if moments.count > Self.keep { moments.removeFirst(moments.count - Self.keep) }
    }

    static func json(_ dip: Dip, end: Date?) -> [String: Any] {
        var out: [String: Any] = ["at": dip.at.timeIntervalSince1970 * 1000, "position": dip.position, "vocation": dip.vocation,
                                  "lowest": (dip.lowest * 1000).rounded() / 1000, "health": Int(dip.health), "maxHealth": Int(dip.maxHealth)]
        if let end { out["seconds"] = Int(end.timeIntervalSince(dip.start).rounded()) } else { out["ongoing"] = true }
        if let creatures = dip.hits?["creatures"] as? [[String: Any]], !creatures.isEmpty { out["creatures"] = Array(creatures.prefix(3)) }
        return out
    }

    /// The moments, newest first, with a dip still going on; and how many there were in the hunt.
    public func summary() -> [String: Any]? {
        let current = open.values.map { Self.json($0, end: nil) }
        guard count + current.count > 0 else { return nil }
        return ["count": count + current.count,
                "moments": (moments + current).sorted { (HuntInsights.number($0["at"]) ?? 0) > (HuntInsights.number($1["at"]) ?? 0) }]
    }
}
