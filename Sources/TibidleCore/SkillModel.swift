import Foundation

/// Evaluates the arithmetic formulas the game publishes for each spell
/// (e.g. `((level / 5) + (maglevel * 2.203) + 13)`). Only numbers, names, + - * / and parentheses.
public enum FormulaEvaluator {
    public static func evaluate(_ text: String, variables: [String: Double]) -> Double? {
        var parser = Parser(chars: Array(text), variables: variables)
        guard let value = parser.expression(), parser.finished(), value.isFinite else { return nil }
        return value
    }

    private struct Parser {
        let chars: [Character]
        let variables: [String: Double]
        var index = 0

        init(chars: [Character], variables: [String: Double]) {
            self.chars = chars
            self.variables = variables
        }

        mutating func finished() -> Bool { space(); return index >= chars.count }

        mutating func space() { while index < chars.count, chars[index].isWhitespace { index += 1 } }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                space()
                guard index < chars.count, chars[index] == "+" || chars[index] == "-" else { return value }
                let op = chars[index]
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
        }

        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while true {
                space()
                guard index < chars.count, chars[index] == "*" || chars[index] == "/" else { return value }
                let op = chars[index]
                index += 1
                guard let rhs = factor() else { return nil }
                if op == "/" && rhs == 0 { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
        }

        mutating func factor() -> Double? {
            space()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c == "-" { index += 1; return factor().map { -$0 } }
            if c == "(" {
                index += 1
                guard let value = expression() else { return nil }
                space()
                guard index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return value
            }
            if c.isNumber || c == "." {
                let start = index
                while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
                return Double(String(chars[start..<index]))
            }
            if c.isLetter || c == "_" {
                let start = index
                while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "_" { index += 1 }
                return variables[String(chars[start..<index])]
            }
            return nil
        }
    }
}

/// The game's public spell list (`/spells`), reduced to what the damage model needs.
public struct SpellCatalog {
    public struct Spell: Equatable {
        public let name: String
        public let vocations: [String]
        public let level: Int
        public let mana: Double
        public let cooldownMs: Double
        public let groupCooldownMs: Double
        public let group: String
        public let combatType: String
        public let area: Bool
        public let areaCells: Int
        public let formulaType: String      // "skill" | "levelmagic"
        public let minFormula: String
        public let maxFormula: String
        public let isRune: Bool
        public let secondaryGroup: String?
        public let secondaryCooldownMs: Double
    }

    public static let url = URL(string: "https://play.tibidle.com/spells")!
    public static let empty = SpellCatalog(spells: [])

    public let spells: [Spell]
    private let byName: [String: Spell]

    public init(spells: [Spell]) {
        self.spells = spells
        byName = Dictionary(spells.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    public init?(json: Data) {
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]], !list.isEmpty else { return nil }
        let spells = list.compactMap { item -> Spell? in
            guard item["available"] as? Bool != false, let name = item["name"] as? String,
                  let type = item["combatType"] as? String, type != "COMBAT_HEALING",
                  let formula = item["formula"] as? [String: Any], let lo = formula["min"] as? String, let hi = formula["max"] as? String,
                  let formulaType = item["formulaType"] as? String else { return nil }
            func number(_ key: String) -> Double { (item[key] as? NSNumber)?.doubleValue ?? 0 }
            return Spell(name: name, vocations: (item["vocations"] as? [String] ?? []).map { $0.lowercased() },
                         level: Int(number("level")), mana: number("mana"), cooldownMs: number("cooldownMs"),
                         groupCooldownMs: number("groupCooldownMs"), group: item["group"] as? String ?? "attack",
                         combatType: type, area: item["area"] is String, areaCells: Int(number("areaCells")),
                         formulaType: formulaType, minFormula: lo, maxFormula: hi, isRune: item["isRune"] as? Bool == true,
                         secondaryGroup: item["secondaryGroup"] as? String, secondaryCooldownMs: number("secondaryGroupCooldownMs"))
        }
        guard !spells.isEmpty else { return nil }
        self.init(spells: spells)
    }

    public func spell(named name: String) -> Spell? { byName[name.lowercased()] }

    /// True when a (possibly promoted, e.g. "Elite Knight") vocation may cast the spell.
    public func castable(_ spell: Spell, vocation: String, level: Int) -> Bool {
        let base = SkillAdvisor.baseVocation(vocation)
        return spell.level <= level && spell.vocations.contains { $0.hasSuffix(base) }
    }
}

/// Elemental damage taken per creature, from the game's bestiary (`/bestiary/creature?name=`).
/// `percent` is a resistance: ≥100 immune, >0 resists, 0 neutral, <0 weak.
public struct CreatureCatalog {
    public var resistance: [String: [String: Double]] = [:]   // lowercase name -> combatType -> resistance %
    /// Health per creature (lowercase name), from the maps' monster lists: what a kill costs in damage.
    public var health: [String: Double] = [:]

    public init() {}

    public func health(of creature: String) -> Double? { health[creature.lowercased()] }

    public mutating func add(name: String, elements: [[String: Any]]) {
        var map: [String: Double] = [:]
        for element in elements {
            if let type = element["type"] as? String, let percent = (element["percent"] as? NSNumber)?.doubleValue { map[type] = percent }
        }
        resistance[name.lowercased()] = map
    }

    public func multiplier(creature: String, type: String) -> Double? {
        guard let map = resistance[creature.lowercased()] else { return nil }
        return max(0, (100 - (map[type] ?? 0)) / 100)
    }

    public func knows(_ creature: String) -> Bool { resistance[creature.lowercased()] != nil }
}

public enum SkillAdvisor {
    public static let assumedAttack = 40.0

    public static func baseVocation(_ vocation: String) -> String {
        let v = vocation.lowercased()
        for base in ["knight", "paladin", "sorcerer", "druid", "monk"] where v.contains(base) { return base }
        return v
    }

    public struct Member {
        public let name: String
        public let vocation: String
        public let level: Int
        public let melee: Double, distance: Double, magic: Double
        public let attack: Double?
        public let kit: [String]            // equipped attack spells, in the configured priority order
        public let minCreatures: [String: Int]
    }

    /// Below this share of the hunt's damage going to monsters whose resistances are known, an element verdict
    /// ("causa só 30% do dano") rests on too few of them to be said.
    public static let minAlertCoverage = 0.5

    struct Context {
        init(spells: SpellCatalog, creatures: CreatureCatalog, kills: [String: Double], crowd: Int) {
            self.spells = spells; self.creatures = creatures; self.kills = kills; self.crowd = crowd
            // Every simulation asks for the same few combat types: weigh the kills once per type.
            var cache: [String: (multiplier: Double, coverage: Double)] = [:]
            for type in Set(spells.spells.map(\.combatType)) { cache[type] = Self.weigh(type, creatures: creatures, kills: kills) }
            self.cache = cache
        }
        let spells: SpellCatalog
        let creatures: CreatureCatalog
        let kills: [String: Double]
        let crowd: Int
        private let cache: [String: (multiplier: Double, coverage: Double)]

        /// The share of normal damage a combat type does to the hunt's monsters, and the share of the hunt's damage
        /// that went to monsters whose resistances are known (the multiplier only averages those).
        func weighted(_ type: String) -> (multiplier: Double, coverage: Double) {
            cache[type] ?? Self.weigh(type, creatures: creatures, kills: kills)
        }

        /// What a simulation should expect per cast: monsters of unknown resistance taken as neutral.
        func expected(_ type: String) -> Double {
            let (multiplier, coverage) = weighted(type)
            return coverage * multiplier + (1 - coverage)
        }

        /// Damage goes into health: one kill of a dragon (8350) takes as much as ten of a lich (880), so each kind of
        /// monster weighs by its kills times its health. Without the health of a monster, the average of the others
        /// stands in; with none known, every kill weighs the same.
        static func weigh(_ type: String, creatures: CreatureCatalog, kills: [String: Double]) -> (multiplier: Double, coverage: Double) {
            let healths = kills.keys.compactMap { creatures.health(of: $0) }.filter { $0 > 0 }
            let typical = healths.isEmpty ? 1 : healths.reduce(0, +) / Double(healths.count)
            var sum = 0.0, total = 0.0, known = 0.0
            for (name, count) in kills where count > 0 {
                let weight = count * (creatures.health(of: name).flatMap { $0 > 0 ? $0 : nil } ?? typical)
                total += weight
                if let m = creatures.multiplier(creature: name, type: type) { sum += m * weight; known += weight }
            }
            return known > 0 ? (sum / known, total > 0 ? known / total : 0) : (1, 0)
        }
    }

    /// Damage of one cast (mid roll, before the elemental modifier); nil without a usable formula.
    public static func baseDamage(_ spell: SpellCatalog.Spell, member: Member) -> Double? {
        let skill = baseVocation(member.vocation) == "paladin" ? member.distance : member.melee
        let vars: [String: Double] = ["level": Double(member.level), "maglevel": member.magic, "skill": skill,
                                      "attack": member.attack ?? assumedAttack]
        guard let lo = FormulaEvaluator.evaluate(spell.minFormula, variables: vars),
              let hi = FormulaEvaluator.evaluate(spell.maxFormula, variables: vars) else { return nil }
        return max(0, (lo + hi) / 2)
    }

    struct Rotation {
        var damagePerSecond = 0.0
        var manaPerMinute = 0.0
        var share: [String: Double] = [:]      // spell -> damage per second
    }

    /// No cast frees a spell or a group sooner than this (guards spells without a cooldown).
    static let minLockMs = 500.0

    /// Greedy rotation: as soon as the kit can cast, the first spell in priority order that is ready and whose
    /// creature threshold the pull meets is cast (the game's own rule). A cast locks the spell for its cooldown,
    /// its group (all attacks) for the group cooldown and its secondary group for that one: the strong strikes
    /// share "special" (8 s) and the ultimates "focus" (40 s), so two of them never go out back to back.
    static func simulate(kit: [String], member: Member, context: Context, seconds: Double = 120) -> Rotation {
        let spells = kit.compactMap { context.spells.spell(named: $0) }
        guard !spells.isEmpty else { return Rotation() }
        // Damage per cast is constant over the simulation: evaluate formulas and resistances once per spell.
        let casts: [(spell: SpellCatalog.Spell, damage: Double)] = spells.compactMap { spell in
            guard Double(context.crowd) >= Double(member.minCreatures[spell.name] ?? 1),
                  let base = baseDamage(spell, member: member) else { return nil }
            let targets = spell.area ? Double(min(context.crowd, max(1, spell.areaCells))) : 1
            return (spell, base * context.expected(spell.combatType) * targets)
        }
        var ready: [String: Double] = [:], locked: [String: Double] = [:]
        func free(_ spell: SpellCatalog.Spell) -> Double {
            max(ready[spell.name] ?? 0, locked[spell.group] ?? 0, spell.secondaryGroup.map { locked[$0] ?? 0 } ?? 0)
        }
        var rotation = Rotation()
        var time = 0.0, mana = 0.0
        let end = seconds * 1000
        while time < end {
            if let (spell, damage) = casts.first(where: { free($0.spell) <= time }) {
                rotation.share[spell.name, default: 0] += damage
                rotation.damagePerSecond += damage
                mana += spell.mana
                ready[spell.name] = time + max(spell.cooldownMs, Self.minLockMs)
                locked[spell.group] = time + max(spell.groupCooldownMs, Self.minLockMs)
                if let secondary = spell.secondaryGroup {
                    locked[secondary] = max(locked[secondary] ?? 0, time + max(spell.secondaryCooldownMs, Self.minLockMs))
                }
            }
            // Jump to the next moment anything in the kit is ready (a cast always locks the group past now).
            guard let next = casts.map({ free($0.spell) }).min(), next > time else { break }
            time = next
        }
        rotation.damagePerSecond /= seconds
        rotation.share = rotation.share.mapValues { $0 / seconds }
        rotation.manaPerMinute = mana / seconds * 60
        return rotation
    }

    /// Modeled party damage per second for each assumed crowd size (used to calibrate against real damage).
    public static func modeledDPS(members: [Member], spells: SpellCatalog, creatures: CreatureCatalog,
                                  kills: [String: Double], crowds: [Int]) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for crowd in crowds {
            let context = Context(spells: spells, creatures: creatures, kills: kills, crowd: crowd)
            out[crowd] = members.reduce(0) { $0 + simulate(kit: $1.kit, member: $1, context: context).damagePerSecond }
        }
        return out
    }

    public struct Calibration: Equatable {
        public var crowd: Int
        public var factor: Double
        public var samples: Int
        public static let none = Calibration(crowd: 3, factor: 1, samples: 0)
    }

    /// Picks the crowd size whose predictions best match real damage across past hunts and the
    /// residual scale on top of it. `runs`: (predicted dps per crowd size, real dps).
    public static func calibrate(_ runs: [(predicted: [Int: Double], actual: Double)]) -> Calibration {
        let usable = runs.filter { $0.actual > 0 }
        guard usable.count >= 3 else { return .none }
        var best: (crowd: Int, factor: Double, spread: Double)?
        for crowd in Set(usable.flatMap { $0.predicted.keys }).sorted() {
            let ratios = usable.compactMap { run -> Double? in
                guard let p = run.predicted[crowd], p > 0 else { return nil }
                return run.actual / p
            }
            guard ratios.count == usable.count else { continue }
            let median = percentile(ratios, 0.5)
            let spread = percentile(ratios.map { abs(log($0 / median)) }, 0.5)
            if best == nil || spread < best!.spread { best = (crowd, median, spread) }
        }
        guard let best else { return .none }
        return Calibration(crowd: best.crowd, factor: best.factor, samples: usable.count)
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
    }

    /// Full analysis for the dashboard: per-member skill table, verdicts and swap suggestions.
    public static func analyze(members: [Member], spells: SpellCatalog, creatures: CreatureCatalog,
                               kills: [String: Double], calibration: Calibration) -> [String: Any] {
        let total = kills.values.reduce(0, +)
        let known = kills.filter { creatures.knows($0.key) }.values.reduce(0, +)
        var result: [String: Any] = ["crowd": calibration.crowd, "calibrated": calibration.samples > 0,
                                     "samples": calibration.samples, "factor": calibration.factor,
                                     "coverage": total > 0 ? known / total : 0]
        let context = Context(spells: spells, creatures: creatures, kills: kills, crowd: calibration.crowd)
        var rows: [[String: Any]] = []
        for member in members {
            let current = simulate(kit: member.kit, member: member, context: context)
            var skills: [[String: Any]] = []
            for name in member.kit {
                guard let spell = spells.spell(named: name) else { continue }
                let (multiplier, coverage) = context.weighted(spell.combatType)
                var row: [String: Any] = ["name": spell.name, "element": spell.combatType, "multiplier": multiplier,
                                          "coverage": coverage, "mana": spell.mana, "cooldown": spell.cooldownMs / 1000,
                                          "dps": (current.share[spell.name] ?? 0) * calibration.factor]
                if let base = baseDamage(spell, member: member) { row["perCast"] = base * multiplier }
                if multiplier < 0.5 && coverage >= minAlertCoverage { row["warning"] = "Maioria dos alvos resiste a este elemento." }
                else if (current.share[spell.name] ?? 0) == 0 && multiplier > 0 {
                    row["warning"] = "Nunca dispara: uma skill de prioridade maior (ou do mesmo grupo de recarga) está sempre pronta, " +
                        "ou o mínimo de criaturas não é atingido."
                } else if multiplier >= 1.1 && coverage >= minAlertCoverage { row["note"] = "Elemento forte contra os alvos." }
                skills.append(row)
            }
            var entry: [String: Any] = ["name": member.name, "vocation": member.vocation, "skills": skills,
                                        "dps": current.damagePerSecond * calibration.factor, "manaPerMinute": current.manaPerMinute,
                                        "unknownSkills": member.kit.filter { spells.spell(named: $0) == nil }]
            entry["suggestions"] = suggestions(member: member, current: current, context: context, spells: spells)
            rows.append(entry)
        }
        result["members"] = rows
        return result
    }

    static func suggestions(member: Member, current: Rotation, context: Context, spells: SpellCatalog) -> [[String: Any]] {
        guard !context.kills.isEmpty else { return [] }
        let fromZero = current.damagePerSecond <= 0
        let candidates = spells.spells.filter {
            !$0.isRune && $0.group == "attack" && !member.kit.contains($0.name)
                && spells.castable($0, vocation: member.vocation, level: member.level)
        }
        var found: [(gain: Double, text: [String: Any])] = []
        // Replace one equipped spell, or add one when the kit has a free slot.
        for candidate in candidates {
            var options: [(kit: [String], replaced: String?)] = [(member.kit + [candidate.name], nil)]
            for slot in member.kit.indices {
                var kit = member.kit
                let replaced = kit[slot]
                kit[slot] = candidate.name
                options.append((kit, replaced))
            }
            for option in options where option.kit.count <= 8 {
                let rotation = simulate(kit: option.kit, member: member, context: context)
                guard rotation.damagePerSecond > 0 else { continue }
                let gain = fromZero ? 10 : min(10, rotation.damagePerSecond / current.damagePerSecond - 1)
                guard gain >= 0.08 else { continue }
                let manaDelta = rotation.manaPerMinute - current.manaPerMinute
                found.append((gain, ["add": candidate.name, "replace": option.replaced as Any, "gain": gain, "fromZero": fromZero,
                                     "manaPerMinuteDelta": manaDelta, "manaPerMinute": rotation.manaPerMinute,
                                     "currentManaPerMinute": current.manaPerMinute,
                                     "multiplier": context.weighted(candidate.combatType).multiplier]))
            }
        }
        // Best per added spell, at most three suggestions.
        var seen = Set<String>()
        return found.sorted { $0.gain > $1.gain }.compactMap { item in
            let name = item.text["add"] as? String ?? ""
            return seen.insert(name).inserted ? item.text : nil
        }.prefix(3).map { $0 }
    }
}

/// Average mana and health of each party member over the current hunt, from the live frames
/// (who runs dry, who takes the hits).
public struct VitalsTracker {
    private var mana: [String: (sum: Double, count: Int)] = [:]
    private var hp: [String: (sum: Double, count: Int, lowest: Double)] = [:]
    public static let minSamples = 20

    public init() {}

    static func key(name: String, vocation: String) -> String { "\(name)|\(SkillAdvisor.baseVocation(vocation))" }

    public mutating func add(party: [[String: Any]]) {
        func fraction(_ member: [String: Any], _ value: String, _ limit: String) -> Double? {
            guard let v = (member[value] as? NSNumber)?.doubleValue, let m = (member[limit] as? NSNumber)?.doubleValue, m > 0 else { return nil }
            return max(0, min(1, v / m))
        }
        for member in party {
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String else { continue }
            let key = Self.key(name: name, vocation: vocation)
            if let m = fraction(member, "mana", "maxMana") {
                let total = mana[key] ?? (0, 0)
                mana[key] = (total.sum + m, total.count + 1)
            }
            if let h = fraction(member, "hp", "maxHp") {
                let total = hp[key] ?? (0, 0, 1)
                hp[key] = (total.sum + h, total.count + 1, min(total.lowest, h))
            }
        }
    }

    /// Mean mana fraction (0...1) per member, once there are enough frames to mean something.
    public func averages() -> [String: Double] {
        mana.filter { $0.value.count >= Self.minSamples }.mapValues { $0.sum / Double($0.count) }
    }

    /// Mean and lowest health fraction per member.
    public func health() -> [String: (average: Double, lowest: Double)] {
        hp.filter { $0.value.count >= Self.minSamples }.mapValues { ($0.sum / Double($0.count), $0.lowest) }
    }

    /// The party with `hpAverage`/`hpLowest` on each member the tracker has enough frames for.
    public func annotate(party: [[String: Any]]) -> [[String: Any]] {
        let health = health()
        guard !health.isEmpty else { return party }
        return party.map { member in
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String,
                  let h = health[Self.key(name: name, vocation: vocation)] else { return member }
            var out = member
            out["hpAverage"] = h.average
            out["hpLowest"] = h.lowest
            return out
        }
    }
}

/// A suggestion that spends more mana is worth less when the member already runs dry: it means more potions
/// (supplies) or the rotation stalling. For those members the mana spent now is taken as all there is: a kit that
/// wants more casts proportionally less, so its gain is what it does with the same mana (`gain`, the simulated one
/// kept as `rawGain`), and a swap that is no longer worth it is dropped.
public enum ManaBudget {
    public static let low = 0.25
    /// The smallest gain a suggestion needs (as in `SkillAdvisor.suggestions`).
    static let minGain = 0.08

    public static func apply(_ analysis: [String: Any], averages: [String: Double]) -> [String: Any] {
        guard !averages.isEmpty, let members = analysis["members"] as? [[String: Any]] else { return analysis }
        var result = analysis
        result["members"] = members.map { member -> [String: Any] in
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String,
                  let average = averages[VitalsTracker.key(name: name, vocation: vocation)] else { return member }
            var out = member
            out["manaAverage"] = average
            if average < low, let suggestions = member["suggestions"] as? [[String: Any]] {
                var adjusted = false
                let kept = suggestions.compactMap { suggestion -> [String: Any]? in
                    var item = suggestion
                    guard number(suggestion["manaPerMinuteDelta"]) > 0 else { return item }
                    item["manaLimited"] = true
                    let now = number(suggestion["currentManaPerMinute"]), then = number(suggestion["manaPerMinute"])
                    guard suggestion["fromZero"] as? Bool != true, now > 0, then > now, let gain = suggestion["gain"] as? Double else { return item }
                    adjusted = true
                    let sustainable = (1 + gain) * now / then - 1
                    guard sustainable >= minGain else { return nil }
                    item["rawGain"] = gain
                    item["gain"] = sustainable
                    return item
                }
                // Best first again, ties in their original order.
                out["suggestions"] = adjusted
                    ? kept.enumerated().sorted { (number($0.element["gain"]), -$0.offset) > (number($1.element["gain"]), -$1.offset) }.map(\.element)
                    : kept
            }
            return out
        }
        return result
    }

    private static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
}
