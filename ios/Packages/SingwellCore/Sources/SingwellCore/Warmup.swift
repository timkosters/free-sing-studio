import Foundation

public enum Warmup {
    public enum Drill: String, CaseIterable, Codable, Sendable, Identifiable {
        case arpeggio
        case fiveNote = "five-note"
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .arpeggio: return "Octave arpeggio"
            case .fiveNote: return "Five-note scale"
            }
        }
        var pattern: [Int] {
            switch self {
            case .arpeggio: return [0, 4, 7, 12, 7, 4, 0]
            case .fiveNote: return [0, 2, 4, 5, 7, 5, 4, 2, 0]
            }
        }
    }

    public enum Phase: String, Sendable { case listen, count, sing, rest }

    public struct Beat: Equatable, Sendable {
        public var time: Double
        public var midi: Int?
        public var root: Int
        public var round: Int
        public var label: String
        public var accent: Bool
        public var phase: Phase
        public var noteIndex: Int
        public var onset: Bool
    }

    public enum SettingsError: Error { case invalid }

    public static let rootRange = 36...72
    public static let stepsRange = 0...12
    public static let bpmRange = 50.0...140.0

    /// Piano demonstration → count-in → sung pass → breathe → up a semitone.
    public static func plan(drill: Drill, root: Int, steps: Int, bpm: Double) throws -> [Beat] {
        guard rootRange.contains(root), stepsRange.contains(steps), bpm.isFinite, bpmRange.contains(bpm) else {
            throw SettingsError.invalid
        }
        let pattern = drill.pattern
        var beats: [Beat] = []
        let duration = 60 / bpm
        func add(_ midi: Int?, _ r: Int, _ round: Int, _ label: String, _ accent: Bool, _ phase: Phase, _ noteIndex: Int = -1, _ onset: Bool = true) {
            beats.append(Beat(time: Double(beats.count) * duration, midi: midi, root: r, round: round, label: label, accent: accent, phase: phase, noteIndex: noteIndex, onset: onset))
        }
        for n in 0..<4 { add(nil, root, 1, "Listen in \(4 - n)", n == 0, .count) }
        for s in 0...steps {
            for phase in [Phase.listen, Phase.sing] {
                if phase == .sing {
                    for n in 0..<4 { add(nil, root + s, s + 1, "Your turn in \(4 - n)", n == 0, .count) }
                }
                for (i, offset) in pattern.enumerated() {
                    for hold in 0..<2 {
                        add(root + s + offset, root + s, s + 1,
                            phase == .listen ? "Listen to the piano" : "Your turn · sing",
                            hold == 0, phase, i, hold == 0)
                    }
                }
            }
            for n in 0..<4 { add(nil, root + s, s + 1, "Breathe · \(4 - n)", n == 0, .rest) }
        }
        return beats
    }

    public struct NoteScore: Equatable, Sendable {
        public var total = 0
        public var voiced = 0
        public var hits = 0
        public var cents: [Double] = []
        public init() {}
    }

    public static func score(_ previous: NoteScore?, midi: Double?, target: Int) -> NoteScore {
        var s = previous ?? NoteScore()
        let diff: Double? = midi.map { ($0 - Double(target)) * 100 }
        s.total += 1
        if let diff {
            s.voiced += 1
            if abs(diff) <= 50 { s.hits += 1 }
            s.cents.append(diff)
        }
        return s
    }

    public enum Verdict: String, Sendable {
        case hit = "Hit", low = "Low", high = "High", steady = "Keep steady", none = "No clear pitch"
    }

    public static func verdict(_ s: NoteScore?) -> Verdict {
        guard let s, s.voiced >= 3 else { return .none }
        if s.hits >= 3 && Double(s.hits) / Double(s.total) >= 0.5 { return .hit }
        let sorted = s.cents.sorted()
        let median = sorted[sorted.count / 2]
        return median < -50 ? .low : median > 50 ? .high : .steady
    }
}
