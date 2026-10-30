/// Equipment upgrades with the most impact, from the gear the collector reads:
/// - defense of whoever takes the hits (the member with the lowest average health), slot by slot, against the
///   best item your other accounts use on the same vocation, scored as damage taken less per second by the
///   game's own rules (wiki "como o dano é calculado"; the server derives from Canary);
/// - the element of a wand or rod against the monsters of the hunt in progress.
/// Items need only the vocation, never a level.
public enum GearAdvisor {
    static let defensiveSlots = ["shield", "head", "armor", "legs", "boots", "necklace", "ring"]
    static let slotNames = ["weapon": "arma", "shield": "escudo", "head": "capacete", "armor": "armadura", "legs": "calça",
                            "boots": "bota", "necklace": "colar", "ring": "anel"]
    /// Below this share of what the tank takes, the swap is noise.
    static let minShare = 0.01
    /// A wand or rod doing less than this share of its damage is the wrong element for the hunt.
    static let weakElement = 0.8
    static let elementNames = ["fire", "energy", "earth", "ice", "holy", "death"]

    /// The game's wands and rods by element, for builds whose gear does not carry `shootType` yet.
    static let wandElements: [String: String] = [
        "wand of vortex": "COMBAT_ENERGYDAMAGE", "wand of cosmic energy": "COMBAT_ENERGYDAMAGE", "wand of starstorm": "COMBAT_ENERGYDAMAGE",
        "wand of defiance": "COMBAT_ENERGYDAMAGE", "wand of dragonbreath": "COMBAT_FIREDAMAGE", "wand of draconia": "COMBAT_FIREDAMAGE",
        "wand of inferno": "COMBAT_FIREDAMAGE", "wand of everblazing": "COMBAT_FIREDAMAGE", "wand of decay": "COMBAT_DEATHDAMAGE",
        "wand of voodoo": "COMBAT_DEATHDAMAGE", "snakebite rod": "COMBAT_EARTHDAMAGE", "terra rod": "COMBAT_EARTHDAMAGE",
        "springsprout rod": "COMBAT_EARTHDAMAGE", "muck rod": "COMBAT_EARTHDAMAGE", "moonlight rod": "COMBAT_ICEDAMAGE",
        "northwind rod": "COMBAT_ICEDAMAGE", "hailstorm rod": "COMBAT_ICEDAMAGE", "glacial rod": "COMBAT_ICEDAMAGE",
        "necrotic rod": "COMBAT_DEATHDAMAGE", "underworld rod": "COMBAT_DEATHDAMAGE",
    ]
    static let shootTypes = ["fire": "COMBAT_FIREDAMAGE", "energy": "COMBAT_ENERGYDAMAGE", "earth": "COMBAT_EARTHDAMAGE", "poison": "COMBAT_EARTHDAMAGE",
                             "ice": "COMBAT_ICEDAMAGE", "death": "COMBAT_DEATHDAMAGE", "holy": "COMBAT_HOLYDAMAGE"]

    struct Item {
        let slot: String
        let name: String
        let stats: [String: Any]
        func number(_ key: String) -> Double { HuntInsights.number(stats["attrs." + key]) ?? 0 }
        var armor: Double { number("armor") }
        var shieldDefense: Double { slot == "shield" ? number("defense") : 0 }
        var shielding: Double { number("skillboost shielding") }
        var physical: Double { number("absorbpercentphysical") }
        /// Protection against one element, in percent: the forge's "elemental protection" and the item's own absorb.
        func protection(_ element: String) -> Double { number("elemental protection " + element) + number("absorbpercent" + element) }

        var summary: String {
            var parts: [String] = []
            for (key, label) in [("armor", "armor"), ("defense", "def")] where number(key) != 0 { parts.append("\(label) \(Int(number(key)))") }
            if number("skillboost shielding") != 0 { parts.append("+\(Int(number("skillboost shielding"))) shielding") }
            if physical != 0 { parts.append("\(Int(physical))% físico") }
            let protections = elementNames.map(protection)
            if let first = protections.first, first != 0, protections.allSatisfy({ $0 == first }) {
                parts.append("\(Int(first))% em cada elemento")
            } else {
                for (element, value) in zip(elementNames, protections) where value != 0 {
                    parts.append("\(Int(value))% \(Attention.elements["COMBAT_\(element.uppercased())DAMAGE"] ?? element)")
                }
            }
            return parts.isEmpty ? name : "\(name) (\(parts.joined(separator: ", ")))"
        }

        var element: String? {
            if let shoot = (stats["attrs.shootType"] as? String)?.lowercased(), let type = shootTypes.first(where: { shoot.contains($0.key) })?.value { return type }
            return wandElements[name.lowercased()]
        }
    }

    struct Member {
        let account: Int
        let label: String
        let vocation: String       // base, uppercase
        let level: Int
        let hpAverage: Double?
        /// Shielding skill; the melee skill stands in before the collector reads it.
        let shielding: Double
        let items: [String: Item]
    }

    /// What hits the tank, per second. Until the hits are read one by one, the party's damage taken with
    /// a typical split: most of it melee on the knight, about two hits a second.
    struct Combat {
        var takenPerSecond: Double
        var hitsPerSecond = 2.0
        var physicalShare = 0.8
        /// Share of the magic damage per element ("fire", "ice"…); empty spreads it evenly.
        var elements: [String: Double] = [:]
    }

    /// Damage the tank stops per second wearing `items`.
    static func stopped(_ items: [String: Item], shielding: Double, combat: Combat) -> Double {
        // Melee hits only: with no physical damage, armor and shield have nothing to work on.
        let hits = combat.physicalShare > 0 ? combat.hitsPerSecond : 0
        let physical = combat.takenPerSecond * combat.physicalShare, magic = combat.takenPerSecond - physical
        let armor = items.values.reduce(0) { $0 + $1.armor }
        let defense = items.values.reduce(0) { $0 + $1.shieldDefense }
        let skill = shielding + items.values.reduce(0) { $0 + $1.shielding }
        // Armor takes between half and nearly all of itself off each melee hit: 0.75 on average.
        let byArmor = 0.75 * armor * hits
        // The shield blocks 0.75 × (Shielding/4 + 2.23) × defense × 0.08 per block, two charges back at one a second.
        let byShield = defense > 0 ? 0.75 * 0.08 * (skill / 4 + 2.23) * defense * min(hits, 1) : 0
        // Physical protection comes first, on the raw hit, before shield and armor take their part.
        let protection = min(0.9, items.values.reduce(0) { $0 + $1.physical } / 100)
        let byProtection = (physical + byArmor + byShield) * protection / (1 - protection)
        // Magic skips shield and armor: only the protection to its element counts.
        let byElement = elementNames.reduce(0.0) { sum, element in
            let share = combat.elements.isEmpty ? 1 / Double(elementNames.count) : combat.elements[element] ?? 0
            let protection = min(0.9, items.values.reduce(0) { $0 + $1.protection(element) } / 100)
            return sum + magic * share * protection / (1 - protection)
        }
        return byArmor + byShield + byProtection + byElement
    }

    static func members(accounts: [[String: Any]]) -> [Member] {
        accounts.flatMap { account -> [Member] in
            let party = ((account["state"] as? [String: Any])?["party"] as? [[String: Any]]) ?? []
            return party.compactMap { member in
                guard let vocation = member["vocation"] as? String, let gear = member["gear"] as? [String: Any], !gear.isEmpty else { return nil }
                var items: [String: Item] = [:]
                for (slot, value) in gear {
                    guard let item = value as? [String: Any], let name = item["name"] as? String else { continue }
                    items[slot] = Item(slot: slot, name: name, stats: item["stats"] as? [String: Any] ?? [:])
                }
                return Member(account: account["index"] as? Int ?? 0, label: account["label"] as? String ?? "",
                              vocation: SkillAdvisor.baseVocation(vocation).uppercased(), level: Int(HuntInsights.number(member["level"]) ?? 1),
                              hpAverage: member["hpAverage"] as? Double, shielding: shielding(member), items: items)
            }
        }
    }

    /// The party's damage taken per second in the hunt so far; a few minutes are needed for a rate.
    static func combat(analyzer: [String: Any]?) -> Combat? {
        guard let analyzer, let elapsed = HuntInsights.number(analyzer["elapsedMs"]), elapsed >= 5 * 60_000,
              let taken = HuntInsights.number(analyzer["damageTaken"]), taken > 0 else { return nil }
        return Combat(takenPerSecond: taken / (elapsed / 1000))
    }

    static func shielding(_ member: [String: Any]) -> Double {
        let skills = member["skillLevels"] as? [String: Any]
        return HuntInsights.number(skills?["shielding"]) ?? HuntInsights.number(skills?["melee"]) ?? 10
    }

    /// - Parameter multiplier: damage share a combat type does to the monsters of this account's hunt (nil if unknown).
    static func suggestions(for account: Int, members all: [Member], combat: Combat?, multiplier: (String) -> Double?) -> [[String: Any]] {
        let mine = all.filter { $0.account == account }
        guard !mine.isEmpty else { return [] }
        // Who takes the hits: lowest average health; before there are enough frames, the knight.
        let tank = mine.filter { $0.hpAverage != nil }.min { $0.hpAverage! < $1.hpAverage! }
            ?? mine.first { $0.vocation == "KNIGHT" }
        var out: [(score: Double, text: [String: Any])] = []
        if let tank, let combat, combat.takenPerSecond > 0 {
            let peers = all.filter { $0.vocation == tank.vocation && $0.account != account }
            let now = stopped(tank.items, shielding: tank.shielding, combat: combat)
            for slot in defensiveSlots {
                let current = tank.items[slot]
                let best = peers.compactMap { peer -> (Member, Item, Double)? in
                    guard let item = peer.items[slot], item.name != current?.name else { return nil }
                    var swapped = tank.items
                    swapped[slot] = item
                    return (peer, item, stopped(swapped, shielding: tank.shielding, combat: combat) - now)
                }.max { $0.2 < $1.2 }
                guard let best, best.2 / combat.takenPerSecond >= minShare else { continue }
                let share = best.2 / combat.takenPerSecond
                // Weighed by how much this member is hit (1 - average health), so the tank's swaps come first.
                let weight = max(0.1, 1 - (tank.hpAverage ?? 0.8)) * 5
                out.append((share * 100 * weight, [
                    "kind": "defense", "vocation": tank.vocation, "slot": slotNames[slot] ?? slot,
                    "perSecond": Int(best.2.rounded()), "share": share,
                    "from": current?.summary ?? "vazio", "to": best.1.summary, "source": best.0.label,
                    "text": "\(BattlePreset.vocationLabel(tank.vocation)) · \(slotNames[slot] ?? slot): " +
                        "\(current?.summary ?? "vazio") → \(best.1.summary) (usado em \(best.0.label)): " +
                        "~\(Int(best.2.rounded())) de dano a menos por segundo (\(percent(share)) do recebido)",
                ]))
            }
        }
        for member in mine where member.vocation == "SORCERER" || member.vocation == "DRUID" {
            guard let weapon = member.items["weapon"], let element = weapon.element, let share = multiplier(element), share < weakElement else { continue }
            let better = all.filter { $0.vocation == member.vocation && $0.account != account }
                .compactMap { peer -> (Member, Item, Double)? in
                    guard let item = peer.items["weapon"], let e = item.element, let m = multiplier(e), m > share + 0.1 else { return nil }
                    return (peer, item, m)
                }.max { $0.2 < $1.2 }
            let from = "\(weapon.name) (\(Attention.elements[element] ?? element), \(percent(share)) do dano)"
            var row: [String: Any] = ["kind": "element", "vocation": member.vocation, "slot": "arma", "from": from]
            var text = "\(BattlePreset.vocationLabel(member.vocation)) · arma: \(from)"
            if let better {
                let to = "\(better.1.name) (\(Attention.elements[better.1.element ?? ""] ?? ""), \(percent(better.2)))"
                row["to"] = to
                row["source"] = better.0.label
                text += " → \(to) (usado em \(better.0.label))"
            } else if let (type, m) = bestElement(for: member.vocation, multiplier: multiplier), m > share + 0.1 {
                let kind = member.vocation == "DRUID" ? "rod" : "wand"
                let to = "uma \(kind) de \(Attention.elements[type] ?? type) (\(percent(m)))"
                row["to"] = to
                text += " → \(to)"
            } else { text += " → uma wand/rod de outro elemento" }
            row["text"] = text
            out.append(((1 - share) * 40, row))
        }
        return out.sorted { $0.score > $1.score }.prefix(4).map(\.text)
    }

    /// The element among the vocation's wands (sorcerer) or rods (druid) the hunt's monsters resist least.
    static func bestElement(for vocation: String, multiplier: (String) -> Double?) -> (String, Double)? {
        let kind = vocation == "DRUID" ? " rod" : "wand "
        let types = Set(wandElements.filter { $0.key.contains(kind) }.values)
        return types.compactMap { type in multiplier(type).map { (type, $0) } }.max { $0.1 < $1.1 }
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
