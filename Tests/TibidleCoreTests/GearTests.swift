import XCTest
@testable import TibidleCore

final class GearTests: XCTestCase {
    func account(_ index: Int, _ label: String, _ party: [[String: Any]]) -> [String: Any] {
        ["index": index, "label": label, "state": ["party": party]]
    }

    func item(_ name: String, _ stats: [String: Any] = [:]) -> [String: Any] { ["name": name, "stats": stats] }

    func testSuggestsTheTanksWeakestSlotsAndTheWrongWandElement() {
        let accounts = [
            account(0, "Peasant", [
                ["vocation": "Elite Knight", "level": 150, "hpAverage": 0.78, "gear": [
                    "shield": item("bone shield", ["attrs.defense": 20]),
                    "head": item("royal helmet", ["attrs.armor": 9, "attrs.skillboost shielding": 3]),
                ]],
                ["vocation": "Master Sorcerer", "level": 150, "hpAverage": 0.99, "gear": ["weapon": item("wand of inferno")]],
                ["vocation": "Elder Druid", "level": 150, "hpAverage": 1.0, "gear": ["weapon": item("springsprout rod")]],
            ]),
            account(1, "Zolp", [
                ["vocation": "Elite Knight", "level": 160, "gear": [
                    "shield": item("mastermind shield", ["attrs.defense": 37, "attrs.skillboost shielding": 3]),
                    "head": item("royal helmet", ["attrs.armor": 9, "attrs.skillboost shielding": 3]),
                    "armor": item("magic plate armor", ["attrs.armor": 17, "attrs.level": 200]),
                ]],
                ["vocation": "Elder Druid", "level": 160, "gear": ["weapon": item("glacial rod")]],
            ]),
        ]
        let shares = ["COMBAT_FIREDAMAGE": 0.15, "COMBAT_EARTHDAMAGE": 0.7, "COMBAT_ICEDAMAGE": 1.05]
        let combat = GearAdvisor.Combat(takenPerSecond: 100)
        let advice = GearAdvisor.suggestions(for: 0, members: GearAdvisor.members(accounts: accounts), combat: combat) { shares[$0] }

        XCTAssertEqual(advice.map { $0["slot"] as? String }, ["arma", "armadura", "arma", "escudo"])
        XCTAssertEqual(advice[0]["text"] as? String, "Sorcerer · arma: wand of inferno (fogo, 15% do dano) → uma wand/rod de outro elemento")
        // No level requirement in the game: the level 200 armor counts. Armor 17 takes 0.75 × 17 off each of 2 hits a second.
        XCTAssertEqual(advice[1]["perSecond"] as? Int, 26)
        XCTAssertEqual(advice[2]["to"] as? String, "glacial rod (gelo, 105%)")
        XCTAssertEqual(advice[2]["source"] as? String, "Zolp")
        // Shield block 0.06 × (Shielding/4 + 2.23) × defense: Shielding 10 + 3 with def 20 → 6.6; 10 + 3 + 3 with def 37 → 13.8.
        // The same royal helmet on both accounts is no swap.
        XCTAssertEqual(advice[3]["text"] as? String, "Knight · escudo: bone shield (def 20) → mastermind shield (def 37, +3 shielding) " +
                       "(usado em Zolp): ~7 de dano a menos por segundo (7% do recebido)")
    }

    func testFallsBackToTheKnightBeforeHealthIsKnown() {
        let accounts = [
            account(0, "A", [["vocation": "Royal Paladin", "level": 100, "gear": ["armor": item("leather armor", ["attrs.armor": 4])]],
                             ["vocation": "Knight", "level": 100, "gear": ["armor": item("chain armor", ["attrs.armor": 6])]]]),
            account(1, "B", [["vocation": "Elite Knight", "level": 100, "gear": ["armor": item("crown armor", ["attrs.armor": 13])]]]),
        ]
        let members = GearAdvisor.members(accounts: accounts)
        let advice = GearAdvisor.suggestions(for: 0, members: members, combat: .init(takenPerSecond: 50)) { _ in nil }
        XCTAssertEqual(advice.count, 1)
        XCTAssertEqual(advice[0]["perSecond"] as? Int, 11)
        XCTAssertEqual(advice[0]["vocation"] as? String, "KNIGHT")
        // Without a damage rate yet there is nothing to weigh the defense by.
        XCTAssertTrue(GearAdvisor.suggestions(for: 0, members: members, combat: nil) { _ in nil }.isEmpty)
    }

    func testMagicSkipsArmorAndOnlyItsElementsProtectionCounts() {
        let armor = GearAdvisor.Item(slot: "armor", name: "plate armor", stats: ["attrs.armor": 10])
        let cape = GearAdvisor.Item(slot: "armor", name: "cape", stats: ["attrs.absorbpercentfire": 10])
        let allMagic = GearAdvisor.Combat(takenPerSecond: 90, hitsPerSecond: 2, physicalShare: 0, elements: ["fire": 1])
        XCTAssertEqual(GearAdvisor.stopped(["armor": cape], shielding: 10, combat: allMagic), 10, accuracy: 0.001)
        let iceOnly = GearAdvisor.Combat(takenPerSecond: 90, hitsPerSecond: 2, physicalShare: 0, elements: ["ice": 1])
        XCTAssertEqual(GearAdvisor.stopped(["armor": cape], shielding: 10, combat: iceOnly), 0)
        XCTAssertEqual(GearAdvisor.stopped(["armor": armor], shielding: 10, combat: allMagic), 0)
        let melee = GearAdvisor.Combat(takenPerSecond: 90, hitsPerSecond: 2, physicalShare: 1)
        XCTAssertEqual(GearAdvisor.stopped(["armor": armor], shielding: 10, combat: melee), 15, accuracy: 0.001)
    }
}

final class HitsTests: XCTestCase {
    func testMeasuredHitsSplitTheDamageForTheAdvisor() {
        var tracker = HitsTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        // Two minutes of 2 melee hits of 30 a second on the knight, and a fire spell of 60 every 2 seconds.
        for step in 0..<40 {
            tracker.add(["melee": ["hits": 6, "amount": 180, "max": 45],
                         "magic": ["COMBAT_FIREDAMAGE": ["casts": 1, "amount": 90]],
                         "creatures": ["Bog Raider": ["hits": 6, "melee": 180, "max": 45, "magic": 0],
                                       "Swamp Troll": ["hits": 0, "melee": 0, "max": 0, "magic": 90]]],
                        at: start.addingTimeInterval(Double(step + 1) * 3))
        }
        let summary = tracker.summary()!
        XCTAssertEqual(summary["seconds"] as? Int, 120)
        XCTAssertEqual(summary["hitsPerSecond"] as! Double, 2, accuracy: 0.001)
        XCTAssertEqual(summary["meleeShare"] as! Double, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual((summary["creatures"] as! [[String: Any]]).map { $0["name"] as? String }, ["Bog Raider", "Swamp Troll"])
        XCTAssertEqual(summary["enough"] as? Bool, true)

        let combat = GearAdvisor.combat(analyzer: ["elapsedMs": 600_000, "damageTaken": 54_000], hits: summary)!
        XCTAssertEqual(combat.takenPerSecond, 90, accuracy: 0.001)
        XCTAssertEqual(combat.physicalShare, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(combat.elements["fire"] ?? 0, 1, accuracy: 0.001)
        // Fire protection now weighs all the magic part: 30/s, 10% of it stopped is 30 × 0.1 / 0.9.
        let cape = GearAdvisor.Item(slot: "armor", name: "cape", stats: ["attrs.absorbpercentfire": 10])
        XCTAssertEqual(GearAdvisor.stopped(["armor": cape], shielding: 10, combat: combat), 30 * 0.1 / 0.9, accuracy: 0.001)
    }

    func testConditionsCountAsTheirElementAndLifeDrainAsUnprotected() {
        let hits: [String: Any] = ["enough": true, "meleeShare": 0.2, "hitsPerSecond": 0.5,
                                   "elements": ["COMBAT_LIFEDRAIN": 0.4, "CONDITION_POISON": 0.2, "COMBAT_EARTHDAMAGE": 0.1, "CONDITION_BLEEDING": 0.1]]
        let combat = GearAdvisor.combat(analyzer: ["elapsedMs": 600_000, "damageTaken": 60_000], hits: hits)!
        XCTAssertEqual(combat.elements["earth"] ?? 0, 0.375, accuracy: 0.001)
        XCTAssertEqual(combat.elements["physical"] ?? 0, 0.125, accuracy: 0.001)
        XCTAssertNil(combat.elements["lifedrain"])
        // Bleeding meets physical protection: 100/s × 0.8 magic × 0.125 = 10/s, 10% of it is 10 × 0.1 / 0.9 (plus the melee part).
        let legs = GearAdvisor.Item(slot: "legs", name: "legs", stats: ["attrs.absorbpercentphysical": 10])
        let noMelee = GearAdvisor.Combat(takenPerSecond: 100, hitsPerSecond: 0, physicalShare: 0, elements: ["physical": 1])
        XCTAssertEqual(GearAdvisor.stopped(["legs": legs], shielding: 10, combat: noMelee), 100 * 0.1 / 0.9, accuracy: 0.001)
    }

    func testTooShortToMeasure() {
        var tracker = HitsTracker()
        tracker.add(["melee": ["hits": 3, "amount": 90, "max": 40]], at: Date(timeIntervalSince1970: 0))
        XCTAssertNil(tracker.summary())
    }
}
