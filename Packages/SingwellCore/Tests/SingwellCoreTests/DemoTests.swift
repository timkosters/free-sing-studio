import XCTest
@testable import SingwellCore

final class DemoTests: XCTestCase {
    func testVoiceBreathesThenSettles() {
        XCTAssertNil(Demo.voice(local: 0, target: 60).midi)
        XCTAssertNil(Demo.voice(local: Demo.breath - 0.01, target: 60).midi)
        XCTAssertNil(Demo.voice(local: .nan, target: 60).midi)
        XCTAssertLessThan(Demo.voice(local: Demo.breath + 0.02, target: 61).midi!, 61 - 0.5)
        for target in [50.0, 61, 67, 76] {
            var t = Demo.breath + 1.2
            while t < 4 {
                let s = Demo.voice(local: t, target: target, global: t + 3)
                XCTAssertLessThan(abs(s.midi! - target) * 100, 20, "\(target)@\(t)")
                XCTAssertTrue(s.level > 0 && s.level <= 1)
                t += 0.05
            }
        }
        XCTAssertEqual(Demo.voice(local: 1, target: 60, global: 5), Demo.voice(local: 1, target: 60, global: 5))
    }

    func testOvershootAndHoldCompletion() {
        let peak = (0..<20).map { Demo.voice(local: Demo.breath + 0.1 + Double($0) * 0.02, target: 60).midi! }.max()!
        XCTAssertGreaterThan(peak, 60.6)
        let steady = (0..<20).map { Demo.voice(local: Demo.breath + 0.1 + Double($0) * 0.02, target: 61).midi! }.max()!
        XCTAssertLessThan(steady, 61.5)
        for target in [57, 60, 62, 63] {
            var hold = 0.0, t = 0.0
            var done: Double?
            while t < 5 && done == nil {
                hold = Quest.advanceHold(hold, midi: Demo.voice(local: t, target: Double(target), global: t).midi, target: target, dt: 0.07)
                if Quest.holdComplete(hold) { done = t }
                t += 0.07
            }
            XCTAssertNotNil(done); XCTAssertLessThan(done ?? 9, 3)
        }
    }

    func testMelodyCycles() {
        XCTAssertEqual(Demo.melody(at: 0).target, 60)
        XCTAssertEqual(Demo.melody(at: 0).local, 0)
        let second = Demo.melody(at: Demo.melodyNoteSeconds + 0.1)
        XCTAssertEqual(second.target, 62)
        XCTAssertLessThan(abs(second.local - 0.1), 1e-9)
        XCTAssertEqual(Demo.melody(at: -4).target, 60)
        XCTAssertEqual(Demo.melody(at: .nan).target, 60)
        var notes = Set<Int>(), voiced = 0, total = 0
        var t = 0.0
        while t < 40 {
            let s = Demo.freeSample(at: t); total += 1
            if let m = s.midi { voiced += 1; notes.insert(Int(m.rounded())); XCTAssertTrue(m > 50 && m < 76) }
            t += 0.07
        }
        XCTAssertGreaterThanOrEqual(notes.count, 5)
        XCTAssertGreaterThan(Double(voiced) / Double(total), 0.6)
        XCTAssertLessThan(voiced, total)
    }
}
