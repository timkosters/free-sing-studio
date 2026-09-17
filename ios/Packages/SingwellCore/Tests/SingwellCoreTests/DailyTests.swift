import XCTest
@testable import SingwellCore

final class DailyTests: XCTestCase {
    func testRoutinesArePlayable() {
        for routine in Daily.routines {
            XCTAssertGreaterThanOrEqual(routine.steps.count, 4, routine.id.rawValue)
            for step in routine.steps {
                XCTAssertTrue(step.seconds >= 30 && step.seconds <= 600, step.id)
                XCTAssertFalse(step.cue.isEmpty); XCTAssertFalse(step.detail.isEmpty); XCTAssertFalse(step.why.isEmpty)
                if step.engine == .hold { XCTAssertNotNil(step.hold) }
                if step.engine == .breath { XCTAssertNotNil(step.breath) }
            }
            XCTAssertTrue(routine.seconds >= 8 * 60 && routine.seconds <= 25 * 60, routine.id.rawValue)
        }
        XCTAssertEqual(Daily.routine(.quick).lengthLabel, "10 min")
        XCTAssertEqual(Daily.stepKey(Daily.routines[2].steps[7], index: 7), "7:bridge")
    }

    func testDayKeysShift() {
        XCTAssertEqual(Daily.shiftDay("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(Daily.shiftDay("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(Daily.shiftDay("2024-02-28", 1), "2024-02-29")
        XCTAssertEqual(Daily.shiftDay("2026-09-16", 0), "2026-09-16")
        XCTAssertEqual(Daily.dayKey().count, 10)
    }

    func testLogStreaks() {
        var log = Daily.Log()
        XCTAssertEqual(log.streak(today: "2026-09-16"), 0)
        log = log.loggingStep(seconds: 60, key: "2026-09-14", now: 1)
        log = log.loggingStep(seconds: 60, key: "2026-09-15", now: 2)
        // Untouched today shows yesterday's streak, not zero.
        XCTAssertEqual(log.streak(today: "2026-09-16"), 2)
        log = log.loggingStep(seconds: 30, key: "2026-09-16", now: 3)
        XCTAssertEqual(log.streak(today: "2026-09-16"), 3)
        // A missed day breaks it.
        XCTAssertEqual(log.streak(today: "2026-09-18"), 0)
        log = log.loggingStep(seconds: 30, key: "2026-09-10", now: 4)
        XCTAssertEqual(log.bestStreak, 3)
        XCTAssertEqual(log.totalDays, 4)
        XCTAssertEqual(log.totalSeconds, 180)
        log = log.loggingComplete(key: "2026-09-16", now: 5)
        XCTAssertTrue(log.days["2026-09-16"]!.completed)
        let recent = log.recentDays(3, today: "2026-09-16")
        XCTAssertEqual(recent.map { $0.key }, ["2026-09-14", "2026-09-15", "2026-09-16"])
        XCTAssertEqual(recent[0].day?.steps, 1)
        XCTAssertEqual(Daily.parse(Daily.serialize(log)), log)
        XCTAssertEqual(Daily.parse("{\"version\":2}".data(using: .utf8)), Daily.Log())
        let messy = Daily.parse("{\"days\":{\"bad\":{\"seconds\":5},\"2026-01-01\":{\"seconds\":-1,\"steps\":2.9,\"completed\":\"yes\"}}}".data(using: .utf8))
        XCTAssertEqual(messy.days.count, 1)
        XCTAssertEqual(messy.days["2026-01-01"]?.seconds, 0)
        XCTAssertEqual(messy.days["2026-01-01"]?.steps, 2)
        XCTAssertEqual(messy.days["2026-01-01"]?.completed, false)
    }
}
