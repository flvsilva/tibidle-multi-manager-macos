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

    func testBigLossesNearFullHealthDoNotCountAtLowHealth() {
        // The knight loses up to 1100 only from full health and is healed back up from anywhere below: a window
        // at 45% is judged by the windows that started near 45%, which never lost health.
        var risk = DeathRisk()
        var hp = 2000.0
        for i in 0..<400 {
            if hp >= 1800 { hp -= Double((i * 37) % 1100) } else { hp = min(2000, hp + 400) }
            risk.add(party: [["vocation": "KNIGHT", "hp": hp, "maxHp": 2000]], at: start.addingTimeInterval(Double(i) * 3))
        }
        XCTAssertLessThan(risk.estimate(now: start.addingTimeInterval(1200))!["perHour"] as! Double, 0.01)
    }

    func testTheMapHistoryOutweighsAFewMinutes() {
        // 400 hours with one death keep a noisy 20%/h near the map's rate; a map never hunted follows the live rate:
        // 10 h of it against 2 h of the overall rate.
        XCTAssertLessThan(DeathRisk.combined(live: 0.2, deaths: 1, hours: 400, overallRate: 0.01), 0.01)
        XCTAssertEqual(DeathRisk.combined(live: 0.2, deaths: 0, hours: 0, overallRate: 0.01), (2 * 0.01 + 0.2 * 10) / 12, accuracy: 1e-9)
        // The more the live rate has been measured, the more it weighs.
        XCTAssertGreaterThan(DeathRisk.combined(live: 0.2, deaths: 1, hours: 400, overallRate: 0.01, liveHours: 30),
                             DeathRisk.combined(live: 0.2, deaths: 1, hours: 400, overallRate: 0.01))
    }

    func testASustainedRateIsNotBuriedUnderAQuietMap() {
        // 50 minutes of big hits on the druid, the estimate accrued as the store does it, about once a minute.
        var risk = DeathRisk()
        for i in 0..<1000 {
            let date = start.addingTimeInterval(Double(i) * 3)
            let hp = i % 2 == 0 ? 800.0 : (i % 25 == 1 ? 800 - Double(500 + (i * 7) % 200) : 720)
            risk.add(party: [["name": "D", "vocation": "DRUID", "hp": hp, "maxHp": 800]], at: date)
            risk.accrue(now: date)
        }
        let now = start.addingTimeInterval(3000)
        let live = risk.estimate(now: now)!["rate"] as! Double
        XCTAssertGreaterThan(1 - exp(-live), DeathRisk.warnPerHour)
        XCTAssertNotNil(risk.highSince)
        let quiet = DeathRisk.combined(live: live, deaths: 1, hours: 400, overallRate: 0.01)
        XCTAssertLessThan(quiet, live / 3)
        XCTAssertEqual(risk.combined(live: live, deaths: 1, hours: 400, overallRate: 0.01, now: now), live / 3, accuracy: 1e-9)
        // A hunt that just started gets no floor.
        XCTAssertEqual(DeathRisk().combined(live: live, deaths: 1, hours: 400, overallRate: 0.01, now: now), quiet, accuracy: 1e-12)
    }

    func testTheTailKeepsTenExcessesAndTiesAtTheThreshold() {
        // 95 losses of 50 and 5 of 80: the old 90% threshold (50) left 5 excesses; now the top 10, five of them ties.
        let weighed = (Array(repeating: 50.0, count: 95) + Array(repeating: 80.0, count: 5)).map { (loss: $0, weight: 1.0) }
        let excess = DeathRisk.excess(weighed)!
        XCTAssertEqual(excess.count, 10)
        XCTAssertEqual(excess.threshold, 50)
        XCTAssertEqual(excess.mean, 15, accuracy: 1e-9)
        // Fewer windows than that: all of them, over zero.
        XCTAssertEqual(DeathRisk.excess([(loss: 10, weight: 1), (loss: 30, weight: 1)])!.mean, 20, accuracy: 1e-9)
        // Nothing lost: no tail.
        XCTAssertNil(DeathRisk.excess(Array(repeating: (loss: 0.0, weight: 1.0), count: 50)))
    }

    func testMembersChangingPlacesAreNotLosses() {
        // The game lists the knight (2000) and the druid (800) in a different order every frame, health unchanged:
        // by position that would read as 1200 lost every 3 s.
        var risk = DeathRisk()
        let knight: [String: Any] = ["name": "Z", "vocation": "Elite Knight", "hp": 2000, "maxHp": 2000]
        let druid: [String: Any] = ["name": "Z", "vocation": "Elder Druid", "hp": 800, "maxHp": 800]
        for i in 0..<400 { risk.add(party: i % 2 == 0 ? [knight, druid] : [druid, knight], at: start.addingTimeInterval(Double(i) * 3)) }
        XCTAssertNil(risk.estimate(now: start.addingTimeInterval(1200)), "no health was lost")
    }

    func testPausesDoNotStretchTheHour() {
        // The same hits after a 5-minute pause (early, so every window keeps its age and weight): the pause is no
        // window and does not dilute the rate (timed over the whole span, it read 30% lower).
        func feed(pauseAt: Int?) -> Double {
            var risk = DeathRisk()
            var time = 0.0
            for i in 0..<250 {
                if i == pauseAt { time += 300 }
                let hp = i % 2 == 0 ? 800.0 : (i % 25 == 13 ? 800 - Double(500 + (i * 7) % 200) : 720)
                risk.add(party: [["name": "D", "vocation": "DRUID", "hp": hp, "maxHp": 800]], at: start.addingTimeInterval(time))
                time += 3
            }
            return risk.estimate(now: start.addingTimeInterval(time))!["rate"] as! Double
        }
        let steady = feed(pauseAt: nil), paused = feed(pauseAt: 2)
        XCTAssertEqual(paused / steady, 1, accuracy: 0.02)
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
        XCTAssertEqual(item.text, "Zolp: risco de morte ~18%/h pela vida perdida nesta hunt e o histórico do mapa. Mais exposto: Druid — em 3 s chegou a perder 640 de vida, com vida mínima de 310/800.")
        var low = entry; low["deathRisk"] = ["perHour": 0.02, "source": "live"]
        XCTAssertNil(Attention.evaluate(accounts: [low], now: 0).first { $0.key.hasPrefix("deathrisk") })
        var history = entry; history["deathRisk"] = ["perHour": 0.2, "source": "history", "deaths": 4, "hours": 15.3]
        let past = Attention.evaluate(accounts: [history], now: 0).first { $0.key.hasPrefix("deathrisk") }!
        XCTAssertEqual(past.level, "warn")
        XCTAssertFalse(past.notify)
    }
}
