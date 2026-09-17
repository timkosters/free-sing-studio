import Foundation

/// The daily practice routine: a fixed, ordered set of steps on a clock, plus the
/// streak log. Everything here is pure so the routine and streak maths can be tested.
public enum Daily {
    /// How a step uses the audio engine.
    public enum Engine: String, Codable, Sendable {
        /// Instruction and timer only. No microphone requested.
        case none
        /// Live pitch display with the piano roll.
        case mic
        /// Live pitch plus a steadiness meter over one held note.
        case hold
        /// A breathing pacer with an expand/hold/release ring.
        case breath
    }

    public struct Step: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// One line telling you what to do right now.
        public var cue: String
        /// Short, concrete lines shown while the step runs.
        public var detail: [String]
        /// Why this step is in the routine, shown small.
        public var why: String
        public var seconds: Double
        public var engine: Engine
        /// For hold steps: the suggested note to sit on, as MIDI.
        public var hold: Int? = nil
        /// For breath steps: inhale / hold / exhale seconds per cycle.
        public var breath: (Double, Double, Double)? = nil

        public static func == (a: Step, b: Step) -> Bool { a.id == b.id && a.seconds == b.seconds }

        func lasting(_ seconds: Double) -> Step { var s = self; s.seconds = seconds; return s }
        public var needsMic: Bool { engine == .mic || engine == .hold }
    }

    public enum RoutineID: String, CaseIterable, Codable, Sendable, Identifiable {
        case quick, full, bridge
        public var id: String { rawValue }
    }

    public struct Routine: Equatable, Sendable, Identifiable {
        public var id: RoutineID
        public var label: String
        public var blurb: String
        public var steps: [Step]
        public var seconds: Double { steps.reduce(0) { $0 + $1.seconds } }
        public var lengthLabel: String { "\(Int((seconds / 60).rounded())) min" }
    }

    // MARK: Step library (kept word-for-word in sync with the web app's lib/daily.ts)

    static let wake = Step(id: "wake", title: "Wake the body up",
        cue: "Loosen the jaw, face and shoulders before any sound.",
        detail: ["Massage the jaw hinge with your fingertips, then let the jaw hang open.",
                 "Roll the shoulders back and drop them. Knees loose, not locked.",
                 "Smile wide, then pucker. Repeat. Tongue side to side.",
                 "Chin level. Feet apart, weight even, chest high."],
        why: "Tension in the jaw and shoulders shows up in the sound",
        seconds: 90, engine: .none)

    static let belly = Step(id: "belly", title: "Belly breath",
        cue: "Sharp inhale into the stomach. Chest stays still.",
        detail: ["Hand on the belly, hand on the chest. Only the lower hand moves.",
                 "Sharp inhale, hold the expansion, then count out loud to 15.",
                 "Take a small top-up breath between each number.",
                 "Neck and throat stay free the whole time."],
        why: "Breathing into the chest is what tightens the throat",
        seconds: 150, engine: .breath, breath: (3, 2, 9))

    static let ladder = Step(id: "ladder", title: "Breath control ladder",
        cue: "Thin, even stream. Imagine breathing out through a straw.",
        detail: ["Hiss on \"sss\" for a slow count of 10. Then \"fff\". Then voiced \"zzz\".",
                 "Then the ratios: in 3 out 9, in 4 out 12, in 5 out 15, in 6 out 18.",
                 "The stream stays even. No collapse at the end.",
                 "Finish on a humming glide, low to high and back."],
        why: "Steady air is what keeps a long phrase supported",
        seconds: 150, engine: .none)

    static let twisters = Step(id: "twisters", title: "Diction",
        cue: "Straw between the teeth. Over-articulate, then drop the straw.",
        detail: ["Peter Piper picked a peck of pickled peppers.",
                 "Betty Botter bought some butter, but she said the butter's bitter.",
                 "How much wood would a woodchuck chuck.",
                 "Last round with nothing in your mouth: fast and clear."],
        why: "Consonants are the first thing a microphone loses",
        seconds: 90, engine: .none)

    static let siren = Step(id: "siren", title: "Lip trill siren",
        cue: "Trill low to high to low. Let the break pass through untouched.",
        detail: ["Lips loose and buzzing. If they stall, press the cheeks in lightly.",
                 "Slide up through your whole range and back down. Four passes.",
                 "Do not stop or push at the break. Glide straight through it.",
                 "Watch the trail: you want one smooth line, not a step."],
        why: "Warms the voice and crosses the break without strain",
        seconds: 90, engine: .mic)

    static let goo = Step(id: "goo", title: "\"Goo\": close the cords",
        cue: "The main event. \"Goo\" on a descending five-note run, up a semitone each time.",
        detail: ["The hard \"g\" snaps the cords together. That is the point.",
                 "Sing goo-oo-oo-oo-oo down 5-4-3-2-1, then start a semitone higher.",
                 "Aim for a clean, buzzy tone. No air leaking around the note.",
                 "If it turns breathy, come back down and restart lower."],
        why: "A breathy tone usually means the cords are not quite meeting",
        seconds: 180, engine: .mic)

    static let oo = Step(id: "oo", title: "Sustained \"oo\"",
        cue: "One note. Hold it dead steady for as long as the breath lasts.",
        detail: ["Pick a comfortable note in the middle. Sing \"oo\" and hold.",
                 "No wobble, no fade, no breath escaping. Straight line.",
                 "Rest, then repeat a tone higher.",
                 "The meter shows how steady you actually are."],
        why: "A held note is where wobble and escaping air become obvious",
        seconds: 120, engine: .hold, hold: 60)

    static let bridge = Step(id: "bridge", title: "The bridge: chest into head",
        cue: "Slide up through the place your voice wants to flip. Glide. Never jump.",
        detail: ["Find your break first: siren slowly until the tone wants to change gear.",
                 "Start below it in chest, slide up through it, keep going into head voice.",
                 "Mouth stays open. Do not brace or anticipate the note before it arrives.",
                 "If it cracks, go slower and quieter, not louder. Then slide back down."],
        why: "The gap between chest and head voice is the slowest thing to build",
        seconds: 180, engine: .mic)

    static let hardLine = Step(id: "hard-line", title: "Your hardest line",
        cue: "One phrase. The one that keeps going wrong. On loop.",
        detail: ["Pick the bar that defeats you, usually the one sitting on your break.",
                 "Take it quieter and slower than feels right. Louder never fixes a break.",
                 "Head neutral. Do not crane upward for the high note; move side to side.",
                 "Lead the sound forward. Do not land heavily on each syllable."],
        why: "One hard bar, repeated, beats another run at the whole song",
        seconds: 180, engine: .mic)

    static let noi = Step(id: "noi", title: "Low notes forward: \"noi\"",
        cue: "Down into your low range. Bring it forward. Do not swallow it.",
        detail: ["Sing \"noi\" on a descending run into your low range.",
                 "Keep the sound at the front of the face, not in the throat.",
                 "A gentle yawn shape before you start opens the space.",
                 "Go one semitone lower than you think you have. It is usually there."],
        why: "Low notes get swallowed long before they actually run out",
        seconds: 90, engine: .mic)

    static let song = Step(id: "song", title: "Song of the day",
        cue: "One section. Not the whole song.",
        detail: ["Whatever you are working on. One song, not a playlist.",
                 "Take one or two lines. Belly breath before each phrase.",
                 "Repeat the section rather than running the whole thing.",
                 "Record a take. In a few weeks you get to compare honestly."],
        why: "Sections build a song; run-throughs rehearse the mistakes",
        seconds: 240, engine: .mic)

    // MARK: Routines

    public static let routines: [Routine] = [
        Routine(id: .quick, label: "Quick", blurb: "The irreducible ten minutes. Breath, cords, bridge.",
                steps: [wake.lasting(60), belly.lasting(120), siren.lasting(60), goo.lasting(150), bridge.lasting(120), song.lasting(120)]),
        Routine(id: .full, label: "Full", blurb: "Everything, in the order a lesson runs it.",
                steps: [wake.lasting(60), belly.lasting(120), ladder.lasting(120), twisters.lasting(60), siren.lasting(60),
                        goo.lasting(150), oo.lasting(90), bridge.lasting(150), hardLine.lasting(120), noi.lasting(90), song.lasting(150)]),
        Routine(id: .bridge, label: "Bridge focus", blurb: "All in on the chest-to-head transition.",
                steps: [wake.lasting(60), belly.lasting(90), siren.lasting(60), goo.lasting(120), bridge.lasting(180),
                        hardLine.lasting(150), oo.lasting(90), bridge.lasting(120)]),
    ]

    public static func routine(_ id: RoutineID) -> Routine {
        routines.first { $0.id == id } ?? routines[0]
    }

    /// Steps can repeat inside a routine, so identity needs the position as well.
    public static func stepKey(_ step: Step, index: Int) -> String { "\(index):\(step.id)" }

    // MARK: Daily log

    public struct Day: Equatable, Sendable, Codable {
        public var seconds = 0.0
        public var steps = 0
        public var completed = false
        public init() {}
        public var practised: Bool { seconds > 0 || steps > 0 }
    }

    public struct Log: Equatable, Sendable, Codable {
        public var version = 1
        public var days: [String: Day] = [:]
        public var updated = 0.0
        public init() {}

        public func loggingStep(seconds: Double, key: String, now: Double) -> Log {
            var l = self
            var day = days[key] ?? Day()
            day.seconds += seconds.isFinite && seconds > 0 ? seconds : 0
            day.steps += 1
            l.days[key] = day
            l.updated = now
            return l
        }

        public func loggingComplete(key: String, now: Double) -> Log {
            var l = self
            var day = days[key] ?? Day()
            day.completed = true
            l.days[key] = day
            l.updated = now
            return l
        }

        func practised(_ key: String) -> Bool { days[key]?.practised ?? false }

        /// Consecutive practised days ending today, or ending yesterday if today is still untouched.
        public func streak(today: String = Daily.dayKey()) -> Int {
            var cursor = practised(today) ? today : Daily.shiftDay(today, -1)
            if !practised(cursor) { return 0 }
            var count = 0
            while practised(cursor) && count < 4000 {
                count += 1
                cursor = Daily.shiftDay(cursor, -1)
            }
            return count
        }

        /// Longest run of consecutive practised days ever recorded.
        public var bestStreak: Int {
            let keys = days.keys.filter { practised($0) }.sorted()
            var best = 0, run = 0, previous = ""
            for key in keys {
                run = (!previous.isEmpty && Daily.shiftDay(previous, 1) == key) ? run + 1 : 1
                previous = key
                best = max(best, run)
            }
            return best
        }

        public var totalDays: Int { days.values.filter { $0.practised }.count }
        public var totalSeconds: Double { days.values.reduce(0) { $0 + $1.seconds } }

        /// The last `count` days, oldest first, for the calendar strip.
        public func recentDays(_ count: Int, today: String = Daily.dayKey()) -> [(key: String, day: Day?)] {
            (0..<count).reversed().map { i in
                let key = Daily.shiftDay(today, -i)
                return (key, days[key])
            }
        }
    }

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local calendar day as YYYY-MM-DD, so "today" means today here.
    public static func dayKey(_ date: Date = Date()) -> String {
        keyFormatter.string(from: date)
    }

    /// Shift a YYYY-MM-DD key by whole days, staying in local time.
    public static func shiftDay(_ key: String, _ days: Int) -> String {
        guard let date = keyFormatter.date(from: key),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) else { return key }
        return dayKey(shifted)
    }

    public static func serialize(_ log: Log) -> Data { (try? JSONEncoder().encode(log)) ?? Data() }

    /// Parse stored JSON defensively. Anything malformed falls back to a clean slate.
    public static func parse(_ data: Data?) -> Log {
        guard let data, !data.isEmpty,
              let raw = try? JSONSerialization.jsonObject(with: data),
              let d = raw as? [String: Any] else { return Log() }
        if let v = d["version"], History.numeric(v) != 1 { return Log() }
        var log = Log()
        let pattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
        for (key, value) in d["days"] as? [String: Any] ?? [:] {
            guard pattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil,
                  let v = value as? [String: Any] else { continue }
            var day = Day()
            day.seconds = History.nonNegative(v["seconds"])
            day.steps = Int(History.nonNegative(v["steps"]).rounded(.down))
            day.completed = History.boolean(v["completed"])
            log.days[key] = day
        }
        log.updated = History.nonNegative(d["updated"])
        return log
    }
}
