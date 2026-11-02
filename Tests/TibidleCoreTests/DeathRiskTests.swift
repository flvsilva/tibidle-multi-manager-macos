import XCTest
@testable import TibidleCore

final class DeathRiskTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A party of a knight and a druid, fed `count` frames 3 s apart: the druid is back to full health on every
    /// even frame and has lost `hit(i)` on the odd ones, healing included.
    private func feed(_ count: Int, druidHp: Double = 800, hit: (Int) -> Double) -> DeathRisk {
        var risk = DeathRisk()
        for i in 0..<count {
            let druid = i % 2 == 0 ? druidHp : max(0, druidHp - hit(i))
            let party: [[String: Any]] = [["vocation": "KNIGHT", "hp": 2000 - Double(i % 2) * 50, "maxHp": 2000], ["vocation": "DRUID", "hp": druid, "maxHp": 800]]
            risk.add(party: party, at: start.addingTimeInterval(Double(i) * 3))
        }
        return risk
    }

    func testNothingBeforeTenMinutesOfWindows() {
        XCTAssertNil(feed(150) { _ in 100 }.estimate(now: start.addingTimeInterval(300)))
    }

    func testSmallSteadyHitsAreSafe() {
        let risk = feed(400) { Double(60 + $0 % 40) }
        let estimate = risk.estimate(now: start.addingTimeInterval(1200))!
        XCTAssertEqual(estimate["source"] as? String, "live")
        XCTAssertLessThan(estimate["perHour"] as! Double, 0.01)
    }

    func testOccasionalBigHitsAgainstLowHealthAreRisky() {
        // Now and then the druid loses 500-700 of its 800 hp in 3 s: the tail reaches past its health.
        let risk = feed(400) { $0 % 25 == 1 ? Double(500 + ($0 * 7) % 200) : 80 }
        let estimate = risk.estimate(now: start.addingTimeInterval(1200))!
        let chance = estimate["perHour"] as! Double
        XCTAssertGreaterThan(chance, DeathRisk.alertPerHour)
        let top = (estimate["members"] as! [[String: Any]]).first!
        XCTAssertEqual(top["vocation"] as? String, "DRUID")
        XCTAssertEqual(top["maxHealth"] as? Int, 800)
        // More health, less risk.
        let safer = feed(400, druidHp: 800) { $0 % 25 == 1 ? Double(300 + ($0 * 7) % 100) : 80 }.estimate(now: start.addingTimeInterval(1200))!
        XCTAssertLessThan(safer["perHour"] as! Double, chance)
    }

    func testHealingWithinTheWindowCounts() {
        // Big hits healed right away (the knight at 1600 in 3 s, back near full): only the net loss counts.
        let risk = feed(400) { _ in 120 }
        XCTAssertLessThan(risk.estimate(now: start.addingTimeInterval(1200))!["perHour"] as! Double, 0.001)
    }

    func testGapsAreNotWindows() {
        var risk = DeathRisk()
        for i in 0..<300 {
            // 60 s apart: none of them counts.
            risk.add(party: [["vocation": "KNIGHT", "hp": i % 2 == 0 ? 100 : 10, "maxHp": 100]], at: start.addingTimeInterval(Double(i) * 60))
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
        XCTAssertEqual(item.text, "Zolp: risco de morte ~18%/h pela vida perdida nesta hunt. Mais exposto: Druid — em 3 s chegou a perder 640 de vida, com vida mínima de 310/800.")
        var low = entry; low["deathRisk"] = ["perHour": 0.02, "source": "live"]
        XCTAssertNil(Attention.evaluate(accounts: [low], now: 0).first { $0.key.hasPrefix("deathrisk") })
        var history = entry; history["deathRisk"] = ["perHour": 0.2, "source": "history", "deaths": 4, "hours": 15.3]
        let past = Attention.evaluate(accounts: [history], now: 0).first { $0.key.hasPrefix("deathrisk") }!
        XCTAssertEqual(past.level, "warn")
        XCTAssertFalse(past.notify)
    }
}
