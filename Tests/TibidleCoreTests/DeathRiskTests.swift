import XCTest
@testable import TibidleCore

final class DeathRiskTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A party of a knight and a druid, fed `count` frames 3 s apart; `hit(i)` is the druid's magic damage in frame i.
    private func feed(_ count: Int, druidHp: Double = 800, hit: (Int) -> Double) -> DeathRisk {
        var risk = DeathRisk()
        let party: [[String: Any]] = [["vocation": "KNIGHT", "hp": 2000, "maxHp": 2000], ["vocation": "DRUID", "hp": druidHp, "maxHp": 800]]
        for i in 0..<count {
            let tally: [String: Any] = ["melee": ["amount": 50], "members": ["1": ["COMBAT_LIFEDRAIN": hit(i)]]]
            risk.add(party: party, tally: tally, at: start.addingTimeInterval(Double(i) * 3))
        }
        return risk
    }

    func testNothingBeforeTenMinutesOfWindows() {
        XCTAssertNil(feed(100) { _ in 100 }.estimate(now: start.addingTimeInterval(300)))
    }

    func testSmallSteadyHitsAreSafe() {
        let risk = feed(300) { $0 % 3 == 0 ? Double(60 + $0 % 40) : 0 }
        let estimate = risk.estimate(now: start.addingTimeInterval(900))!
        XCTAssertEqual(estimate["source"] as? String, "live")
        XCTAssertLessThan(estimate["perHour"] as! Double, 0.01)
    }

    func testOccasionalBigHitsAgainstLowHealthAreRisky() {
        // Every 25th window the druid takes 500-700 with 800 hp: the tail reaches past its health.
        let risk = feed(300) { $0 % 25 == 0 ? Double(500 + ($0 * 7) % 200) : Double($0 % 3 == 0 ? 80 : 0) }
        let estimate = risk.estimate(now: start.addingTimeInterval(900))!
        let chance = estimate["perHour"] as! Double
        XCTAssertGreaterThan(chance, DeathRisk.alertPerHour)
        let top = (estimate["members"] as! [[String: Any]]).first!
        XCTAssertEqual(top["vocation"] as? String, "DRUID")
        XCTAssertEqual(top["maxHealth"] as? Int, 800)
        // More health, less risk.
        let safer = feed(300, druidHp: 800) { $0 % 25 == 0 ? Double(300 + ($0 * 7) % 100) : 0 }.estimate(now: start.addingTimeInterval(900))!
        XCTAssertLessThan(safer["perHour"] as! Double, chance)
    }

    func testGapsAreNotWindows() {
        var risk = DeathRisk()
        let party: [[String: Any]] = [["vocation": "KNIGHT", "hp": 100, "maxHp": 100]]
        for i in 0..<300 {
            // 60 s apart: none of them counts.
            risk.add(party: party, tally: ["melee": ["amount": 90]], at: start.addingTimeInterval(Double(i) * 60))
        }
        XCTAssertNil(risk.estimate(now: start.addingTimeInterval(18000)))
    }

    func testHistoryPullsTowardsTheOverallRate() {
        let short = DeathRisk.fromHistory(deaths: 1, hours: 1, overallRate: 0.03)!
        XCTAssertEqual(short["rate"] as! Double, (1 + 0.3) / 11, accuracy: 1e-9)
        XCTAssertEqual(short["source"] as? String, "history")
        XCTAssertNil(DeathRisk.fromHistory(deaths: 0, hours: 0, overallRate: 0))
    }

    func testCalibrationNeedsTenHuntsAndStaysBounded() {
        XCTAssertEqual(DeathRisk.calibration(Array(repeating: (0.5, 0), count: 9)).factor, 1)
        XCTAssertEqual(DeathRisk.calibration(Array(repeating: (1.0, 0), count: 10)).factor, 0.25)
        XCTAssertEqual(DeathRisk.calibration(Array(repeating: (0.1, 1), count: 10)).factor, 4)
    }

    func testAttentionWarnsAndNotifiesFromTheLiveEstimate() {
        let risk: [String: Any] = ["perHour": 0.18, "source": "live",
                                   "members": [["vocation": "ELDER DRUID", "biggestWindow": 640, "lowestHealth": 310, "maxHealth": 800]]]
        let entry: [String: Any] = ["index": 0, "label": "Zolp", "status": "hunting", "huntId": 192, "deathRisk": risk]
        let item = Attention.evaluate(accounts: [entry], now: 0).first { $0.key.hasPrefix("deathrisk") }!
        XCTAssertEqual(item.level, "bad")
        XCTAssertTrue(item.notify)
        XCTAssertEqual(item.text, "Zolp: risco de morte ~18%/h pelo dano desta hunt. Mais exposto: Druid — em 3 s chegou a levar 640 de dano, com vida mínima de 310/800.")
        var low = entry; low["deathRisk"] = ["perHour": 0.02, "source": "live"]
        XCTAssertNil(Attention.evaluate(accounts: [low], now: 0).first { $0.key.hasPrefix("deathrisk") })
        var history = entry; history["deathRisk"] = ["perHour": 0.2, "source": "history", "deaths": 4, "hours": 15.3]
        let past = Attention.evaluate(accounts: [history], now: 0).first { $0.key.hasPrefix("deathrisk") }!
        XCTAssertEqual(past.level, "warn")
        XCTAssertFalse(past.notify)
    }
}
