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

    public init() {}

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

    struct Context {
        init(spells: SpellCatalog, creatures: CreatureCatalog, kills: [String: Double], crowd: Int) {
            self.spells = spells; self.creatures = creatures; self.kills = kills; self.crowd = crowd
        }
        let spells: SpellCatalog
        let creatures: CreatureCatalog
        let kills: [String: Double]
        let crowd: Int
        func weighted(_ type: String) -> (multiplier: Double, coverage: Double) {
            var sum = 0.0, total = 0.0, known = 0.0
            for (name, count) in kills {
                total += count
                if let m = creatures.multiplier(creature: name, type: type) { sum += m * count; known += count }
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

    /// Greedy rotation: every shared-group tick the first spell, in priority order, that is off cooldown
    /// and whose creature threshold the pull meets is cast (the game's own rule).
    static func simulate(kit: [String], member: Member, context: Context, seconds: Double = 120) -> Rotation {
        let spells = kit.compactMap { context.spells.spell(named: $0) }
        guard !spells.isEmpty else { return Rotation() }
        let tick = max(500, spells.map(\.groupCooldownMs).min() ?? 2000)
        var ready: [String: Double] = [:]
        var rotation = Rotation()
        var time = 0.0, mana = 0.0
        while time < seconds * 1000 {
            for spell in spells {
                let need = Double(member.minCreatures[spell.name] ?? 1)
                if Double(context.crowd) < need { continue }
                if (ready[spell.name] ?? 0) > time { continue }
                guard let base = baseDamage(spell, member: member) else { continue }
                let targets = spell.area ? Double(min(context.crowd, max(1, spell.areaCells))) : 1
                let damage = base * context.weighted(spell.combatType).multiplier * targets
                rotation.share[spell.name, default: 0] += damage
                rotation.damagePerSecond += damage
                mana += spell.mana
                ready[spell.name] = time + max(spell.cooldownMs, tick)
                break
            }
            time += tick
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
                if multiplier < 0.5 && coverage > 0.3 { row["warning"] = "Maioria dos alvos resiste a este elemento." }
                else if (current.share[spell.name] ?? 0) == 0 && multiplier > 0 {
                    row["warning"] = "Nunca dispara: uma skill de prioridade maior está sempre pronta ou o mínimo de criaturas não é atingido."
                } else if multiplier >= 1.1 && coverage > 0.3 { row["note"] = "Elemento forte contra os alvos." }
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
                                     "manaPerMinuteDelta": manaDelta,
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

/// Average mana of each party member over the current hunt, from the live frames.
public struct ManaTracker {
    private var totals: [String: (sum: Double, count: Int)] = [:]
    public static let minSamples = 20

    public init() {}

    static func key(name: String, vocation: String) -> String { "\(name)|\(SkillAdvisor.baseVocation(vocation))" }

    public mutating func add(party: [[String: Any]]) {
        for member in party {
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String,
                  let mana = (member["mana"] as? NSNumber)?.doubleValue, let maxMana = (member["maxMana"] as? NSNumber)?.doubleValue,
                  maxMana > 0 else { continue }
            let key = Self.key(name: name, vocation: vocation)
            let total = totals[key] ?? (0, 0)
            totals[key] = (total.sum + max(0, min(1, mana / maxMana)), total.count + 1)
        }
    }

    /// Mean mana fraction (0...1) per member, once there are enough frames to mean something.
    public func averages() -> [String: Double] {
        totals.filter { $0.value.count >= Self.minSamples }.mapValues { $0.sum / Double($0.count) }
    }
}

/// A suggestion that spends more mana is worth less when the member already runs dry: it means more potions
/// (supplies) or the rotation stalling. This marks those, using the hunt's average mana.
public enum ManaBudget {
    public static let low = 0.25

    public static func apply(_ analysis: [String: Any], averages: [String: Double]) -> [String: Any] {
        guard !averages.isEmpty, let members = analysis["members"] as? [[String: Any]] else { return analysis }
        var result = analysis
        result["members"] = members.map { member -> [String: Any] in
            guard let name = member["name"] as? String, let vocation = member["vocation"] as? String,
                  let average = averages[ManaTracker.key(name: name, vocation: vocation)] else { return member }
            var out = member
            out["manaAverage"] = average
            if average < low, let suggestions = member["suggestions"] as? [[String: Any]] {
                out["suggestions"] = suggestions.map { suggestion -> [String: Any] in
                    var item = suggestion
                    if ((suggestion["manaPerMinuteDelta"] as? NSNumber)?.doubleValue ?? 0) > 0 { item["manaLimited"] = true }
                    return item
                }
            }
            return out
        }
        return result
    }
}
