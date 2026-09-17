import XCTest
@testable import SingwellCore

final class HistoryTests: XCTestCase {
    func json(_ s: String) -> Data { s.data(using: .utf8)! }

    func testGapsAndCorruptDataCannotFabricate() {
        var s = History.Sustain().tracking(midi: 60, now: 0)
        s = s.tracking(midi: 60, now: 300)
        XCTAssertNil(s.low)
        XCTAssertEqual(History.parse(json("{\"version\":99}")), History.Record())
        let h = History.parse(json("{\"low\":-999,\"high\":999,\"quest\":{\"quickestAverage\":-3,\"widestLow\":80,\"widestHigh\":30}}"))
        XCTAssertNil(h.low); XCTAssertNil(h.high)
        XCTAssertNil(h.quest.quickestAverage)
        XCTAssertEqual(h.quest.widestLow, 30); XCTAssertEqual(h.quest.widestHigh, 80)
    }

    func testOnlySustainedNotesWidenRange() {
        var s = History.Sustain()
        s = s.tracking(midi: 72, now: 0)
        s = s.tracking(midi: 72.1, now: 0.2)
        s = s.tracking(midi: nil, now: 0.3)
        XCTAssertNil(s.low); XCTAssertNil(s.high)
        s = s.tracking(midi: 57.05, now: 1)
        s = s.tracking(midi: 56.95, now: 1.3)
        XCTAssertNil(s.low)
        s = s.tracking(midi: 57.02, now: 1 + History.sustainSeconds)
        XCTAssertEqual(s.low, 57); XCTAssertEqual(s.high, 57)
        s = s.tracking(midi: 64, now: 2)
        s = s.tracking(midi: 64, now: 2.2)
        XCTAssertEqual(s.high, 57)
        s = s.tracking(midi: 64, now: 2.6)
        XCTAssertEqual(s.high, 64); XCTAssertEqual(s.low, 57)
        let quiet = s.tracking(midi: nil, now: 3)
        XCTAssertEqual(quiet.low, 57)
        XCTAssertEqual(quiet.tracking(midi: nil, now: 3.1), quiet)
        XCTAssertEqual(quiet.tracking(midi: .nan, now: 3.2), quiet)
        s = quiet.tracking(midi: 48, now: 4)
        s = s.tracking(midi: 48, now: 4.6)
        XCTAssertEqual(s.low, 48); XCTAssertEqual(s.high, 64)
        XCTAssertEqual(Formatting.rangeSpan(s.low, s.high), 16)
        XCTAssertNil(Formatting.rangeSpan(nil, 64))
    }

    func testDefensiveParseAndRoundTrip() {
        XCTAssertEqual(History.parse(nil), History.Record())
        XCTAssertEqual(History.parse(Data()), History.Record())
        XCTAssertEqual(History.parse(json("not json")), History.Record())
        XCTAssertEqual(History.parse(json("42")), History.Record())
        XCTAssertEqual(History.parse(json("[]")).quest, History.Record().quest)
        let messy = History.parse(json("{\"seconds\":-5,\"sessions\":2.7,\"low\":70,\"high\":50,\"quest\":{\"runs\":\"x\",\"mostMatched\":3,\"quickestAverage\":null}}"))
        XCTAssertEqual(messy.seconds, 0)
        XCTAssertEqual(messy.sessions, 2)
        XCTAssertEqual(messy.low, 50); XCTAssertEqual(messy.high, 70)
        XCTAssertEqual(messy.quest.runs, 0)
        XCTAssertEqual(messy.quest.mostMatched, 3)
        XCTAssertNil(messy.quest.quickestAverage)
        XCTAssertEqual(History.parse(json("{\"low\":55}")).high, 55)
        var h = History.Record()
        h = h.addingPractice(seconds: 90, now: 1000)
        h = h.recordingSession(now: 1001)
        h = h.recordingRange(low: 50, high: 62, now: 1002)
        XCTAssertEqual(History.parse(History.serialize(h)), h)
    }

    func testAccumulatesWithoutShrinking() {
        var h = History.Record()
        h = h.addingPractice(seconds: 30, now: 1)
        h = h.addingPractice(seconds: -10, now: 2)
        h = h.addingPractice(seconds: .nan, now: 3)
        XCTAssertEqual(h.seconds, 30); XCTAssertEqual(h.updated, 1)
        XCTAssertEqual(h.addingPractice(seconds: 0, now: 9), h)
        h = h.recordingRange(low: 55, high: 60, now: 4)
        h = h.recordingRange(low: 57, high: 58, now: 5)
        XCTAssertEqual([h.low, h.high], [55, 60]); XCTAssertEqual(h.updated, 4)
        h = h.recordingRange(low: 50, high: 65, now: 6)
        XCTAssertEqual([h.low, h.high], [50, 65])
        XCTAssertEqual(h.recordingRange(low: nil, high: 70, now: 7), h)
        h = h.recordingQuest(Quest.Summary(matched: 5, total: 8, skipped: 3, averageSeconds: 1.8, low: 55, high: 60), now: 8)
        XCTAssertEqual(h.quest.runs, 1); XCTAssertEqual(h.quest.mostMatched, 5)
        XCTAssertNil(h.quest.quickestAverage)
        XCTAssertEqual([h.quest.widestLow, h.quest.widestHigh], [55, 60])
        h = h.recordingQuest(Quest.Summary(matched: 8, total: 8, skipped: 0, averageSeconds: 2.2, low: 57, high: 59), now: 9)
        XCTAssertEqual(h.quest.mostMatched, 8); XCTAssertEqual(h.quest.quickestAverage, 2.2)
        XCTAssertEqual([h.quest.widestLow, h.quest.widestHigh], [55, 60])
        h = h.recordingQuest(Quest.Summary(matched: 8, total: 8, skipped: 0, averageSeconds: 1.5, low: 50, high: 64), now: 10)
        XCTAssertEqual(h.quest.quickestAverage, 1.5)
        XCTAssertEqual([h.quest.widestLow, h.quest.widestHigh], [50, 64])
        XCTAssertEqual(h.quest.runs, 3)
        h = h.recordingQuest(Quest.Summary(matched: 0, total: 5, skipped: 5, averageSeconds: nil, low: nil, high: nil), now: 11)
        XCTAssertEqual(h.quest.runs, 4); XCTAssertEqual(h.quest.mostMatched, 8)
        XCTAssertEqual(h.recordingSession(now: 12).sessions, 1)
    }

    func testMinutesLabel() {
        XCTAssertEqual(Formatting.minutes(0), "0 sec")
        XCTAssertEqual(Formatting.minutes(45), "45 sec")
        XCTAssertEqual(Formatting.minutes(60), "1 min")
        XCTAssertEqual(Formatting.minutes(150), "3 min")
        XCTAssertEqual(Formatting.minutes(3600), "1 h")
        XCTAssertEqual(Formatting.minutes(3600 * 2 + 60 * 5), "2 h 5 min")
        XCTAssertEqual(Formatting.minutes(-20), "0 sec")
    }
}
