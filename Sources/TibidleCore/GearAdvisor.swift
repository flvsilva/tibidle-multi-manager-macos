import Foundation

/// Equipment upgrades with the most impact, from the gear the collector reads:
/// - defense of whoever takes the hits (the member with the lowest average health), slot by slot, against the
///   best item your other accounts use on the same vocation;
/// - the element of a wand or rod against the monsters of the hunt in progress.
/// Damage per kill is the monster's health, so defense shows up as damage taken (and supplies) per kill.
public enum GearAdvisor {
    static let defensiveSlots = ["shield", "head", "armor", "legs", "boots", "necklace", "ring"]
    static let slotNames = ["weapon": "arma", "shield": "escudo", "head": "capacete", "armor": "armadura", "legs": "calça",
                            "boots": "bota", "necklace": "colar", "ring": "anel"]
    /// Below this the swap is noise.
    static let minGain = 3.0
    /// A wand or rod doing less than this share of its damage is the wrong element for the hunt.
    static let weakElement = 0.8

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
        var requiredLevel: Int? { HuntInsights.number(stats["attrs.level"]).map { Int($0) } }

        /// Armor and shield defense count once each; shielding boosts and physical absorption weigh more,
        /// elemental protections a little (the hunt's damage mix is unknown).
        var defense: Double {
            let elemental = stats.reduce(0.0) { sum, pair in
                let key = pair.key
                guard key.hasPrefix("attrs.elemental protection") || (key.hasPrefix("attrs.absorbpercent") && key != "attrs.absorbpercentphysical")
                else { return sum }
                return sum + (HuntInsights.number(pair.value) ?? 0)
            }
            return number("armor") + number("defense") + 2 * number("skillboost shielding") + 3 * number("absorbpercentphysical") + 0.3 * elemental
        }

        var summary: String {
            var parts: [String] = []
            for (key, label) in [("armor", "armor"), ("defense", "def")] where number(key) != 0 { parts.append("\(label) \(Int(number(key)))") }
            if number("skillboost shielding") != 0 { parts.append("+\(Int(number("skillboost shielding"))) shielding") }
            if number("absorbpercentphysical") != 0 { parts.append("\(Int(number("absorbpercentphysical")))% físico") }
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
        let items: [String: Item]
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
                              hpAverage: member["hpAverage"] as? Double, items: items)
            }
        }
    }

    /// - Parameter multiplier: damage share a combat type does to the monsters of this account's hunt (nil if unknown).
    static func suggestions(for account: Int, members all: [Member], multiplier: (String) -> Double?) -> [[String: Any]] {
        let mine = all.filter { $0.account == account }
        guard !mine.isEmpty else { return [] }
        // Who takes the hits: lowest average health; before there are enough frames, the knight.
        let tank = mine.filter { $0.hpAverage != nil }.min { $0.hpAverage! < $1.hpAverage! }
            ?? mine.first { $0.vocation == "KNIGHT" }
        var out: [(score: Double, text: [String: Any])] = []
        if let tank {
            let peers = all.filter { $0.vocation == tank.vocation && $0.account != account }
            for slot in defensiveSlots {
                let current = tank.items[slot]
                let candidates = peers.compactMap { peer in peer.items[slot].map { (peer, $0) } }
                    .filter { $0.1.requiredLevel.map { $0 <= tank.level } ?? true }
                guard let best = candidates.max(by: { $0.1.defense < $1.1.defense }) else { continue }
                let gain = best.1.defense - (current?.defense ?? 0)
                guard gain >= minGain, best.1.name != current?.name else { continue }
                // Weighed by how much this member is hit (1 - average health), so the tank's swaps come first.
                let weight = max(0.1, 1 - (tank.hpAverage ?? 0.8)) * 5
                out.append((gain * weight, [
                    "kind": "defense", "vocation": tank.vocation, "slot": slotNames[slot] ?? slot, "gain": Int(gain.rounded()),
                    "from": current?.summary ?? "vazio", "to": best.1.summary, "source": best.0.label,
                    "text": "\(BattlePreset.vocationLabel(tank.vocation)) · \(slotNames[slot] ?? slot): " +
                        "\(current?.summary ?? "vazio") → \(best.1.summary) (usado em \(best.0.label))",
                ]))
            }
        }
        for member in mine where member.vocation == "SORCERER" || member.vocation == "DRUID" {
            guard let weapon = member.items["weapon"], let element = weapon.element, let share = multiplier(element), share < weakElement else { continue }
            let better = all.filter { $0.vocation == member.vocation && $0.account != account }
                .compactMap { peer -> (Member, Item, Double)? in
                    guard let item = peer.items["weapon"], let e = item.element, let m = multiplier(e), m > share + 0.1,
                          item.requiredLevel.map({ $0 <= member.level }) ?? true else { return nil }
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
            } else { text += " → uma wand/rod de outro elemento" }
            row["text"] = text
            out.append(((1 - share) * 40, row))
        }
        return out.sorted { $0.score > $1.score }.prefix(4).map(\.text)
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
