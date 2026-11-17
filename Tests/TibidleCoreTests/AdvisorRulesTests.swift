import XCTest
@testable import TibidleCore

/// The game rules and the statistics behind the advice: cooldown groups, damage weighed by health, mana that is
/// not there, a typical hunt as the bar, members changing places.
final class AdvisorRulesTests: XCTestCase {
    static let spellsJSON = #"""
    [
     {"name":"Strong Energy Strike","available":true,"group":"attack","groupCooldownMs":2000,"secondaryGroup":"special","secondaryGroupCooldownMs":8000,
      "level":55,"mana":60,"vocations":["sorcerer","master sorcerer"],"cooldownMs":8000,"combatType":"COMBAT_ENERGYDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 2.8) + 16)","max":"((level / 5) + (maglevel * 4.4) + 28)"}},
     {"name":"Strong Flame Strike","available":true,"group":"attack","groupCooldownMs":2000,"secondaryGroup":"special","secondaryGroupCooldownMs":8000,
      "level":70,"mana":60,"vocations":["sorcerer","master sorcerer"],"cooldownMs":8000,"combatType":"COMBAT_FIREDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 2.8) + 16)","max":"((level / 5) + (maglevel * 4.4) + 28)"}},
     {"name":"Energy Strike","available":true,"group":"attack","groupCooldownMs":2000,"level":12,"mana":20,
      "vocations":["druid","elder druid","sorcerer","master sorcerer"],"cooldownMs":2000,"combatType":"COMBAT_ENERGYDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 1.403) + 8)","max":"((level / 5) + (maglevel * 2.203) + 13)"}},
     {"name":"Hell's Core","available":true,"group":"attack","groupCooldownMs":4000,"secondaryGroup":"focus","secondaryGroupCooldownMs":40000,
      "level":60,"mana":1100,"vocations":["sorcerer","master sorcerer"],"cooldownMs":40000,"area":"AREA_CIRCLE5X5","areaCells":60,
      "combatType":"COMBAT_FIREDAMAGE","formulaType":"levelmagic","formula":{"min":"((level / 5) + (maglevel * 10))","max":"((level / 5) + (maglevel * 14))"}}
    ]
    """#
    var spells: SpellCatalog { SpellCatalog(json: Data(Self.spellsJSON.utf8))! }

    func sorcerer(_ kit: [String]) -> SkillAdvisor.Member {
        SkillAdvisor.Member(name: "S", vocation: "Master Sorcerer", level: 100, melee: 10, distance: 10, magic: 80, attack: nil, kit: kit, minCreatures: [:])
    }

    func testStrongStrikesShareTheirSecondaryCooldown() {
        let context = SkillAdvisor.Context(spells: spells, creatures: CreatureCatalog(), kills: ["Rat": 10], crowd: 1)
        let pair = SkillAdvisor.simulate(kit: ["Strong Energy Strike", "Energy Strike"], member: sorcerer([]), context: context)
        let three = SkillAdvisor.simulate(kit: ["Strong Energy Strike", "Strong Flame Strike", "Energy Strike"], member: sorcerer([]), context: context)
        // "special" stays locked 8 s after either strong strike: the second one never finds a gap, the damage is the same.
        XCTAssertNil(three.share["Strong Flame Strike"])
        XCTAssertEqual(three.damagePerSecond, pair.damagePerSecond, accuracy: 1e-9)
        // 120 s: the strong strike every 8 s (15 casts), the plain one in the 45 other 2-second slots.
        let strong = SkillAdvisor.baseDamage(spells.spell(named: "Strong Energy Strike")!, member: sorcerer([]))!
        let plain = SkillAdvisor.baseDamage(spells.spell(named: "Energy Strike")!, member: sorcerer([]))!
        XCTAssertEqual(pair.share["Strong Energy Strike"]!, strong * 15 / 120, accuracy: 1e-9)
        XCTAssertEqual(pair.share["Energy Strike"]!, plain * 45 / 120, accuracy: 1e-9)
        // So adding the second strong strike is never suggested as a gain.
        let analysis = SkillAdvisor.analyze(members: [sorcerer(["Strong Energy Strike", "Energy Strike"])], spells: spells,
                                            creatures: CreatureCatalog(), kills: ["Rat": 50], calibration: .none)
        let suggestions = (analysis["members"] as! [[String: Any]])[0]["suggestions"] as! [[String: Any]]
        XCTAssertFalse(suggestions.contains { $0["add"] as? String == "Strong Flame Strike" && $0["replace"] is NSNull })
    }

    func testALongGroupCooldownHoldsTheNextAttack() {
        // Hell's Core locks every attack for 4 s, not for the kit's shortest 2 s.
        let context = SkillAdvisor.Context(spells: spells, creatures: CreatureCatalog(), kills: ["Rat": 10], crowd: 1)
        let rotation = SkillAdvisor.simulate(kit: ["Hell's Core", "Energy Strike"], member: sorcerer([]), context: context)
        let core = SkillAdvisor.baseDamage(spells.spell(named: "Hell's Core")!, member: sorcerer([]))!
        let plain = SkillAdvisor.baseDamage(spells.spell(named: "Energy Strike")!, member: sorcerer([]))!
        // Hell's Core at 0, 40 and 80 s; Energy Strike from 4 s to 38 s every 2 s (18 casts) in each 40 s.
        XCTAssertEqual(rotation.share["Hell's Core"]!, core * 3 / 120, accuracy: 1e-9)
        XCTAssertEqual(rotation.share["Energy Strike"]!, plain * 54 / 120, accuracy: 1e-9)
    }

    func testDamageShareWeighsByTheMonstersHealth() {
        // Four kills of a 100 hp monster immune to energy and one of a 1000 hp one it hurts fully: most of the damage
        // went into the big one.
        var creatures = CreatureCatalog()
        creatures.add(name: "Small", elements: [["type": "COMBAT_ENERGYDAMAGE", "percent": 100]])
        creatures.add(name: "Big", elements: [["type": "COMBAT_ENERGYDAMAGE", "percent": 0]])
        let kills = ["Small": 4.0, "Big": 1]
        let byKill = SkillAdvisor.Context(spells: spells, creatures: creatures, kills: kills, crowd: 1).weighted("COMBAT_ENERGYDAMAGE")
        XCTAssertEqual(byKill.multiplier, 0.2, accuracy: 1e-9, "without health every kill weighs the same")
        creatures.health = ["small": 100, "big": 1000]
        let byHealth = SkillAdvisor.Context(spells: spells, creatures: creatures, kills: kills, crowd: 1).weighted("COMBAT_ENERGYDAMAGE")
        XCTAssertEqual(byHealth.multiplier, 1000.0 / 1400, accuracy: 1e-9)
        XCTAssertEqual(byHealth.coverage, 1)
        // A monster of unknown resistance counts in the coverage by its health too, and as neutral in the simulation.
        let partial = SkillAdvisor.Context(spells: spells, creatures: creatures, kills: ["Small": 4, "Unknown": 1], crowd: 1)
        // Unknown health: the average of the hunt's monsters whose health is known (here 100).
        XCTAssertEqual(partial.weighted("COMBAT_ENERGYDAMAGE").coverage, 400.0 / 500, accuracy: 1e-9)
        XCTAssertEqual(partial.expected("COMBAT_ENERGYDAMAGE"), 100.0 / 500, accuracy: 1e-9)
    }

    func testTheMapsMonsterListCarriesHealth() {
        let json = #"[{"id":1,"title":"Lair","bestiary":{"bonus":"x","stages":[{"kills":10,"value":1}]},"monsters":[{"name":"Lich","health":880,"elements":[]}]}]"#
        XCTAssertEqual(HuntBestiaryCatalog(json: Data(json.utf8))!.creatures.health(of: "LICH"), 880)
    }

    func testAResistedElementNeedsMostOfTheHuntBehindIt() {
        func entry(coverage: Double) -> [String: Any] {
            ["skills": ["members": [["name": "S", "vocation": "SORCERER", "skills": [
                ["name": "Flame Strike", "element": "COMBAT_FIREDAMAGE", "multiplier": 0.1, "dps": 20, "coverage": coverage]]]]]]
        }
        XCTAssertTrue(Attention.skillItems(entry(coverage: 0.05), account: 0, label: "A").isEmpty)
        XCTAssertEqual(Attention.skillItems(entry(coverage: SkillAdvisor.minAlertCoverage), account: 0, label: "A").map(\.kind), ["element"])
    }

    func testAMemberOutOfManaGetsTheGainOfTheSameMana() {
        var tracker = VitalsTracker()
        for _ in 0..<VitalsTracker.minSamples { tracker.add(party: [["name": "S", "vocation": "SORCERER", "mana": 100, "maxMana": 1000]]) }
        let suggestions: [[String: Any]] = [
            // +30% for 50% more mana: with the same mana it is (1.3 / 1.5) − 1, a loss.
            ["add": "Hungry", "gain": 0.30, "manaPerMinuteDelta": 500, "manaPerMinute": 1500, "currentManaPerMinute": 1000],
            // +50% for 10% more: (1.5 / 1.1) − 1 = 36%.
            ["add": "Efficient", "gain": 0.50, "manaPerMinuteDelta": 100, "manaPerMinute": 1100, "currentManaPerMinute": 1000],
            ["add": "Cheap", "gain": 0.40, "manaPerMinuteDelta": -50, "manaPerMinute": 950, "currentManaPerMinute": 1000],
        ]
        let analysis: [String: Any] = ["members": [["name": "S", "vocation": "SORCERER", "suggestions": suggestions]]]
        let kept = (ManaBudget.apply(analysis, averages: tracker.averages())["members"] as! [[String: Any]])[0]["suggestions"] as! [[String: Any]]
        XCTAssertEqual(kept.map { $0["add"] as? String }, ["Cheap", "Efficient"])
        XCTAssertEqual(kept[1]["gain"] as! Double, 1.5 / 1.1 - 1, accuracy: 1e-9)
        XCTAssertEqual(kept[1]["rawGain"] as? Double, 0.5)
        XCTAssertEqual(kept[1]["manaLimited"] as? Bool, true)
    }

    func run(_ id: Int, minimum: Int, profitPerHour: Double, hours: Double = 1, endedAt: Double) -> HuntInsights.Run {
        HuntInsights.Run(id: id, summary: ["huntId": 7, "elapsedSec": hours * 3600, "balance": profitPerHour * hours, "endedAt": endedAt,
                                           "level": ["start": 100, "end": 100],
                                           "setup": ["SORCERER": ["skills": ["Energy Wave"], "minCreatures": ["Energy Wave": minimum]]]])
    }

    func testOneLuckyHuntDoesNotSetTheBar() {
        let now = 1_800_000_000_000.0
        // Setup 2: 60k, 70k, 65k; setup 3 once at 120k (luck).
        let runs = [run(1, minimum: 2, profitPerHour: 60_000, endedAt: now - 4e6), run(2, minimum: 2, profitPerHour: 70_000, endedAt: now - 3e6),
                    run(3, minimum: 3, profitPerHour: 120_000, endedAt: now - 2e6), run(4, minimum: 2, profitPerHour: 65_000, endedAt: now - 1e6)]
        let reference = HuntInsights.reference(runs: runs, huntId: 7, level: 100, now: now)!
        XCTAssertEqual(reference.id, 4)
        XCTAssertEqual(reference.baseline, 65_000)
        XCTAssertEqual(reference.runs, 3)
        // Every setup different: the typical hunt is shown, and no setup is blamed.
        let distinct = [run(1, minimum: 2, profitPerHour: 60_000, endedAt: now - 3e6), run(2, minimum: 3, profitPerHour: 90_000, endedAt: now - 2e6),
                        run(3, minimum: 4, profitPerHour: 70_000, endedAt: now - 1e6)]
        let typical = HuntInsights.reference(runs: distinct, huntId: 7, level: 100, now: now)!
        XCTAssertEqual(typical.baseline, 70_000)
        XCTAssertEqual(typical.runs, 1)
        let current: [String: [String: Any]] = ["SORCERER": ["skills": ["Energy Wave"], "minCreatures": ["Energy Wave": 9]]]
        let insights = HuntInsights.evaluate(reference: typical, analyzer: ["elapsedMs": 3_600_000, "lootGold": 30_000, "suppliesGold": 0], setup: current)
        XCTAssertEqual(insights["drop"] as! Double, 40.0 / 70, accuracy: 1e-9)
        let entry: [String: Any] = ["index": 0, "label": "A", "status": "hunting", "insights": insights]
        XCTAssertFalse(Attention.evaluate(accounts: [entry], now: now).contains { $0.kind == "setup" })
    }

    func testSkillPaceFollowsTheMemberNotTheSlot() {
        // Two members trade places every frame; by slot each frame would read as a loss and start over.
        var training = SkillTraining()
        let start = Date(timeIntervalSince1970: 1000)
        for i in 0...300 {
            let progress = 6000 + i / 20
            let knight: [String: Any] = ["name": "Z", "vocation": "KNIGHT", "skillLevels": ["melee": progress / 100], "skillProgress": ["melee": progress % 100]]
            let paladin: [String: Any] = ["name": "Z", "vocation": "PALADIN", "skillLevels": ["distance": 90], "skillProgress": ["distance": 10]]
            training.add(party: i % 2 == 0 ? [knight, paladin] : [paladin, knight], at: start.addingTimeInterval(Double(i) * 6))
        }
        let rows = training.summary()!
        XCTAssertEqual(rows.count, 1, "only the knight's melee moved")
        XCTAssertEqual(rows[0]["vocation"] as? String, "KNIGHT")
        XCTAssertEqual((rows[0]["skills"] as! [[String: Any]])[0]["perHour"] as! Double, 30, accuracy: 0.1)
    }

    func testADipOfAMemberWhoLeftIsNotStillGoingOn() {
        var dangers = DangerTracker()
        let start = Date(timeIntervalSince1970: 1000)
        dangers.add(party: [["name": "A", "vocation": "DRUID", "hp": 200, "maxHp": 800]], at: start) { nil }
        // Someone else at full health takes the slot: that is not A recovering.
        dangers.add(party: [["name": "B", "vocation": "DRUID", "hp": 800, "maxHp": 800]], at: start.addingTimeInterval(3)) { nil }
        let moment = (dangers.summary()!["moments"] as! [[String: Any]])[0]
        XCTAssertEqual(moment["left"] as? Bool, true)
        XCTAssertNil(moment["ongoing"])
        XCTAssertNil(moment["seconds"])
    }
}
