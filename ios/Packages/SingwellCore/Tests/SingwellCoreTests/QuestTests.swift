import XCTest
@testable import SingwellCore

final class QuestTests: XCTestCase {
    func testRangeNormalisation() {
        XCTAssertTrue(Quest.normalizeRange(48, 60) == (48, 60))
        XCTAssertTrue(Quest.normalizeRange(60, 48) == (48, 60))
        XCTAssertTrue(Quest.normalizeRange(0, 200) == (Quest.lowest, Quest.highest))
        XCTAssertTrue(Quest.normalizeRange(55, 55) == (55, 57))
        XCTAssertTrue(Quest.normalizeRange(84, 84) == (82, 84))
        XCTAssertTrue(Quest.normalizeRange(.nan, 62) == (60, 62))
    }

    func testTargetsStayInRangeWithGentleLeaps() {
        for seed in [1.0, 7, 42, 999, 1_758_000_000_000] {
            let targets = Quest.makeTargets(low: 50, high: 62, count: 16, seed: seed)
            XCTAssertEqual(targets.count, 16)
            XCTAssertEqual(targets[0], 56)
            for i in targets.indices {
                XCTAssertTrue(targets[i] >= 50 && targets[i] <= 62)
                if i > 0 {
                    XCTAssertNotEqual(targets[i], targets[i - 1])
                    XCTAssertLessThanOrEqual(abs(targets[i] - targets[i - 1]), 5)
                }
            }
        }
        XCTAssertEqual(Quest.makeTargets(low: 60, high: 62, count: 5, seed: 3), Quest.makeTargets(low: 60, high: 62, count: 5, seed: 3))
        XCTAssertNotEqual(Quest.makeTargets(low: 40, high: 70, count: 12, seed: 1), Quest.makeTargets(low: 40, high: 70, count: 12, seed: 2))
        XCTAssertEqual(Quest.makeTargets(low: 60, high: 70, count: 0).count, 1)
        XCTAssertEqual(Quest.makeTargets(low: 60, high: 70, count: 1000).count, 40)
    }

    func testToleranceAndHold() {
        XCTAssertTrue(Quest.isOnTarget(60.49, target: 60))
        XCTAssertTrue(Quest.isOnTarget(59.51, target: 60))
        XCTAssertFalse(Quest.isOnTarget(60.6, target: 60))
        XCTAssertFalse(Quest.isOnTarget(nil, target: 60))
        XCTAssertTrue(Quest.isOnTarget(60.8, target: 60, tolerance: 100))
        var hold = 0.0, ticks = 0
        while !Quest.holdComplete(hold) { hold = Quest.advanceHold(hold, midi: 60.1, target: 60, dt: 0.07); ticks += 1 }
        XCTAssertLessThan(abs(Double(ticks) * 0.07 - Quest.holdSeconds), 0.1)
        let drained = Quest.advanceHold(0.6, midi: nil, target: 60, dt: 0.07)
        XCTAssertTrue(drained < 0.6 && drained > 0.4)
        XCTAssertEqual(Quest.advanceHold(0.05, midi: 65, target: 60, dt: 0.07), 0)
        XCTAssertEqual(Quest.advanceHold(Quest.holdSeconds, midi: 60, target: 60, dt: 5), Quest.holdSeconds)
        XCTAssertLessThanOrEqual(Quest.advanceHold(0, midi: 60, target: 60, dt: 3), 0.25)
        XCTAssertEqual(Quest.advanceHold(0.5, midi: 60, target: 60, dt: -1), 0.5)
    }

    func testRunAdvancesAndSkips() {
        var run = Quest.Run(targets: [60, 62, 64])
        XCTAssertEqual(run.current, 60)
        var advanced = false, elapsed = 0.0
        while !advanced { elapsed += 0.07; advanced = run.sample(midi: 60, dt: 0.07, elapsedOnTarget: elapsed) }
        XCTAssertEqual(run.index, 1)
        XCTAssertEqual(run.matched, [60])
        XCTAssertEqual(run.times.count, 1)
        XCTAssertGreaterThanOrEqual(run.times[0], Quest.holdSeconds)
        XCTAssertFalse(run.sample(midi: 70, dt: 0.07, elapsedOnTarget: 0.07))
        XCTAssertEqual(run.index, 1)
        run.skip()
        XCTAssertEqual(run.index, 2); XCTAssertEqual(run.skipped, 1); XCTAssertEqual(run.current, 64)
        for i in 0..<20 { run.sample(midi: 64, dt: 0.07, elapsedOnTarget: Double(i) * 0.07) }
        XCTAssertTrue(run.finished)
        XCTAssertEqual(run.outcomes, [.hit, .skip, .hit])
        XCTAssertNil(run.current)
        let frozen = run
        run.sample(midi: 64, dt: 0.07, elapsedOnTarget: 1); run.skip()
        XCTAssertEqual(run, frozen)
        let s = run.summary
        XCTAssertEqual(s.matched, 2); XCTAssertEqual(s.total, 3); XCTAssertEqual(s.skipped, 1)
        XCTAssertEqual(s.low, 60); XCTAssertEqual(s.high, 64)
        XCTAssertGreaterThanOrEqual(s.averageSeconds ?? 0, Quest.holdSeconds)
        XCTAssertEqual(Quest.verdict(s), "2 of 3 targets matched.")
        var full = s; full.matched = 3
        XCTAssertEqual(Quest.verdict(full), "Every target matched.")
        XCTAssertEqual(Quest.verdict(Quest.Run(targets: []).summary), "Nothing to report yet.")
        var none = Quest.Run(targets: [60]); none.skip()
        XCTAssertNil(none.summary.low); XCTAssertNil(none.summary.averageSeconds)
        XCTAssertTrue(Quest.verdict(none.summary).contains("No targets matched"))
    }
}
