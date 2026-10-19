import XCTest
@testable import TibidleCore

final class SkillTests: XCTestCase {
    static let spellsJSON = #"""
    [
     {"name":"Ice Strike","available":true,"group":"attack","level":15,"mana":20,"vocations":["druid","elder druid","sorcerer","master sorcerer"],
      "cooldownMs":2000,"groupCooldownMs":2000,"combatType":"COMBAT_ICEDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 1.403) + 8)","max":"((level / 5) + (maglevel * 2.203) + 13)"}},
     {"name":"Flame Strike","available":true,"group":"attack","level":14,"mana":20,"vocations":["druid","elder druid","sorcerer","master sorcerer"],
      "cooldownMs":2000,"groupCooldownMs":2000,"combatType":"COMBAT_FIREDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 1.403) + 8)","max":"((level / 5) + (maglevel * 2.203) + 13)"}},
     {"name":"Hell's Core","available":true,"group":"attack","level":60,"mana":1100,"vocations":["sorcerer","master sorcerer"],
      "cooldownMs":40000,"groupCooldownMs":4000,"area":"AREA_CIRCLE5X5","areaCells":60,"combatType":"COMBAT_FIREDAMAGE","formulaType":"levelmagic",
      "formula":{"min":"((level / 5) + (maglevel * 10))","max":"((level / 5) + (maglevel * 14))"}},
     {"name":"Exura","available":true,"group":"healing","level":8,"mana":20,"vocations":["druid"],"cooldownMs":1000,"groupCooldownMs":1000,
      "combatType":"COMBAT_HEALING","formulaType":"levelmagic","formula":{"min":"1","max":"2"}}
    ]
    """#

    var spells: SpellCatalog { SpellCatalog(json: Data(Self.spellsJSON.utf8))! }

    /// A fire-immune, ice-weak crowd (like the Dragon in the game's bestiary: fire 100, ice -10).
    var creatures: CreatureCatalog {
        var catalog = CreatureCatalog()
        catalog.add(name: "Dragon", elements: [["type": "COMBAT_FIREDAMAGE", "percent": 100], ["type": "COMBAT_ICEDAMAGE", "percent": -10]])
        return catalog
    }

    func member(kit: [String]) -> SkillAdvisor.Member {
        SkillAdvisor.Member(name: "Druida", vocation: "Elder Druid", level: 100, melee: 10, distance: 10, magic: 80,
                            attack: nil, kit: kit, minCreatures: [:])
    }

    func testFormulaEvaluator() {
        XCTAssertEqual(FormulaEvaluator.evaluate("((level / 5) + (maglevel * 2) + 13)", variables: ["level": 100, "maglevel": 10]), 53)
        XCTAssertEqual(FormulaEvaluator.evaluate(" -(2 + 3) * 2 ", variables: [:]), -10)
        XCTAssertNil(FormulaEvaluator.evaluate("level +", variables: ["level": 1]))
        XCTAssertNil(FormulaEvaluator.evaluate("unknown * 2", variables: [:]))
        XCTAssertNil(FormulaEvaluator.evaluate("1 / 0", variables: [:]))
        XCTAssertNil(FormulaEvaluator.evaluate("1 2", variables: [:]))
    }

    func testCatalogKeepsOnlyDamageSpellsAndMatchesVocations() {
        XCTAssertEqual(Set(spells.spells.map(\.name)), ["Ice Strike", "Flame Strike", "Hell's Core"])
        let hell = spells.spell(named: "hell's core")!
        XCTAssertFalse(spells.castable(hell, vocation: "Elder Druid", level: 100))
        XCTAssertTrue(spells.castable(hell, vocation: "Master Sorcerer", level: 100))
        XCTAssertFalse(spells.castable(hell, vocation: "Master Sorcerer", level: 40), "level gate")
    }

    func testResistanceIsInvertedIntoDamageMultiplier() {
        XCTAssertEqual(creatures.multiplier(creature: "dragon", type: "COMBAT_FIREDAMAGE"), 0)
        XCTAssertEqual(creatures.multiplier(creature: "Dragon", type: "COMBAT_ICEDAMAGE")!, 1.1, accuracy: 1e-9)
        XCTAssertEqual(creatures.multiplier(creature: "Dragon", type: "COMBAT_PHYSICALDAMAGE"), 1)
        XCTAssertNil(creatures.multiplier(creature: "Rat", type: "COMBAT_FIREDAMAGE"))
    }

    func testAdvisorFlagsImmuneElementAndSuggestsTheBetterOne() {
        let analysis = SkillAdvisor.analyze(members: [member(kit: ["Flame Strike"])], spells: spells, creatures: creatures,
                                            kills: ["Dragon": 100], calibration: .none)
        let druid = (analysis["members"] as! [[String: Any]])[0]
        let skill = (druid["skills"] as! [[String: Any]])[0]
        XCTAssertEqual(skill["multiplier"] as? Double, 0)
        XCTAssertNotNil(skill["warning"])
        XCTAssertEqual(druid["dps"] as? Double, 0)
        let suggestion = (druid["suggestions"] as! [[String: Any]]).first
        XCTAssertEqual(suggestion?["add"] as? String, "Ice Strike")
        XCTAssertEqual(suggestion?["replace"] as? String, "Flame Strike")
    }

    func testNoSuggestionWhenKitAlreadyFitsAndCastingRulesHold() {
        let good = SkillAdvisor.analyze(members: [member(kit: ["Ice Strike"])], spells: spells, creatures: creatures,
                                        kills: ["Dragon": 100], calibration: .none)
        let druid = (good["members"] as! [[String: Any]])[0]
        XCTAssertGreaterThan(druid["dps"] as! Double, 0)
        XCTAssertTrue((druid["suggestions"] as! [[String: Any]]).isEmpty)
        // A creature threshold above the pull keeps the spell from ever firing.
        var gated = member(kit: ["Ice Strike"])
        gated = SkillAdvisor.Member(name: gated.name, vocation: gated.vocation, level: gated.level, melee: 10, distance: 10, magic: 80,
                                    attack: nil, kit: gated.kit, minCreatures: ["Ice Strike": 5])
        let dps = SkillAdvisor.modeledDPS(members: [gated], spells: spells, creatures: creatures, kills: ["Dragon": 10], crowds: [1, 6])
        XCTAssertEqual(dps[1], 0)
        XCTAssertGreaterThan(dps[6]!, 0)
    }

    func testAreaSpellScalesWithCrowdAndRespectsGroupCooldown() {
        let sorcerer = SkillAdvisor.Member(name: "S", vocation: "Master Sorcerer", level: 100, melee: 10, distance: 10, magic: 80,
                                           attack: nil, kit: ["Hell's Core"], minCreatures: [:])
        let neutral = CreatureCatalog()
        let dps = SkillAdvisor.modeledDPS(members: [sorcerer], spells: spells, creatures: neutral, kills: ["Rat": 50], crowds: [1, 4])
        XCTAssertEqual(dps[4]! / dps[1]!, 4, accuracy: 1e-9)
        // Cooldown 40 s: at most 3 casts in 120 s (t = 0, 40, 80), damage mid = 20 + 80*12 = 980.
        XCTAssertEqual(dps[1]!, 980 * 3 / 120, accuracy: 1e-6)
    }

    func testCalibrationPicksTheCrowdSizeThatFitsRealDamage() {
        // Real damage is consistently 2x the crowd-3 prediction, so crowd 3 must win with factor 2.
        let runs = (1...5).map { i -> (predicted: [Int: Double], actual: Double) in
            let base = Double(100 + i * 10)
            return ([1: base * 0.4, 3: base, 6: base * 2.5], base * 2 * (i.isMultiple(of: 2) ? 1.02 : 0.98))
        }
        let calibration = SkillAdvisor.calibrate(runs)
        XCTAssertEqual(calibration.crowd, 3)
        XCTAssertEqual(calibration.factor, 2, accuracy: 0.05)
        XCTAssertEqual(calibration.samples, 5)
        XCTAssertEqual(SkillAdvisor.calibrate(Array(runs.prefix(2))), .none, "needs at least three hunts")
    }

    func testStoreBuildsAnalysisAndLearnsFromFinishedHunts() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DashboardStore(databaseURL: nil, now: { clock })
        store.setSpellCatalog(spells)
        store.setCreatures(creatures)
        let party = #"[{"name":"Druida","vocation":"Elder Druid","level":100,"skillLevels":{"melee":10,"distance":10,"magic":80},"kit":[{"name":"Ice Strike","mana":20,"cooldownMs":2000}]}]"#
        func frame(kills: Int, damage: Int, elapsed: Int) -> String {
            #"{"type":"frame","data":{"state":{"party":\#(party)},"analyzer":{"elapsedMs":\#(elapsed),"kills":{"Dragon":\#(kills)},"damageDealt":\#(damage),"killsTotal":\#(kills)}}}"#
        }
        func hunt() {
            store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":3,"state":{"party":\#(party)}}}"#)
            for minute in 0...10 {
                store.ingest(account: 0, json: frame(kills: 40 + minute * 10, damage: minute * 40_000, elapsed: 60_000 * minute))
                clock += 60
            }
            store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":3,"reason":"manual","elapsedSec":660,"damageDealt":440000,"killsTotal":140,"xp":"1","lootGold":0,"suppliesGold":0,"balance":0}}}"#)
        }
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":3,"state":{"party":\#(party)}}}"#)
        store.ingest(account: 0, json: frame(kills: 40, damage: 1000, elapsed: 60_000))
        let accounts = (try! JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any])["accounts"] as! [[String: Any]]
        let skills = accounts[0]["skills"] as? [String: Any]
        XCTAssertNotNil(skills, "analysis appears once enough kills are known")
        XCTAssertNil(accounts[0]["battle"], "the raw battle config is not exposed")
        XCTAssertEqual(store.calibrationSamples(), 0)
        for _ in 0..<3 { hunt() }
        XCTAssertEqual(store.calibrationSamples(), 3, "each full hunt adds a modeled-vs-real sample")
        // An app opened mid-hunt (resume) never feeds calibration: the model missed the start.
        store.ingest(account: 0, json: #"{"type":"resume","data":{"huntId":3,"state":{"party":\#(party)}}}"#)
        for minute in 0...10 { store.ingest(account: 0, json: frame(kills: 100, damage: 1, elapsed: 60_000 * minute)); clock += 60 }
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":3,"reason":"manual","elapsedSec":660,"damageDealt":1,"killsTotal":1,"xp":"1","lootGold":0,"suppliesGold":0,"balance":0}}}"#)
        XCTAssertEqual(store.calibrationSamples(), 3)
    }
}
