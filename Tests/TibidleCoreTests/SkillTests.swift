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

    static let selectJSON = #"""
    [{"id":10,"title":"Dragon Lair","levelMin":1,"bestiary":{"bonus":"hpRegen","stages":[{"kills":1000,"value":1},{"kills":2000,"value":2},{"kills":4000,"value":3}]},
      "monsters":[{"name":"Dragon","elements":[{"type":"COMBAT_FIREDAMAGE","percent":100}]}]},
     {"id":11,"title":"Sem bestiário","bestiary":{"bonus":"x","stages":[{"kills":0,"value":0}]},"monsters":[]}]
    """#

    func testHuntBestiaryCatalogParsesStagesAndFeedsCreatures() {
        let catalog = HuntBestiaryCatalog(json: Data(Self.selectJSON.utf8))!
        XCTAssertEqual(catalog.entries.keys.sorted(), [10], "maps whose milestones are all zero are skipped")
        XCTAssertEqual(catalog.entries[10]?.stages.map(\.kills), [1000, 2000, 4000])
        XCTAssertEqual(catalog.creatures.multiplier(creature: "Dragon", type: "COMBAT_FIREDAMAGE"), 0)
        XCTAssertNil(HuntBestiaryCatalog(json: Data("[]".utf8)))
    }

    func testBestiaryEtaUsesTheCurrentKillRate() {
        let entry = HuntBestiaryCatalog(json: Data(Self.selectJSON.utf8))!.entries[10]!
        // 800 recorded + 300 this hunt in 30 min = 600 kills/h; next milestone at 2000 -> 900 kills left -> 1.5 h.
        let result = BestiaryAdvisor.evaluate(entry, counted: 800, session: 300, elapsedMs: 30 * 60_000)
        XCTAssertEqual(result["kills"] as? Double, 1100)
        XCTAssertEqual(result["reached"] as? Int, 1)
        XCTAssertEqual(result["done"] as? Bool, false)
        XCTAssertEqual((result["next"] as! [String: Any])["kills"] as? Double, 2000)
        XCTAssertEqual((result["next"] as! [String: Any])["etaMs"] as! Double, 1.5 * 3_600_000, accuracy: 1)
        XCTAssertEqual(result["etaMs"] as! Double, 4.8333 * 3_600_000, accuracy: 5_000, "(4000-1100)/600 h")
        // Too little data: no estimate, but the progress still shows.
        let early = BestiaryAdvisor.evaluate(entry, counted: 800, session: 20, elapsedMs: 2 * 60_000)
        XCTAssertNil(early["etaMs"])
        XCTAssertEqual(early["kills"] as? Double, 820)
        let finished = BestiaryAdvisor.evaluate(entry, counted: 4100, session: 0, elapsedMs: 0)
        XCTAssertEqual(finished["done"] as? Bool, true)
    }

    func testStoreShowsBestiaryAndFoldsFinishedHunts() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DashboardStore(databaseURL: nil, now: { clock })
        store.setBestiaries(HuntBestiaryCatalog(json: Data(Self.selectJSON.utf8))!)
        store.ingest(account: 0, json: #"{"type":"welcome","data":{"huntBestiary":{"10":900,"11":5}}}"#)
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{}}}"#)
        for minute in 1...10 {
            clock += 60
            store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":\#(minute * 60_000),"killsTotal":\#(minute * 20),"kills":{"Dragon":\#(minute * 20)}}}}"#)
        }
        func bestiary() -> [String: Any]? {
            ((try! JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any])["accounts"] as! [[String: Any]])[0]["bestiary"] as? [String: Any]
        }
        XCTAssertEqual(bestiary()?["kills"] as? Double, 1100)
        XCTAssertNotNil(bestiary()?["etaMs"])
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":10,"reason":"manual","elapsedSec":600,"killsTotal":200,"xp":"1","lootGold":0,"suppliesGold":0,"balance":0}}}"#)
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{}}}"#)
        XCTAssertEqual(bestiary()?["kills"] as? Double, 1100, "finished hunt is folded into the counter, not lost or doubled")
    }

    func testBestiaryDoesNotDoubleCountWhenTheAppOpensMidHunt() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = DashboardStore(databaseURL: nil, now: { clock })
        store.setBestiaries(HuntBestiaryCatalog(json: Data(Self.selectJSON.utf8))!)
        func kills() -> Double? {
            let accounts = (try! JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any])["accounts"] as! [[String: Any]]
            return (accounts[0]["bestiary"] as? [String: Any])?["kills"] as? Double
        }
        // The app opens mid-hunt: the server counter (2400) already includes the 2376 kills so far.
        store.ingest(account: 0, json: #"{"type":"resume","data":{"huntId":10,"huntBestiary":{"10":2400},"analyzer":{"elapsedMs":7400000,"killsTotal":2376,"kills":{}},"state":{}}}"#)
        XCTAssertEqual(kills(), 2400, "no double counting of the hunt in progress")
        clock += 60
        store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":7460000,"killsTotal":2400,"kills":{}}}}"#)
        XCTAssertEqual(kills(), 2424, "kills made after the counter was read are added")
        // Finishing the hunt folds only the new kills, and the next hunt starts from the folded counter.
        store.ingest(account: 0, json: #"{"type":"ended","data":{"summary":{"huntId":10,"reason":"manual","elapsedSec":7500,"killsTotal":2430,"xp":"1","lootGold":0,"suppliesGold":0,"balance":0}}}"#)
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":10,"state":{}}}"#)
        store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":{"elapsedMs":60000,"killsTotal":0,"kills":{}}}}"#)
        XCTAssertEqual(kills(), 2454, "2400 read + (2430 - 2376) made since")
    }
}

final class ManaBudgetTests: XCTestCase {
    func testFlagsManaHungrySuggestionsForMembersThatRunDry() {
        var tracker = VitalsTracker()
        for _ in 0..<(VitalsTracker.minSamples - 1) {
            tracker.add(party: [["name": "Zolp", "vocation": "Elite Knight", "mana": 40, "maxMana": 400],
                                ["name": "Zolp", "vocation": "DRUID", "mana": 1600, "maxMana": 2000]])
        }
        XCTAssertTrue(tracker.averages().isEmpty, "too few frames to judge")
        tracker.add(party: [["name": "Zolp", "vocation": "Elite Knight", "mana": 40, "maxMana": 400],
                            ["name": "Zolp", "vocation": "DRUID", "mana": 1600, "maxMana": 2000]])
        let averages = tracker.averages()
        XCTAssertEqual(averages["Zolp|knight"] ?? 0, 0.1, accuracy: 1e-9)

        let suggestions: [[String: Any]] = [["add": "Groundshaker", "manaPerMinuteDelta": 1200], ["add": "Cheap", "manaPerMinuteDelta": -50]]
        let analysis: [String: Any] = ["members": [
            ["name": "Zolp", "vocation": "KNIGHT", "suggestions": suggestions],
            ["name": "Zolp", "vocation": "DRUID", "suggestions": suggestions],
        ]]
        let members = ManaBudget.apply(analysis, averages: averages)["members"] as! [[String: Any]]
        let knight = members[0]["suggestions"] as! [[String: Any]]
        XCTAssertEqual(knight[0]["manaLimited"] as? Bool, true)
        XCTAssertNil(knight[1]["manaLimited"], "a cheaper swap is fine")
        XCTAssertEqual(members[1]["manaAverage"] as? Double ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertNil((members[1]["suggestions"] as! [[String: Any]])[0]["manaLimited"], "a member with mana to spare is not flagged")
    }
}

final class VitalsTests: XCTestCase {
    func testTracksAverageAndLowestHealthPerMember() {
        var tracker = VitalsTracker()
        for hp in [100, 50, 90, 80] {
            for _ in 0..<5 {
                tracker.add(party: [["name": "Zolp", "vocation": "KNIGHT", "hp": hp, "maxHp": 100], ["name": "Zolp", "vocation": "DRUID", "hp": 60, "maxHp": 60]])
            }
        }
        let party = tracker.annotate(party: [["name": "Zolp", "vocation": "Elite Knight"], ["name": "Zolp", "vocation": "DRUID"], ["name": "Novo", "vocation": "DRUID"]])
        XCTAssertEqual(party[0]["hpAverage"] as? Double ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(party[0]["hpLowest"] as? Double, 0.5)
        XCTAssertEqual(party[1]["hpAverage"] as? Double, 1)
        XCTAssertNil(party[2]["hpAverage"], "a member with no frames stays as it was")
    }
}

final class SkillAttentionTests: XCTestCase {
    func testWarnsAboutResistedSpellsThatFireAndMembersOutOfMana() {
        let entry: [String: Any] = ["skills": ["members": [
            ["name": "Crovax", "vocation": "SORCERER", "manaAverage": 0.06, "manaPerMinute": 3075, "skills": [
                ["name": "Great Fire Wave", "element": "COMBAT_FIREDAMAGE", "multiplier": 0.15, "dps": 16.5],
                ["name": "sudden death rune", "element": "COMBAT_DEATHDAMAGE", "multiplier": 0.2, "dps": 0],   // never fires: no warning
                ["name": "Energy Wave", "element": "COMBAT_ENERGYDAMAGE", "multiplier": 1.1, "dps": 92]]],
            ["name": "Crovax", "vocation": "KNIGHT", "manaAverage": 0.16, "manaPerMinute": 4610, "skills": []],
            ["name": "Crovax", "vocation": "DRUID", "manaAverage": 0.02, "manaPerMinute": 0, "skills": []],   // spends no mana on attacks
        ]]]
        let items = Attention.skillItems(entry, account: 1, label: "Crovax")
        XCTAssertEqual(items.map(\.kind), ["element", "mana"])
        XCTAssertTrue(items[0].text.hasPrefix("Crovax · Sorcerer: Great Fire Wave (fogo) causa só 15% do dano"))
        XCTAssertTrue(items[1].text.contains("Sorcerer passa a hunt com 6% de mana em média"))
    }
}
