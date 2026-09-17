import Foundation

/// What the routine knows about one particular voice. Lives in the singer's own account
/// (Supabase `singer_profile`) and is folded into step text at render time, so the shipped
/// routine stays generic and the practice gets specific.
public struct Profile: Equatable, Sendable, Codable {
    public var low: Int?
    public var high: Int?
    public var breakLow: Int?
    public var breakHigh: Int?
    public var songs: [String] = []
    public var hardLine: String?
    public init() {}

    public var isEmpty: Bool {
        low == nil && high == nil && breakLow == nil && breakHigh == nil && songs.isEmpty && hardLine == nil
    }

    static let noteRange = 24...96

    static func note(_ v: Int?) -> Int? { v.flatMap { noteRange.contains($0) ? $0 : nil } }
    static func text(_ v: String?, max: Int) -> String? {
        guard let v else { return nil }
        let t = String(v.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
        return t.isEmpty ? nil : t
    }
    static func ordered(_ a: Int?, _ b: Int?) -> (Int?, Int?) {
        if let a, let b { return (min(a, b), max(a, b)) }
        return (a, b)
    }

    /// One row of the `singer_profile` table.
    public struct Row: Codable, Equatable, Sendable {
        public var low_note: Int?
        public var high_note: Int?
        public var break_low: Int?
        public var break_high: Int?
        public var songs: [String]
        public var hard_line: String?
        public init(low_note: Int?, high_note: Int?, break_low: Int?, break_high: Int?, songs: [String], hard_line: String?) {
            self.low_note = low_note; self.high_note = high_note; self.break_low = break_low
            self.break_high = break_high; self.songs = songs; self.hard_line = hard_line
        }
    }

    /// Build a profile from a server row, range-checking every field.
    public init(row: Row) {
        (low, high) = Profile.ordered(Profile.note(row.low_note), Profile.note(row.high_note))
        (breakLow, breakHigh) = Profile.ordered(Profile.note(row.break_low), Profile.note(row.break_high))
        songs = Array(row.songs.compactMap { Profile.text($0, max: 80) }.prefix(12))
        hardLine = Profile.text(row.hard_line, max: 200)
    }

    public var row: Row {
        Row(low_note: low, high_note: high, break_low: breakLow, break_high: breakHigh, songs: songs, hard_line: hardLine)
    }

    static func orList(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items.last!
    }

    /// Fold what we know about this voice into one step's wording. Only lines a profile can
    /// genuinely improve are replaced, and only when the relevant field is filled.
    public func personalize(_ step: Daily.Step) -> Daily.Step {
        var s = step
        switch step.id {
        case "bridge":
            guard let breakLow, let breakHigh else { return step }
            let from = Pitch.noteName(Double(breakLow)), to = Pitch.noteName(Double(breakHigh))
            let below = Pitch.noteName(Double(max(Profile.noteRange.lowerBound, breakLow - 3)))
            s.cue = "Slide from \(below) up through \(from)–\(to) and into head voice. Glide. Never jump."
            s.detail = ["Your break sits around \(from) to \(to). Start below it, in chest.",
                        "Slide up through it without stopping, and keep going into head voice.",
                        "Mouth stays open. Do not brace or anticipate the note before it arrives.",
                        "If it cracks, go slower and quieter, not louder. Then slide back down."]
        case "hard-line":
            guard let hardLine else { return step }
            s.cue = "\"\(hardLine)\" On loop."
            s.detail = ["This is the line you marked as the one that keeps going wrong.",
                        "Take it quieter and slower than feels right. Louder never fixes a break.",
                        "Head neutral. Do not crane upward for the high note; move side to side.",
                        "Lead the sound forward. Do not land heavily on each syllable."]
        case "noi":
            guard let low else { return step }
            let lowest = Pitch.noteName(Double(low))
            let reach = Pitch.noteName(Double(max(Profile.noteRange.lowerBound, low - 1)))
            s.detail = ["Sing \"noi\" on a descending run into your low range.",
                        "Keep the sound at the front of the face, not in the throat.",
                        "A gentle yawn shape before you start opens the space.",
                        "Your lowest tracked note is \(lowest). Go for \(reach) today."]
        case "song":
            guard !songs.isEmpty else { return step }
            s.detail = ["\(Profile.orList(songs)). Pick one.",
                        "Take one or two lines. Belly breath before each phrase.",
                        "Repeat the section rather than running the whole thing.",
                        "Record a take. In a few weeks you get to compare honestly."]
        default:
            return step
        }
        return s
    }

    public func personalize(_ steps: [Daily.Step]) -> [Daily.Step] {
        isEmpty ? steps : steps.map { personalize($0) }
    }
}
