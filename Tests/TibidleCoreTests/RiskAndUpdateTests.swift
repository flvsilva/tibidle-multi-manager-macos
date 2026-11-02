import XCTest
@testable import TibidleCore

final class RiskTests: XCTestCase {
    private func hunting(party: [[String: Any]], creatures: [[String: Any]] = []) -> [String: Any] {
        ["index": 0, "label": "Peasant", "status": "hunting", "huntId": 7,
         "state": ["party": party], "hits": ["creatures": creatures]]
    }

    func testWarnsWhenSomeoneNearlyDiedAndSaysWhoHurtsMost() {
        let entry = hunting(party: [["vocation": "KNIGHT", "maxHp": 1600, "hpLowest": 0.22], ["vocation": "SORCERER", "maxHp": 650, "hpLowest": 0.7]],
                            creatures: [["name": "Ravenlich", "share": 0.72, "meleeMax": 30]])
        let items = Attention.evaluate(accounts: [entry], now: 0).filter { $0.kind == "risk" }
        XCTAssertEqual(items.map(\.level), ["warn"])
        XCTAssertEqual(items.first?.text, "Peasant: o Knight chegou a 22% da vida nesta hunt; quem mais machuca é Ravenlich (72% do dano).")
        XCTAssertFalse(items[0].notify)
    }

    func testCriticalHealthNotifiesAndABigHitNamesTheCreature() {
        let entry = hunting(party: [["vocation": "ELITE KNIGHT", "maxHp": 1000, "hpLowest": 0.1]],
                            creatures: [["name": "Ravenlich", "share": 0.7, "meleeMax": 30], ["name": "Lanternbone Dragon", "share": 0.3, "meleeMax": 450]])
        let item = Attention.evaluate(accounts: [entry], now: 0).first { $0.kind == "risk" }!
        XCTAssertEqual(item.level, "bad")
        XCTAssertTrue(item.notify)
        XCTAssertEqual(item.text, "Peasant: o Knight chegou a 10% da vida nesta hunt; Lanternbone Dragon acerta até 450 no Knight (45% da vida).")
    }

    func testQuietWhenTheHuntIsSafe() {
        let entry = hunting(party: [["vocation": "KNIGHT", "maxHp": 2800, "hpLowest": 0.57]], creatures: [["name": "Lanternbone Dragon", "share": 0.75, "meleeMax": 289]])
        XCTAssertTrue(Attention.evaluate(accounts: [entry], now: 0).filter { $0.kind == "risk" }.isEmpty)
    }
}

final class WeaponTests: XCTestCase {
    func testWarnsAboutAWandOrRodOfAResistedElement() {
        let entry: [String: Any] = ["index": 1, "label": "Zolp", "status": "hunting", "gearAdvice": [
            ["kind": "element", "vocation": "DRUID", "weapon": "springsprout rod", "damageShare": 0.0, "to": "glacial rod (gelo, 100%)", "source": "showshow"],
            ["kind": "element", "vocation": "SORCERER", "weapon": "wand of inferno", "damageShare": 0.65, "to": "wand of destruction (energia, 84%)"],
            ["kind": "defense", "vocation": "KNIGHT", "text": "…"],
        ]]
        let items = Attention.evaluate(accounts: [entry], now: 0).filter { $0.kind == "weapon" }
        XCTAssertEqual(items.map(\.text), ["Zolp: Druid com springsprout rod causa só 0% do dano nos monstros desta hunt — " +
                                           "troque por glacial rod (gelo, 100%) (usada em showshow)."])
    }
}

final class UpdateTests: XCTestCase {
    func testComparesVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testReadsTheLatestReleaseAndOnlyKeepsGitHubPages() {
        let ok = Data(#"{"tag_name":"v1.0.1","html_url":"https://github.com/flvsilva/tibidle-multi-manager-macos/releases/tag/v1.0.1"}"#.utf8)
        XCTAssertEqual(UpdateChecker.release(from: ok)?.version, "1.0.1")
        let elsewhere = Data(#"{"tag_name":"v9.0.0","html_url":"https://example.com/x"}"#.utf8)
        XCTAssertNil(UpdateChecker.release(from: elsewhere))
        let odd = Data(#"{"tag_name":"v1.0.1-beta<script>","html_url":"https://github.com/x"}"#.utf8)
        XCTAssertNil(UpdateChecker.release(from: odd))
    }

    func testTheDashboardStateCarriesTheUpdate() throws {
        let store = DashboardStore(databaseURL: nil)
        store.setUpdate(("1.0.1", "https://github.com/flvsilva/tibidle-multi-manager-macos/releases/tag/v1.0.1"))
        let state = try JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any]
        XCTAssertEqual((state["update"] as? [String: String])?["version"], "1.0.1")
        store.setUpdate(nil)
        XCTAssertNil((try JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any])["update"])
    }
}
