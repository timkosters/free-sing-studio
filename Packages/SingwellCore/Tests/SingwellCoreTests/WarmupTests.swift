import XCTest
@testable import SingwellCore

final class WarmupTests: XCTestCase {
    func testArpeggioMovesUpAfterBreath() throws {
        let b = try Warmup.plan(drill: .arpeggio, root: 48, steps: 2, bpm: 60)
        XCTAssertEqual(b.count, 4 + 3 * 36)
        XCTAssertEqual(b[0..<4].map { $0.midi }, [nil, nil, nil, nil])
        XCTAssertEqual(b.filter { $0.round == 1 && $0.phase == .listen && $0.onset }.map { $0.midi }, [48, 52, 55, 60, 55, 52, 48])
        XCTAssertTrue(b[18..<22].allSatisfy { $0.midi == nil && $0.phase == .count })
        XCTAssertEqual(b[4..<18].map { $0.midi }, b[22..<36].map { $0.midi })
        XCTAssertTrue(b[22..<36].allSatisfy { $0.phase == .sing })
        XCTAssertTrue(b[36..<40].allSatisfy { $0.phase == .rest })
        XCTAssertEqual(b[40].midi, 49)
        XCTAssertEqual(b[40].time, 40)
        XCTAssertEqual(b.last?.round, 3)
    }

    func testFiveNoteAndLimits() throws {
        XCTAssertEqual(try Warmup.plan(drill: .fiveNote, root: 48, steps: 0, bpm: 120).filter { $0.phase == .listen && $0.onset }.map { $0.midi }, [48, 50, 52, 53, 55, 53, 52, 50, 48])
        let all = try Warmup.plan(drill: .arpeggio, root: 72, steps: 12, bpm: 140)
        XCTAssertEqual(all.compactMap { $0.midi }.max(), 96)
        XCTAssertThrowsError(try Warmup.plan(drill: .arpeggio, root: 10, steps: 2, bpm: 80))
        XCTAssertThrowsError(try Warmup.plan(drill: .arpeggio, root: 48, steps: 99, bpm: 80))
        XCTAssertThrowsError(try Warmup.plan(drill: .arpeggio, root: 48, steps: 2, bpm: .nan))
        XCTAssertEqual(Formatting.clock(125), "2:05")
    }

    func testScoring() {
        var s: Warmup.NoteScore?
        for _ in 0..<10 { s = Warmup.score(s, midi: 60.2, target: 60) }
        XCTAssertEqual(Warmup.verdict(s), .hit)
        s = nil
        for _ in 0..<10 { s = Warmup.score(s, midi: nil, target: 60) }
        XCTAssertEqual(Warmup.verdict(s), .none)
        for (m, v) in [(59.0, Warmup.Verdict.low), (61.0, .high)] {
            s = nil
            for _ in 0..<10 { s = Warmup.score(s, midi: m, target: 60) }
            XCTAssertEqual(Warmup.verdict(s), v)
        }
        s = nil
        for i in 0..<10 { s = Warmup.score(s, midi: i < 3 ? 60 : nil, target: 60) }
        XCTAssertEqual(Warmup.verdict(s), .steady)
    }
}
