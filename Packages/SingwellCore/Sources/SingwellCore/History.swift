import Foundation

/// Session range map and local practice history. Only sustained notes count.
public enum History {
    /// A note must be held this long (seconds) before it counts as observed.
    public static let sustainSeconds = 0.5

    public struct Sustain: Equatable, Sendable {
        public var candidate: Int?
        public var since = 0.0
        public var lastSample = 0.0
        public var low: Int?
        public var high: Int?
        public init() {}

        /// Feed one detected pitch. Silence or a different note restarts the candidate clock.
        public func tracking(midi: Double?, now: Double) -> Sustain {
            guard let midi, midi.isFinite else {
                if candidate == nil { return self }
                var s = self; s.candidate = nil; return s
            }
            let note = Int(midi.rounded())
            var s = self
            if note != candidate || now - lastSample > 1 || now < lastSample {
                s.candidate = note; s.since = now; s.lastSample = now
                return s
            }
            if now - since < History.sustainSeconds { s.lastSample = now; return s }
            s.low = low.map { min($0, note) } ?? note
            s.high = high.map { max($0, note) } ?? note
            s.lastSample = now
            return s
        }
    }

    public struct QuestBests: Equatable, Sendable, Codable {
        public var runs = 0
        public var mostMatched = 0
        public var quickestAverage: Double?
        public var widestLow: Int?
        public var widestHigh: Int?
        public init() {}
    }

    public struct Record: Equatable, Sendable, Codable {
        public var version = 1
        public var seconds = 0.0
        public var sessions = 0
        public var low: Int?
        public var high: Int?
        public var quest = QuestBests()
        public var updated = 0.0
        public init() {}

        public func addingPractice(seconds add: Double, now: Double) -> Record {
            let a = add.isFinite ? max(0, add) : 0
            if a == 0 { return self }
            var r = self; r.seconds += a; r.updated = now; return r
        }

        public func recordingSession(now: Double) -> Record {
            var r = self; r.sessions += 1; r.updated = now; return r
        }

        public func recordingRange(low l: Int?, high h: Int?, now: Double) -> Record {
            guard let l, let h else { return self }
            let nextLow = low.map { min($0, l) } ?? l
            let nextHigh = high.map { max($0, h) } ?? h
            if nextLow == low && nextHigh == high { return self }
            var r = self; r.low = nextLow; r.high = nextHigh; r.updated = now; return r
        }

        public func recordingQuest(_ result: Quest.Summary, now: Double) -> Record {
            var r = self
            let q = quest
            let complete = result.total > 0 && result.matched == result.total
            var quickest = q.quickestAverage
            if complete, let avg = result.averageSeconds {
                quickest = q.quickestAverage.map { min($0, avg) } ?? avg
            }
            func span(_ lo: Int?, _ hi: Int?) -> Int { (lo != nil && hi != nil) ? hi! - lo! : -1 }
            let wider = span(result.low, result.high) > span(q.widestLow, q.widestHigh)
            r.updated = now
            r.quest.runs = q.runs + 1
            r.quest.mostMatched = max(q.mostMatched, result.matched)
            r.quest.quickestAverage = quickest
            r.quest.widestLow = wider ? result.low : q.widestLow
            r.quest.widestHigh = wider ? result.high : q.widestHigh
            return r
        }
    }

    public static func serialize(_ r: Record) -> Data {
        (try? JSONEncoder().encode(r)) ?? Data()
    }

    /// Parse stored JSON defensively. Anything malformed falls back to a clean slate.
    public static func parse(_ data: Data?) -> Record {
        guard let data, !data.isEmpty,
              let raw = try? JSONSerialization.jsonObject(with: data),
              let d = raw as? [String: Any] else { return Record() }
        if let v = d["version"], numeric(v) != 1 { return Record() }
        let q = d["quest"] as? [String: Any] ?? [:]
        let low = validNote(d["low"]), high = validNote(d["high"])
        let questLow = validNote(q["widestLow"]), questHigh = validNote(q["widestHigh"])
        let quickest = numeric(q["quickestAverage"])
        var r = Record()
        r.seconds = nonNegative(d["seconds"])
        r.sessions = Int(nonNegative(d["sessions"]).rounded(.down))
        if let low, let high { r.low = min(low, high); r.high = max(low, high) } else { r.low = low ?? high; r.high = high ?? low }
        r.quest.runs = Int(nonNegative(q["runs"]).rounded(.down))
        r.quest.mostMatched = Int(nonNegative(q["mostMatched"]).rounded(.down))
        r.quest.quickestAverage = (quickest ?? 0) >= 1 ? quickest : nil
        if let questLow, let questHigh { r.quest.widestLow = min(questLow, questHigh); r.quest.widestHigh = max(questLow, questHigh) }
        r.updated = nonNegative(d["updated"])
        return r
    }

    /// JSON booleans arrive as NSNumber too; only genuine numbers count, like `typeof v === 'number'`.
    static func isBoolean(_ n: NSNumber) -> Bool { String(cString: n.objCType) == "c" || String(cString: n.objCType) == "B" }
    static func numeric(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, !isBoolean(n) { let d = n.doubleValue; return d.isFinite ? d : nil }
        return nil
    }
    static func boolean(_ v: Any?) -> Bool {
        if let b = v as? Bool, let n = v as? NSNumber, isBoolean(n) { return b }
        return false
    }
    static func nonNegative(_ v: Any?) -> Double { max(0, numeric(v) ?? 0) }
    static func validNote(_ v: Any?) -> Int? {
        guard let n = numeric(v), n >= 24, n <= 96 else { return nil }
        return Int(n.rounded())
    }
}
