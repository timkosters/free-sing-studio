import XCTest
@testable import SingwellCore

final class ProfileTests: XCTestCase {
    func testRowIsRangeCheckedAndOrdered() {
        let p = Profile(row: .init(low_note: 70, high_note: 40, break_low: 200, break_high: 66, songs: ["  Blackbird ", "", String(repeating: "x", count: 100)], hard_line: "   "))
        XCTAssertEqual(p.low, 40); XCTAssertEqual(p.high, 70)
        XCTAssertNil(p.breakLow); XCTAssertEqual(p.breakHigh, 66)
        XCTAssertEqual(p.songs.count, 2)
        XCTAssertEqual(p.songs[0], "Blackbird")
        XCTAssertEqual(p.songs[1].count, 80)
        XCTAssertNil(p.hardLine)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(Profile().isEmpty)
        XCTAssertEqual(Profile(row: p.row), p)
    }

    func testPersonalizationOnlyTouchesFilledFields() {
        var p = Profile()
        let steps = Daily.routine(.full).steps
        XCTAssertEqual(p.personalize(steps), steps)
        p.breakLow = 65; p.breakHigh = 69; p.hardLine = "Into the light"; p.songs = ["Blackbird", "Vienna"]
        let out = p.personalize(steps)
        let bridge = out.first { $0.id == "bridge" }!
        XCTAssertTrue(bridge.cue.contains("F4–A4"), bridge.cue)
        XCTAssertTrue(bridge.cue.contains("Slide from D4"), bridge.cue)
        XCTAssertTrue(out.first { $0.id == "hard-line" }!.cue.contains("Into the light"))
        XCTAssertTrue(out.first { $0.id == "song" }!.detail[0].hasPrefix("Blackbird or Vienna."))
        XCTAssertEqual(out.first { $0.id == "noi" }!.detail, steps.first { $0.id == "noi" }!.detail)
        p.low = 42
        XCTAssertTrue(p.personalize(steps).first { $0.id == "noi" }!.detail[3].contains("F♯2"))
    }
}
