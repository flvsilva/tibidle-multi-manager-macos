import XCTest
@testable import TibidleCore

final class SkillTrainingTests: XCTestCase {
    private func member(_ level: Int, _ pct: Int) -> [String: Any] {
        ["name": "K", "vocation": "KNIGHT", "skillLevels": ["melee": level, "magic": 9], "skillProgress": ["melee": pct, "magic": 50]]
    }

    func testPaceOfTheLastTenMinutesAndTheNextLevel() {
        var training = SkillTraining()
        let start = Date(timeIntervalSince1970: 1000)
        // 1% every 2 minutes for 30 minutes, through a level up: 60 (90%) → 61 (5%).
        for i in 0...300 {
            let progress = 6090 + i / 20
            training.add(party: [member(progress / 100, progress % 100)], at: start.addingTimeInterval(Double(i) * 6))
        }
        let rows = training.summary()![0]["skills"] as! [[String: Any]]
        XCTAssertEqual(rows.count, 1, "magic did not move")
        let melee = rows[0]
        XCTAssertEqual(melee["level"] as? Int, 61)
        XCTAssertEqual(melee["pct"] as! Double, 5, accuracy: 0.001)
        XCTAssertEqual(melee["minutes"] as? Int, 10)
        XCTAssertEqual(melee["perHour"] as! Double, 30, accuracy: 0.1)
        XCTAssertEqual(melee["nextInSec"] as! Double, 95.0 / 30 * 3600, accuracy: 30)
    }

    func testASlowSkillLooksFurtherBack() {
        var training = SkillTraining()
        let start = Date(timeIntervalSince1970: 1000)
        // 1% every 15 minutes: the last 10 minutes hold at most 1%, so it looks over 40 minutes.
        for i in 0...600 {
            training.add(party: [member(60, i / 150)], at: start.addingTimeInterval(Double(i) * 6))
        }
        let melee = (training.summary()![0]["skills"] as! [[String: Any]])[0]
        XCTAssertEqual(melee["minutes"] as? Int, 30)
        XCTAssertEqual(melee["perHour"] as! Double, 4, accuracy: 0.5)
    }

    func testNothingBeforeItMovesAndALossStartsOver() {
        var training = SkillTraining()
        let start = Date(timeIntervalSince1970: 1000)
        for i in 0...100 { training.add(party: [member(60, 10)], at: start.addingTimeInterval(Double(i) * 6)) }
        XCTAssertNil(training.summary())
        for i in 0...100 { training.add(party: [member(60, 10 + i / 10)], at: start.addingTimeInterval(606 + Double(i) * 6)) }
        XCTAssertNotNil(training.summary())
        training.add(party: [member(59, 80)], at: start.addingTimeInterval(1300))
        XCTAssertNil(training.summary())
    }
}
