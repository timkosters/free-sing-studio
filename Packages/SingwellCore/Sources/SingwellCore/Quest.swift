import Foundation

/// Pitch Quest: one piano target at a time, matched and held steadily to advance.
public enum Quest {
    public static let lowest = 36 // C2
    public static let highest = 84 // C6
    public static let holdSeconds = 1.0
    public static let toleranceCents = 50.0
    public static let counts = [5, 8, 12, 16]

    /// Clamp and order a chosen comfortable range; guarantees at least two semitones.
    public static func normalizeRange(_ low: Double, _ high: Double) -> (low: Int, high: Int) {
        func clamp(_ n: Double) -> Int {
            min(highest, max(lowest, n.isFinite ? Int(n.rounded()) : 60))
        }
        var a = clamp(low), b = clamp(high)
        if a > b { swap(&a, &b) }
        if b - a < 2 {
            if b + (2 - (b - a)) <= highest { b = a + 2 } else { a = b - 2 }
        }
        return (a, b)
    }

    /// mulberry32, so target sequences are reproducible in tests.
    struct SeededRandom {
        private var a: UInt32
        init(seed: Double) {
            let truncated = UInt32(truncatingIfNeeded: Int64(seed.isFinite ? seed.rounded(.down) : 1))
            a = truncated == 0 ? 1 : truncated
        }
        mutating func next() -> Double {
            a = a &+ 0x6d2b_79f5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// Targets inside [low, high] starting near the middle, never repeating a note
    /// twice in a row and never leaping more than five semitones.
    public static func makeTargets(low: Double, high: Double, count: Int, seed: Double = 1) -> [Int] {
        let (a, b) = normalizeRange(low, high)
        let n = max(1, min(40, count))
        var random = SeededRandom(seed: seed)
        var targets: [Int] = []
        var current = Int((Double(a + b) / 2).rounded())
        for i in 0..<n {
            if i > 0 {
                let lo = max(a, current - 5), hi = min(b, current + 5)
                let options = (lo...hi).filter { $0 != current }
                if !options.isEmpty {
                    current = options[min(options.count - 1, Int(random.next() * Double(options.count)))]
                }
            }
            targets.append(current)
        }
        return targets
    }

    public static func isOnTarget(_ midi: Double?, target: Int, tolerance: Double = toleranceCents) -> Bool {
        guard let midi else { return false }
        return abs(midi - Double(target)) * 100 <= tolerance
    }

    /// Matching samples fill the hold; unmatched samples drain it twice as fast instead of resetting.
    public static func advanceHold(_ hold: Double, midi: Double?, target: Int, dt: Double, tolerance: Double = toleranceCents) -> Double {
        let step = min(0.25, max(0, dt))
        return isOnTarget(midi, target: target, tolerance: tolerance)
            ? min(holdSeconds, hold + step)
            : max(0, hold - step * 2)
    }

    public static func holdComplete(_ hold: Double) -> Bool { hold >= holdSeconds - 1e-9 }

    public enum Outcome: String, Codable, Sendable { case hit, skip }

    public struct Run: Equatable, Sendable {
        public var targets: [Int]
        public var index = 0
        public var hold = 0.0
        public var matched: [Int] = []
        public var skipped = 0
        public var outcomes: [Outcome] = []
        public var times: [Double] = []

        public init(targets: [Int]) { self.targets = targets }

        public var finished: Bool { index >= targets.count }
        public var current: Int? { finished ? nil : targets[index] }

        /// Apply one pitch sample. Returns whether a target was just matched.
        @discardableResult
        public mutating func sample(midi: Double?, dt: Double, elapsedOnTarget: Double) -> Bool {
            guard let target = current else { return false }
            let next = Quest.advanceHold(hold, midi: midi, target: target, dt: dt)
            if !Quest.holdComplete(next) { hold = next; return false }
            hold = 0
            index += 1
            matched.append(target)
            outcomes.append(.hit)
            times.append(max(Quest.holdSeconds, elapsedOnTarget))
            return true
        }

        public mutating func skip() {
            guard !finished else { return }
            hold = 0
            index += 1
            skipped += 1
            outcomes.append(.skip)
        }

        public var summary: Summary {
            Summary(matched: matched.count, total: targets.count, skipped: skipped,
                    averageSeconds: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count),
                    low: matched.min(), high: matched.max())
        }
    }

    public struct Summary: Equatable, Sendable, Codable {
        public var matched: Int
        public var total: Int
        public var skipped: Int
        public var averageSeconds: Double?
        public var low: Int?
        public var high: Int?
        public init(matched: Int, total: Int, skipped: Int, averageSeconds: Double?, low: Int?, high: Int?) {
            self.matched = matched; self.total = total; self.skipped = skipped
            self.averageSeconds = averageSeconds; self.low = low; self.high = high
        }
        public var complete: Bool { total > 0 && matched == total }
    }

    /// Rough label for a completed run without ranking the singer.
    public static func verdict(_ s: Summary) -> String {
        if s.total == 0 { return "Nothing to report yet." }
        if s.matched == s.total { return "Every target matched." }
        if s.matched == 0 { return "No targets matched this time. That happens." }
        return "\(s.matched) of \(s.total) targets matched."
    }
}
