import Foundation
import Observation
import SwiftUI
import UIKit
import SingwellCore

/// Which surface is driving the session. Switching surfaces ends any drill in flight.
enum PracticeMode: String, CaseIterable, Identifiable {
    case daily, sing, train, library, progress
    var id: String { rawValue }
}

struct WarmupLive: Equatable {
    var beat: Warmup.Beat
    var progress: Double
}

struct QuestState: Equatable {
    var run: Quest.Run
    var finished: Bool
    var synthetic: Bool
    var summary: Quest.Summary?
    var saved: Bool
}

struct DailyRun: Equatable {
    var routine: Daily.Routine
    var index: Int
    /// Seconds left on the current step.
    var left: Double
    var playing: Bool
    /// Seconds of this routine already logged, so a replay cannot double-count.
    var logged: Double
    var step: Daily.Step { routine.steps[index] }
    var isLast: Bool { index >= routine.steps.count - 1 }
}

/// A finished recording waiting for the user to name and keep (or discard) it.
struct PendingTake: Identifiable, Equatable {
    var id: UUID
    var url: URL
    var duration: Double
    var frames: [PitchFrame]
    var context: TakeContext
}

/// The live practice state machine: microphone, pitch trail, recording, warm-ups, quests and
/// the daily routine. A direct port of the web app's session logic, without the DOM.
@MainActor
@Observable
final class PracticeSession {
    // Live input
    private(set) var listening = false
    private(set) var busy = false
    var error: String?
    private(set) var pitch: Double?
    private(set) var level: Double = 0
    private(set) var frames: [PitchFrame] = []
    private(set) var target: Int?
    private(set) var playedNote: Int?
    private(set) var sessionLow: Int?
    private(set) var sessionHigh: Int?
    /// Set while a reference tone rings so the detector ignores the speaker.
    private var referenceUntil: Double = 0

    // Recording
    private(set) var recording = false
    private(set) var recordSeconds: Double = 0
    var pendingTake: PendingTake?
    private var recordingStart: Double = 0
    private var recordingFrames: [PitchFrame] = []
    private var recordingURL: URL?
    private var recordingContext: TakeContext = .sing

    // Warm-ups
    private(set) var warming = false
    private(set) var warmLabel = "Ready"
    private(set) var warmPlan: [Warmup.Beat] = []
    private(set) var warmLive: WarmupLive?
    private(set) var scores: [String: Warmup.NoteScore] = [:]
    private var warm: (beats: [Warmup.Beat], start: Double, scheduled: Int, duration: Double, last: Int, click: Bool)?
    private var warmTimer: Timer?

    // Quest
    private(set) var questState: QuestState?
    private var quest: (run: Quest.Run, startedAt: Double, targetSince: Double, lastSample: Double, synthetic: Bool)?

    // Daily routine
    private(set) var dailyRun: DailyRun?
    private(set) var dayDone = false
    private var dailyTimer: Timer?
    private var holdSamples: [(t: Double, midi: Double)] = []
    private(set) var steadiness: Double?

    // Demo
    private(set) var demo = false
    private var demoTimer: Timer?
    private var demoStart = 0.0
    private var demoLastTarget: Int?
    private var demoTargetSince = 0.0

    // Practice time bookkeeping
    private var practiceStart: Double?
    private var practiceFlushed: Double = 0
    private var sessionCounted = false
    private var sustain = History.Sustain()
    private var keyTimer: Timer?

    let audio = AudioEngine()
    private var progress: ProgressStore?
    private var library: TakeLibrary?
    private var settings: AppSettings?

    init() {
        audio.onReading = { [weak self] reading in self?.handle(reading) }
        audio.onInterruption = { [weak self] in
            guard let self else { return }
            self.stopEverything()
            self.error = "Audio was interrupted. Tap Start listening to continue."
        }
    }

    func attach(progress: ProgressStore, library: TakeLibrary, settings: AppSettings) {
        self.progress = progress
        self.library = library
        self.settings = settings
    }

    var now: Double { ProcessInfo.processInfo.systemUptime }
    var inputActive: Bool { listening || (demo && demoTimer != nil) }
    var currentCents: Int? { Pitch.cents(pitch) }
    var nearestNote: Int? { pitch.map { Int($0.rounded()) } }

    // MARK: Listening

    /// Starts the microphone (asking for permission the first time). Returns false when it could not start.
    @discardableResult
    func startListening() async -> Bool {
        if demo { return startDemoVoice() }
        if listening { return true }
        if busy { return false }
        busy = true
        error = nil
        defer { busy = false }
        let granted = await AudioEngine.requestMicrophonePermission()
        guard granted else {
            error = AudioEngineError.permissionDenied.errorDescription
            return false
        }
        do {
            try audio.startListening()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Could not access the microphone."
            return false
        }
        listening = true
        frames = []
        let started = now
        practiceStart = started
        practiceFlushed = started
        if !sessionCounted {
            sessionCounted = true
            progress?.recordSession()
        }
        applyIdleTimer()
        return true
    }

    func stopListening() {
        if warm != nil { stopWarmup() }
        if quest != nil { endQuest() }
        finishRecording()
        audio.stopListening()
        flushPractice()
        practiceStart = nil
        listening = false
        pitch = nil
        level = 0
        applyIdleTimer()
    }

    func toggleListening() {
        if inputActive { stopInput() } else { Task { await startListening() } }
    }

    private func stopInput() {
        if demo { stopDemoVoice() } else { stopListening() }
    }

    /// Ends every drill, the microphone and any recording. Used on interruption and when leaving a surface.
    func stopEverything() {
        stopRoutine(logPartial: true)
        stopInput()
        stopDemoVoice()
    }

    private func flushPractice() {
        guard practiceStart != nil else { return }
        let delta = now - practiceFlushed
        practiceFlushed = now
        if delta > 0 && delta < 3600 { progress?.addPractice(seconds: delta) }
    }

    private func applyIdleTimer() {
        let keep = (settings?.keepAwake ?? true) && (inputActive || dailyRun?.playing == true)
        UIApplication.shared.isIdleTimerDisabled = keep
    }

    // MARK: Sample processing

    private func handle(_ reading: PitchReading) {
        guard listening else { return }
        process(midi: reading.midi, now: reading.time, level: reading.level, synthetic: false)
        if let start = practiceStart, reading.time - practiceFlushed >= 30 { _ = start; flushPractice() }
        if recording {
            recordSeconds = reading.time - recordingStart
            if recordSeconds >= 600 {
                finishRecording()
                error = "Your 10-minute take is ready. Listening continues; start another take whenever you like."
            }
        }
    }

    /// Shared by the microphone and the synthetic demo voice. Only real input feeds history.
    private func process(midi input: Double?, now: Double, level lvl: Double, synthetic: Bool) {
        var m = input
        if !synthetic && now < referenceUntil { m = nil }
        level = lvl

        if let w = warm {
            let elapsed = audio.synth.currentTime - w.start
            let idx = Int((elapsed / w.duration).rounded(.down))
            if idx >= 0, idx < w.beats.count {
                let beat = w.beats[idx]
                if beat.phase == .sing, let midi = beat.midi {
                    let withinNote = elapsed - beat.time + (beat.onset ? 0 : w.duration)
                    if withinNote >= 0.25 {
                        let key = "\(beat.round)-\(beat.noteIndex)"
                        scores[key] = Warmup.score(scores[key], midi: m, target: midi)
                    }
                }
            }
        }

        if var q = quest {
            let dt = min(0.25, max(0, now - q.lastSample))
            q.lastSample = now
            let advanced = q.run.sample(midi: m, dt: dt, elapsedOnTarget: now - q.targetSince)
            quest = q
            if advanced {
                Haptics.hit()
                if q.run.finished {
                    if let last = q.run.matched.last { audio.synth.fanfare(midi: last) }
                    endQuest()
                } else {
                    q.targetSince = now
                    quest = q
                    let next = q.run.current
                    target = next
                    if let next { cue(next, duration: 1.2) }
                }
            }
            if let live = quest {
                questState = QuestState(run: live.run, finished: false, synthetic: live.synthetic, summary: nil, saved: false)
            }
        }

        if !synthetic {
            let previous = sustain
            let next = previous.tracking(midi: m, now: now)
            if next != previous {
                sustain = next
                if next.low != previous.low || next.high != previous.high {
                    sessionLow = next.low
                    sessionHigh = next.high
                    progress?.recordRange(low: next.low, high: next.high)
                }
            }
        }

        if let run = dailyRun, run.playing, run.step.engine == .hold {
            if let m { holdSamples.append((now, m)) }
            holdSamples.removeAll { now - $0.t > 1.5 }
            steadiness = Self.steadiness(of: holdSamples)
        }

        pitch = m
        let frame = PitchFrame(t: now, midi: m, target: target.map(Double.init))
        frames.removeAll { now - $0.t > 10 }
        frames.append(frame)
        if recording {
            recordingFrames.append(PitchFrame(t: now - recordingStart, midi: m, target: frame.target))
        }
    }

    /// 1 = rock steady, 0 = wandering more than a semitone. Needs about a second of voiced input.
    static func steadiness(of samples: [(t: Double, midi: Double)]) -> Double? {
        guard samples.count >= 6 else { return nil }
        let values = samples.map { $0.midi }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return max(0, min(1, 1 - variance.squareRoot() / 0.5))
    }

    // MARK: Reference tones

    private func cue(_ midi: Int, duration: Double, at time: Double? = nil) {
        let delay = max(0, (time ?? audio.synth.currentTime) - audio.synth.currentTime)
        referenceUntil = max(referenceUntil, now + delay + duration + 0.15)
        audio.synth.play(midi: midi, at: time, duration: duration)
    }

    /// Tap a key on the piano roll to hear it.
    func playKey(_ midi: Int) {
        do { try audio.startOutputIfNeeded(listening: listening) } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Could not play this note."
            return
        }
        cue(midi, duration: 1)
        showPlayed(midi)
        Haptics.tap()
    }

    private func showPlayed(_ midi: Int) {
        playedNote = midi
        keyTimer?.invalidate()
        keyTimer = Timer.commonMode(interval: 1, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.playedNote = nil }
        }
    }

    // MARK: Recording

    func startRecording(context: TakeContext = .sing) async {
        guard !recording, !demo else { return }
        guard await startListening(), let library else { return }
        let url = library.newRecordingURL()
        do {
            try audio.startRecording(to: url)
        } catch {
            self.error = "Recording could not start."
            return
        }
        recordingURL = url
        recordingStart = now
        recordingFrames = []
        recordingContext = context
        recordSeconds = 0
        recording = true
        Haptics.tap()
    }

    func finishRecording() {
        guard recording, let url = recordingURL else { return }
        recording = false
        let written = audio.stopRecording() ?? 0
        let duration = max(written, now - recordingStart)
        recordingURL = nil
        if written < 0.3 {
            library?.discardUnsaved(at: url)
            error = "No audio was captured. Please try recording again."
            return
        }
        pendingTake = PendingTake(id: UUID(), url: url, duration: duration, frames: recordingFrames, context: recordingContext)
        Haptics.tap()
    }

    func toggleRecording() {
        if recording { finishRecording() } else { Task { await startRecording() } }
    }

    /// Keeps the pending take in the library under the chosen title.
    func savePendingTake(title: String) {
        guard let pending = pendingTake, let library else { return }
        let take = Take(id: pending.id, title: title, duration: pending.duration, fileName: pending.url.lastPathComponent,
                        frames: pending.frames, context: pending.context)
        library.add(take)
        pendingTake = nil
    }

    func discardPendingTake() {
        guard let pending = pendingTake else { return }
        library?.discardUnsaved(at: pending.url)
        pendingTake = nil
    }

    // MARK: Warm-ups

    func startWarmup(drill: Warmup.Drill, root: Int, steps: Int, bpm: Double, metronome: Bool) async {
        stopWarmup()
        if quest != nil { endQuest() }
        error = nil
        guard await startListening() else { return }
        do {
            let beats = try Warmup.plan(drill: drill, root: root, steps: steps, bpm: bpm)
            warmPlan = beats
            warmLive = nil
            scores = [:]
            warm = (beats, audio.synth.currentTime + 0.2, 0, 60 / bpm, -1, metronome)
            warming = true
            warmLabel = "Get ready"
            warmTimer?.invalidate()
            warmTimer = Timer.commonMode(interval: 0.025, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickWarmup() }
            }
        } catch {
            self.error = "Those warm-up settings are out of range."
        }
    }

    func stopWarmup() {
        warmTimer?.invalidate()
        warmTimer = nil
        warm = nil
        audio.synth.stopAll()
        if quest == nil { target = nil }
        warming = false
        warmLabel = "Ready"
        applyIdleTimer()
    }

    private func tickWarmup() {
        guard var w = warm else { return }
        let elapsed = audio.synth.currentTime - w.start
        if w.scheduled < w.beats.count, elapsed - w.beats[w.scheduled].time > 0.25 {
            stopWarmup()
            warmLabel = "Warm-up stopped because audio timing was interrupted. Press Start to restart."
            return
        }
        while w.scheduled < w.beats.count, w.beats[w.scheduled].time <= elapsed + 0.12 {
            let b = w.beats[w.scheduled]
            let when = max(audio.synth.currentTime, w.start + b.time)
            if b.phase == .listen, b.onset, let midi = b.midi { cue(midi, duration: w.duration * 1.7, at: when) }
            if w.click { audio.synth.click(accent: b.accent, at: when) }
            w.scheduled += 1
        }
        let idx = min(w.beats.count - 1, Int((elapsed / w.duration).rounded(.down)))
        if idx >= 0 {
            let beat = w.beats[idx]
            warmLive = WarmupLive(beat: beat, progress: min(1, ((elapsed - beat.time) / w.duration + (beat.onset ? 0 : 1)) / 2))
            if idx != w.last {
                w.last = idx
                target = beat.midi
                warmLabel = "\(beat.label) · \(Pitch.noteName(Double(beat.root))) · round \(beat.round)"
                if beat.accent { Haptics.beat(accent: beat.phase == .count) }
            }
        }
        warm = w
        if elapsed >= Double(w.beats.count) * w.duration {
            stopWarmup()
            warmLabel = "Warm-up complete. Listening can continue."
        }
    }

    // MARK: Quest

    func startQuest(low: Int, high: Int, count: Int) async {
        if warm != nil { stopWarmup() }
        if quest != nil { endQuest() }
        error = nil
        let synthetic = demo
        guard await startListening() else { return }
        let (a, b) = Quest.normalizeRange(Double(low), Double(high))
        let targets = Quest.makeTargets(low: Double(a), high: Double(b), count: count, seed: Date().timeIntervalSince1970 * 1000)
        let t = now
        let run = Quest.Run(targets: targets)
        quest = (run, t, t, t, synthetic)
        target = targets.first
        if let first = targets.first { cue(first, duration: 1.2, at: audio.synth.currentTime + 0.05) }
        questState = QuestState(run: run, finished: false, synthetic: synthetic, summary: nil, saved: false)
    }

    func skipQuestTarget() {
        guard var q = quest else { return }
        q.run.skip()
        if q.run.finished { quest = q; endQuest(); return }
        let t = now
        q.targetSince = t
        q.lastSample = t
        quest = q
        target = q.run.current
        if let next = q.run.current { cue(next, duration: 1.2) }
        questState = QuestState(run: q.run, finished: false, synthetic: q.synthetic, summary: nil, saved: false)
    }

    func replayQuestTarget() {
        guard let t = quest?.run.current else { return }
        cue(t, duration: 1.2)
        showPlayed(t)
    }

    func endQuest() {
        guard let q = quest else { return }
        quest = nil
        target = nil
        let summary = q.run.summary
        let saved = !q.synthetic && (q.run.finished || summary.matched > 0)
        if saved { progress?.recordQuest(summary) }
        questState = QuestState(run: q.run, finished: true, synthetic: q.synthetic, summary: summary, saved: saved)
    }

    func clearQuestState() { questState = nil }

    // MARK: Daily routine

    func startRoutine(_ id: Daily.RoutineID) async {
        stopRoutine(logPartial: true)
        if warm != nil { stopWarmup() }
        if quest != nil { endQuest() }
        let routine = progress?.routine(id) ?? Daily.routine(id)
        dayDone = false
        dailyRun = DailyRun(routine: routine, index: 0, left: routine.steps[0].seconds, playing: true, logged: 0)
        await prepareStep()
        dailyTimer?.invalidate()
        dailyTimer = Timer.commonMode(interval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickRoutine() }
        }
        applyIdleTimer()
    }

    private func prepareStep() async {
        guard let run = dailyRun else { return }
        holdSamples = []
        steadiness = nil
        if run.step.needsMic {
            if !listening { _ = await startListening() }
            if run.step.engine == .hold, let hold = run.step.hold {
                target = hold
                cue(hold, duration: 1.2)
            } else {
                target = nil
            }
        } else {
            target = nil
        }
    }

    private func tickRoutine() {
        guard var run = dailyRun, run.playing else { return }
        run.left -= 0.25
        if run.left <= 0 {
            completeStep(&run)
        } else {
            dailyRun = run
        }
    }

    private func completeStep(_ run: inout DailyRun) {
        let step = run.step
        progress?.logStep(seconds: step.seconds)
        run.logged += step.seconds
        Haptics.hit()
        if run.isLast {
            progress?.logRoutineComplete()
            dailyRun = nil
            dayDone = true
            dailyTimer?.invalidate()
            target = nil
            applyIdleTimer()
            return
        }
        run.index += 1
        run.left = run.routine.steps[run.index].seconds
        dailyRun = run
        Task { await prepareStep() }
    }

    func pauseRoutine() {
        dailyRun?.playing = false
        applyIdleTimer()
    }

    func resumeRoutine() {
        dailyRun?.playing = true
        applyIdleTimer()
    }

    /// Skips ahead without logging the skipped step as practised.
    func nextStep() {
        guard var run = dailyRun else { return }
        if run.isLast {
            dailyRun = nil
            dayDone = run.logged > 0
            if dayDone { progress?.logRoutineComplete() }
            dailyTimer?.invalidate()
            target = nil
            return
        }
        run.index += 1
        run.left = run.routine.steps[run.index].seconds
        dailyRun = run
        Task { await prepareStep() }
    }

    func previousStep() {
        guard var run = dailyRun, run.index > 0 else { return }
        run.index -= 1
        run.left = run.routine.steps[run.index].seconds
        dailyRun = run
        Task { await prepareStep() }
    }

    /// Restart the current step's clock.
    func restartStep() {
        guard var run = dailyRun else { return }
        run.left = run.step.seconds
        dailyRun = run
        Task { await prepareStep() }
    }

    func stopRoutine(logPartial: Bool = false) {
        if logPartial, let run = dailyRun {
            let done = run.step.seconds - run.left
            if done >= 15 { progress?.logStep(seconds: done) }
        }
        dailyTimer?.invalidate()
        dailyTimer = nil
        dailyRun = nil
        holdSamples = []
        steadiness = nil
        if quest == nil && warm == nil { target = nil }
        applyIdleTimer()
    }

    func dismissDayDone() { dayDone = false }

    // MARK: Session range

    func resetSessionRange() {
        sustain = History.Sustain()
        sessionLow = nil
        sessionHigh = nil
    }

    func resetSessionCount() { sessionCounted = false }

    // MARK: Demo voice

    func enterDemo() {
        finishRecording()
        stopListening()
        frames = []
        error = nil
        questState = nil
        warmLive = nil
        scores = [:]
        demo = true
        _ = startDemoVoice()
    }

    func exitDemo() {
        stopDemoVoice()
        demo = false
        frames = []
        questState = nil
        warmLive = nil
        scores = [:]
        error = nil
    }

    private func startDemoVoice() -> Bool {
        if demoTimer != nil { return true }
        try? audio.startOutput()
        frames = []
        demoStart = now
        demoLastTarget = nil
        demoTargetSince = demoStart
        demoTimer = Timer.commonMode(interval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickDemo() }
        }
        return true
    }

    private func tickDemo() {
        let t = now
        let sample: Demo.Sample
        if let live = target {
            if live != demoLastTarget { demoLastTarget = live; demoTargetSince = t }
            sample = Demo.voice(local: t - demoTargetSince, target: Double(live), global: t - demoStart)
        } else {
            demoLastTarget = nil
            sample = (warm != nil || quest != nil) ? Demo.Sample(midi: nil, level: 0.05) : Demo.freeSample(at: t - demoStart)
        }
        process(midi: sample.midi, now: t, level: sample.level, synthetic: true)
    }

    private func stopDemoVoice() {
        if warm != nil { stopWarmup() }
        if quest != nil { endQuest() }
        demoTimer?.invalidate()
        demoTimer = nil
        pitch = nil
        level = 0
    }
}

extension Timer {
    /// A repeating (or one-shot) timer that keeps firing while the user scrolls. `scheduledTimer`
    /// only runs in the default run-loop mode, which pauses during ScrollView tracking.
    static func commonMode(interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

extension PracticeSession {
    /// A binding to the pending take that only fires for recordings made on one surface,
    /// so two tabs never try to present the save sheet at once.
    func pendingBinding(for context: TakeContext) -> Binding<PendingTake?> {
        Binding(get: { [weak self] in self?.pendingTake.flatMap { $0.context == context ? $0 : nil } },
                set: { [weak self] value in if value == nil { self?.pendingTake = nil } })
    }
}

extension AudioEngine {
    /// Output for key taps: reuse the live session when listening, otherwise a playback-only session.
    func startOutputIfNeeded(listening: Bool) throws {
        if listening && isRunning { return }
        try startOutput()
    }
}
