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
        let advice = GearAdvisor.suggestions(for: 0, members: GearAdvisor.members(accounts: accounts)) { shares[$0] }

        XCTAssertEqual(advice.map { $0["kind"] as? String }, ["element", "defense", "element"])
        XCTAssertEqual(advice[0]["text"] as? String, "Sorcerer · arma: wand of inferno (fogo, 15% do dano) → uma wand/rod de outro elemento")
        // Same helmet: nothing to gain. Magic plate armor needs level 200.
        XCTAssertEqual(advice[1]["text"] as? String,
                       "Knight · escudo: bone shield (def 20) → mastermind shield (def 37, +3 shielding) (usado em Zolp)")
        XCTAssertEqual(advice[2]["to"] as? String, "glacial rod (gelo, 105%)")
        XCTAssertEqual(advice[2]["source"] as? String, "Zolp")
    }

    func testFallsBackToTheKnightBeforeHealthIsKnown() {
        let accounts = [
            account(0, "A", [["vocation": "Royal Paladin", "level": 100, "gear": ["armor": item("leather armor", ["attrs.armor": 4])]],
                             ["vocation": "Knight", "level": 100, "gear": ["armor": item("chain armor", ["attrs.armor": 6])]]]),
            account(1, "B", [["vocation": "Elite Knight", "level": 100, "gear": ["armor": item("crown armor", ["attrs.armor": 13])]]]),
        ]
        let advice = GearAdvisor.suggestions(for: 0, members: GearAdvisor.members(accounts: accounts)) { _ in nil }
        XCTAssertEqual(advice.count, 1)
        XCTAssertEqual(advice[0]["gain"] as? Int, 7)
        XCTAssertEqual(advice[0]["vocation"] as? String, "KNIGHT")
    }
}
