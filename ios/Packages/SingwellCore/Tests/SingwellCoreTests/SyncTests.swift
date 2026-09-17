import XCTest
@testable import SingwellCore

final class SyncTests: XCTestCase {
    func testRowsRoundTripAndDropJunk() {
        let rows = [Sync.Row(day: "2026-09-16T00:00:00", seconds: 120, steps: 3, completed: true),
                    Sync.Row(day: "not a day", seconds: 5, steps: 1, completed: false),
                    Sync.Row(day: "2026-09-15", seconds: -4, steps: 2, completed: false)]
        let log = Sync.log(from: rows)
        XCTAssertEqual(log.days.count, 2)
        XCTAssertEqual(log.days["2026-09-16"]?.seconds, 120)
        XCTAssertEqual(log.days["2026-09-16"]?.completed, true)
        XCTAssertEqual(log.days["2026-09-15"]?.seconds, 0)
        let back = Sync.rows(from: log)
        XCTAssertEqual(back.map { $0.day }, ["2026-09-15", "2026-09-16"])
        XCTAssertEqual(back[1].steps, 3)
    }

    func testMergeTakesTheLargerValueAndIsCommutative() {
        var a = Daily.Log(); a = a.loggingStep(seconds: 100, key: "2026-09-10", now: 1); a = a.loggingStep(seconds: 50, key: "2026-09-11", now: 2)
        var b = Daily.Log(); b = b.loggingStep(seconds: 30, key: "2026-09-10", now: 3); b = b.loggingStep(seconds: 30, key: "2026-09-10", now: 4)
        b = b.loggingComplete(key: "2026-09-10", now: 5); b = b.loggingStep(seconds: 10, key: "2026-09-12", now: 6)
        let ab = Sync.merge(a, b), ba = Sync.merge(b, a)
        XCTAssertEqual(ab.days, ba.days)
        XCTAssertEqual(ab.days["2026-09-10"]?.seconds, 100)
        XCTAssertEqual(ab.days["2026-09-10"]?.steps, 2)
        XCTAssertEqual(ab.days["2026-09-10"]?.completed, true)
        XCTAssertEqual(ab.days.count, 3)
        XCTAssertEqual(Sync.merge(ab, ab).days, ab.days)
        XCTAssertTrue(Sync.needsPush(remote: b, merged: ab))
        XCTAssertFalse(Sync.needsPush(remote: ab, merged: ab))
    }

    func testEmailAndMessages() {
        XCTAssertTrue(Sync.looksLikeEmail(" timour@example.com "))
        XCTAssertFalse(Sync.looksLikeEmail("timour@example"))
        XCTAssertTrue(Sync.authMessage("Request rate limit reached").contains("Too many"))
        XCTAssertTrue(Sync.authMessage("Token has expired").contains("expired"))
        XCTAssertEqual(Sync.authMessage(nil), "Something went wrong. Please try again.")
        XCTAssertEqual(Sync.authMessage("Custom problem"), "Custom problem")
    }
}
