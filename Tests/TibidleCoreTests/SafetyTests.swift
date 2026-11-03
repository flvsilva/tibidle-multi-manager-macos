import XCTest
@testable import TibidleCore

final class SafetyTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 2_000_000)

    private func frame(_ store: DashboardStore, knightHp: Int, analyzer: String = #"{"elapsedMs":60000}"#) {
        clock.addTimeInterval(3)
        store.ingest(account: 0, json: #"{"type":"frame","data":{"analyzer":\#(analyzer),"state":{"character":{"level":101},"party":[{"name":"K","vocation":"KNIGHT","hp":\#(knightHp),"maxHp":1000}]}}}"#)
    }

    private func state(_ store: DashboardStore) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: store.stateJSON()) as! [String: Any]
    }

    func testIgnoredAdviceLeavesThePanelForTheHuntOrForGood() {
        let store = DashboardStore(databaseURL: nil, now: { [unowned self] in clock })
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":9}}"#)
        for hp in Array(repeating: 1000, count: 10) + [200] + Array(repeating: 900, count: 14) { frame(store, knightHp: hp) }
        let risk = (state(store)["attention"] as! [[String: Any]]).first { $0["kind"] as? String == "risk" }!
        let mute = risk["mute"] as! String
        XCTAssertEqual(mute, "risk|0|9")
        XCTAssertTrue(store.mute(mute, always: false))
        XCTAssertNil((state(store)["attention"] as! [[String: Any]]).first { $0["kind"] as? String == "risk" })
        XCTAssertEqual((state(store)["muted"] as! [[String: Any]]).first?["always"] as? Bool, false)
        XCTAssertTrue(store.attention().allSatisfy { $0.kind != "risk" })
        // A new hunt brings it back; "always" keeps it away.
        clock.addTimeInterval(60)
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":9}}"#)
        for hp in Array(repeating: 1000, count: 10) + [200] + Array(repeating: 900, count: 14) { frame(store, knightHp: hp) }
        XCTAssertNotNil((state(store)["attention"] as! [[String: Any]]).first { $0["mute"] as? String == mute })
        XCTAssertTrue(store.mute(mute, always: true))
        XCTAssertNil((state(store)["attention"] as! [[String: Any]]).first { $0["mute"] as? String == mute })
        store.unmute(mute)
        XCTAssertNotNil((state(store)["attention"] as! [[String: Any]]).first { $0["mute"] as? String == mute })
        // Events (a finished hunt, a mission) cannot be muted.
        XCTAssertFalse(store.mute("ended|0|1", always: true))
    }

    func testDangerMomentsSayHowLowHowLongAndWhatHit() {
        var tracker = DangerTracker()
        let start = Date(timeIntervalSince1970: 1000)
        let hits: [String: Any] = ["creatures": [["name": "Ravenlich", "melee": 0, "magic": 420], ["name": "Lanternbone Dragon", "melee": 300, "magic": 0]]]
        for (i, hp) in [900, 350, 300, 500, 700, 900, 380, 450].enumerated() {
            tracker.add(party: [["vocation": "KNIGHT", "hp": hp, "maxHp": 1000]], at: start.addingTimeInterval(Double(i) * 3)) { hits }
        }
        let summary = tracker.summary()!
        XCTAssertEqual(summary["count"] as? Int, 2)
        let moments = summary["moments"] as! [[String: Any]]
        XCTAssertEqual(moments[0]["ongoing"] as? Bool, true)
        XCTAssertEqual(moments[1]["lowest"] as? Double, 0.3)
        XCTAssertEqual(moments[1]["health"] as? Int, 300)
        XCTAssertEqual(moments[1]["seconds"] as? Int, 9)
        XCTAssertEqual((moments[1]["creatures"] as? [[String: Any]])?.first?["name"] as? String, "Ravenlich")
        XCTAssertNil(DangerTracker().summary())
    }

    func testHealingCostAgainstTheMapsHunts() {
        let store = DashboardStore(databaseURL: nil, now: { [unowned self] in clock })
        for (supplies, taken) in [(10_000, 100_000), (12_000, 100_000), (20_000, 100_000)] {
            store.ingest(account: 1, json: #"{"type":"hunt_started","data":{"huntId":9,"state":{"character":{"level":100}}}}"#)
            clock.addTimeInterval(3600)
            store.ingest(account: 1, json: #"{"type":"ended","data":{"summary":{"huntId":9,"elapsedSec":3600,"level":{"start":100,"end":100},"suppliesGold":\#(supplies),"damageTaken":\#(taken)}}}"#)
        }
        store.ingest(account: 0, json: #"{"type":"hunt_started","data":{"huntId":9,"state":{"character":{"level":101}}}}"#)
        frame(store, knightHp: 1000, analyzer: #"{"elapsedMs":1800000,"damageTaken":50000,"healingDone":20000,"suppliesGold":9000}"#)
        let account = (state(store)["accounts"] as! [[String: Any]])[0]
        let healing = account["healing"] as! [String: Any]
        XCTAssertEqual(healing["suppliesPerThousand"] as! Double, 180, accuracy: 0.01)
        XCTAssertEqual(healing["healingShare"] as! Double, 0.4, accuracy: 0.001)
        XCTAssertEqual(healing["healingPerHour"] as? Int, 40000)
        let reference = healing["reference"] as! [String: Any]
        XCTAssertEqual(reference["median"] as? Double, 120)
        XCTAssertEqual(reference["best"] as? Double, 100)
        XCTAssertEqual(reference["runs"] as? Int, 3)
    }
}
