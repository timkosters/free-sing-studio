import SwiftUI
import SingwellCore

/// Train tab: warm-ups and Pitch Quest behind one segmented control.
struct TrainView: View {
    @Environment(PracticeSession.self) private var session
    @State private var section: Segment = .warmups

    enum Segment: String, CaseIterable, Identifiable {
        case warmups = "Warm-ups", quest = "Pitch Quest"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Section", selection: $section) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let error = session.error { ErrorBanner(message: error) { session.error = nil } }
                    switch section {
                    case .warmups: WarmupsView()
                    case .quest: QuestView()
                    }
                }
                .padding(16)
            }
            .background(Color.pageBackground)
            .navigationTitle("Train")
            .onChange(of: section) { _, _ in
                session.stopWarmup()
                session.endQuest()
            }
        }
    }
}

/// Piano demonstration, count-in, your pass, breathe, up a semitone.
struct WarmupsView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @State private var showPaywall = false

    private var drill: Warmup.Drill { Warmup.Drill(rawValue: settings.warmupDrill) ?? .arpeggio }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Warm up, gently.").font(.title2.weight(.bold))
                Text("Listen to the piano, then sing it back. Use headphones so the microphone hears only you.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if session.warming || session.warmLive != nil {
                liveCard
            }

            settingsCard

            if !session.warming, let live = session.warmLive, !session.scores.isEmpty {
                resultsCard(finalRound: live.beat.round)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(reason: "All drills, more semitones and longer climbs are part of Pro.") }
    }

    private var liveCard: some View {
        VStack(spacing: 12) {
            HStack {
                LiveDot(color: session.warmLive?.beat.phase == .sing ? .singGreen : .listenBlue)
                Text(session.warmLabel).font(.subheadline.weight(.semibold))
                Spacer()
            }
            PianoRollView(frames: session.frames, now: session.now, window: 8, currentMidi: session.pitch, target: session.target,
                          playedNote: session.playedNote, follow: true, demo: session.demo, onKeyTap: { session.playKey($0) })
                .frame(height: 260)
            if let live = session.warmLive {
                noteLane(round: live.beat.round, current: live)
            }
        }
        .card()
    }

    private func noteLane(round: Int, current: WarmupLive) -> some View {
        let pattern = drill.pattern
        let root = current.beat.root
        return VStack(alignment: .leading, spacing: 6) {
            Text(current.beat.phase == .sing ? "YOUR TURN" : current.beat.phase == .listen ? "LISTEN" : current.beat.phase == .count ? "COUNT-IN" : "BREATHE")
                .font(.caption2.weight(.bold)).foregroundStyle(current.beat.phase == .sing ? Color.singGreen : Color.listenBlue)
            HStack(spacing: 5) {
                ForEach(Array(pattern.enumerated()), id: \.offset) { i, offset in
                    let key = "\(round)-\(i)"
                    let verdict = Warmup.verdict(session.scores[key])
                    let active = current.beat.noteIndex == i && (current.beat.phase == .sing || current.beat.phase == .listen)
                    VStack(spacing: 2) {
                        Text(Pitch.noteName(Double(root + offset))).font(.caption.weight(.semibold))
                        Text(session.scores[key] == nil ? " " : verdict.rawValue).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(verdict == .hit && session.scores[key] != nil ? Color.singGreen.opacity(0.15) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active ? (current.beat.phase == .sing ? Color.singGreen : Color.listenBlue) : .clear, lineWidth: 2))
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 14) {
            Picker("Drill", selection: Binding(get: { drill }, set: { d in
                if Entitlements.canUseDrill(d.rawValue, pro: store.isPro) { settings.warmupDrill = d.rawValue } else { showPaywall = true }
            })) {
                ForEach(Warmup.Drill.allCases) { d in
                    Text(d.label + (Entitlements.canUseDrill(d.rawValue, pro: store.isPro) ? "" : " 🔒")).tag(d)
                }
            }
            .pickerStyle(.segmented)
            NoteStepper(title: "Starting note", midi: Bindable(settings).warmupRoot, range: Warmup.rootRange, onPlay: { session.playKey($0) })
            HStack {
                Text("Climb")
                Spacer()
                Text("\(settings.warmupSteps) semitone\(settings.warmupSteps == 1 ? "" : "s")").foregroundStyle(.secondary)
                if !store.isPro && settings.warmupSteps > Entitlements.freeWarmupSteps { ProBadge() }
            }
            Slider(value: Binding(get: { Double(settings.warmupSteps) }, set: { settings.warmupSteps = Int($0.rounded()) }), in: 0...12, step: 1)
            HStack { Text("Tempo"); Spacer(); Text("\(Int(settings.warmupBpm)) bpm").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: Bindable(settings).warmupBpm, in: 50...140, step: 2)
            Toggle("Metronome click", isOn: Bindable(settings).metronome)
            Button {
                if session.warming { session.stopWarmup(); return }
                if !Entitlements.canUseWarmupSteps(settings.warmupSteps, pro: store.isPro) { showPaywall = true; return }
                Task { await session.startWarmup(drill: drill, root: settings.warmupRoot, steps: settings.warmupSteps, bpm: settings.warmupBpm, metronome: settings.metronome) }
            } label: {
                Label(session.warming ? "Stop warm-up" : "Start warm-up", systemImage: session.warming ? "stop.fill" : "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(session.warming ? .red : .voice).controlSize(.large)
            .disabled(session.busy)
        }
        .card()
    }

    private func resultsCard(finalRound: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last warm-up").font(.headline)
            let hits = session.scores.values.filter { Warmup.verdict($0) == .hit }.count
            let scored = session.scores.values.filter { Warmup.verdict($0) != .none }.count
            Text("\(hits) of \(scored) sung notes landed within 50 cents.").font(.subheadline).foregroundStyle(.secondary)
            Text("Hit means at least half your samples on a note were in tune. Low and High say which way to lean next time.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension Warmup.Drill {
    var pattern: [Int] {
        switch self {
        case .arpeggio: return [0, 4, 7, 12, 7, 4, 0]
        case .fiveNote: return [0, 2, 4, 5, 7, 5, 4, 2, 0]
        }
    }
}

/// One target at a time. Match it, hold it for a second, move on.
struct QuestView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pitch Quest.").font(.title2.weight(.bold))
                Text("One target at a time. Match it within 50 cents and hold for a second. Targets never leap more than five semitones.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let q = session.questState {
                if q.finished, let summary = q.summary { summaryCard(q, summary) } else { liveCard(q) }
            } else {
                setupCard
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(reason: "Longer quests (12 and 16 targets) are part of Pro.") }
    }

    private var setupCard: some View {
        VStack(spacing: 14) {
            NoteStepper(title: "Lowest comfortable", midi: Bindable(settings).questLow, range: Quest.lowest...Quest.highest, onPlay: { session.playKey($0) })
            NoteStepper(title: "Highest comfortable", midi: Bindable(settings).questHigh, range: Quest.lowest...Quest.highest, onPlay: { session.playKey($0) })
            Picker("Targets", selection: Binding(get: { settings.questCount }, set: { c in
                if Entitlements.canUseQuestCount(c, pro: store.isPro) { settings.questCount = c } else { showPaywall = true }
            })) {
                ForEach(Quest.counts, id: \.self) { c in
                    Text("\(c)" + (Entitlements.canUseQuestCount(c, pro: store.isPro) ? "" : " 🔒")).tag(c)
                }
            }
            .pickerStyle(.segmented)
            Button {
                Task { await session.startQuest(low: settings.questLow, high: settings.questHigh, count: settings.questCount) }
            } label: { Label("Start quest", systemImage: "target").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(.voice).controlSize(.large)
            .disabled(session.busy)
        }
        .card()
    }

    private func liveCard(_ q: QuestState) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Target \(q.run.index + 1) of \(q.run.targets.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(Array(q.run.outcomes.enumerated()), id: \.offset) { _, o in
                        Circle().fill(o == .hit ? Color.singGreen : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                    }
                }
            }
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 12)
                Circle().trim(from: 0, to: q.run.hold / Quest.holdSeconds)
                    .stroke(Color.singGreen, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.08), value: q.run.hold)
                VStack(spacing: 4) {
                    Text("SING").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(q.run.current.map { Pitch.noteName(Double($0)) } ?? "—").font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(youLabel).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)
            HStack(spacing: 12) {
                Button { session.replayQuestTarget() } label: { Label("Hear it", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button { session.skipQuestTarget() } label: { Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button(role: .destructive) { session.endQuest() } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
            }
            .controlSize(.large)
            PianoRollView(frames: session.frames, now: session.now, window: 6, currentMidi: session.pitch, target: session.target,
                          playedNote: session.playedNote, follow: true, demo: session.demo, onKeyTap: { session.playKey($0) })
                .frame(height: 200)
        }
        .card()
    }

    private var youLabel: String {
        guard let midi = session.pitch, let t = session.target else { return "Listening…" }
        let cents = (midi - Double(t)) * 100
        if abs(cents) <= 50 { return "On it. Hold." }
        return cents < 0 ? "A little higher" : "A little lower"
    }

    private func summaryCard(_ q: QuestState, _ s: Quest.Summary) -> some View {
        VStack(spacing: 12) {
            Image(systemName: s.complete ? "checkmark.seal.fill" : "target").font(.system(size: 44)).foregroundStyle(s.complete ? Color.singGreen : Color.voice)
            Text(Quest.verdict(s)).font(.title3.weight(.semibold))
            HStack {
                StatTile(label: "Matched", value: "\(s.matched)/\(s.total)")
                StatTile(label: "Avg per note", value: s.averageSeconds.map { String(format: "%.1f", $0) } ?? "—", unit: "s")
                StatTile(label: "Covered", value: (s.low != nil && s.high != nil) ? "\(Pitch.noteName(Double(s.low!)))–\(Pitch.noteName(Double(s.high!)))" : "—")
            }
            if q.synthetic { Text("Demo voice: not saved to your history.").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Again") { Task { await session.startQuest(low: settings.questLow, high: settings.questHigh, count: settings.questCount) } }
                    .buttonStyle(.borderedProminent).tint(.voice)
                Button("Done") { session.clearQuestState() }.buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
