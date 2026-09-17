import SwiftUI
import SingwellCore

/// Today tab: streak, routine picker and the guided step runner.
struct DailyView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(ProgressStore.self) private var progress
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @State private var showPaywall = false
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let run = session.dailyRun {
                        RoutineRunnerView(run: run)
                    } else if session.dayDone {
                        dayDoneCard
                    } else {
                        streakCard
                        routinePicker
                    }
                    if let error = session.error, session.dailyRun != nil {
                        ErrorBanner(message: error) { session.error = nil }
                    }
                }
                .padding(16)
            }
            .background(Color.pageBackground)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Unlock the Full and Bridge routines.") }
            .sheet(isPresented: $showAccount) { AccountView() }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "flame.fill").foregroundStyle(progress.streak > 0 ? .orange : .secondary)
                Text("\(progress.streak) day streak").font(.display(.title2))
                Spacer()
                Text(progress.practisedToday ? "Practised today" : "Not yet today").font(.sora(.caption)).foregroundStyle(.secondary)
            }
            StreakStrip(log: progress.daily, days: 14)
            HStack {
                Text("Best \(progress.daily.bestStreak) days").font(.sora(.caption)).foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.daily.totalDays) days · \(Formatting.minutes(progress.daily.totalSeconds)) of routine").font(.sora(.caption)).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var routinePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ten minutes. Every day.").font(.display(.title2))
            Text("A guided routine, one step at a time, on a clock. Pick a length and press start.")
                .font(.sora(.subheadline)).foregroundStyle(.secondary)
            ForEach(Daily.routines) { routine in
                let locked = !Entitlements.canUseRoutine(routine.id.rawValue, pro: store.isPro)
                Button {
                    if locked { showPaywall = true } else {
                        settings.dailyRoutine = routine.id.rawValue
                        Task { await session.startRoutine(routine.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(routine.label).font(.display(.title3))
                                Text(routine.lengthLabel).font(.sora(.caption, .semibold)).foregroundStyle(.secondary)
                                if locked { ProBadge() }
                            }
                            Text(routine.blurb).font(.sora(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            Text(routine.steps.map { $0.title }.joined(separator: " · ")).font(.sora(.caption2)).foregroundStyle(.tertiary).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: locked ? "lock.fill" : "play.fill")
                            .font(.display(.title3))
                            .foregroundStyle(locked ? Color.secondary : Color.voice)
                    }
                    .padding(14)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dayDoneCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(Color.singGreen)
            Text("Routine complete").font(.display(.title2))
            Text("\(progress.streak) day streak. See you tomorrow.").foregroundStyle(.secondary)
            StreakStrip(log: progress.daily, days: 14)
            HStack {
                Button("Done") { session.dismissDayDone() }.buttonStyle(.borderedProminent).tint(.voice)
                ShareLink(item: "I just finished a \(progress.streak)-day singing streak with Singwell.") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Fourteen little squares, one per day, filled when practised.
struct StreakStrip: View {
    var log: Daily.Log
    var days: Int

    var body: some View {
        let recent = log.recentDays(days)
        HStack(spacing: 4) {
            ForEach(recent, id: \.key) { entry in
                let practised = entry.day?.practised ?? false
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(practised ? (entry.day?.completed == true ? Color.orange : Color.orange.opacity(0.55)) : Color.primary.opacity(0.08))
                    .frame(height: 14)
            }
        }
        .accessibilityLabel("\(recent.filter { $0.day?.practised ?? false }.count) of the last \(days) days practised")
    }
}

/// One step at a time, with a clock and the panel that step needs.
struct RoutineRunnerView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(TakeLibrary.self) private var library
    @Environment(StoreService.self) private var store
    var run: DailyRun
    @State private var confirmStop = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(run.routine.label).font(.sora(.caption, .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Step \(run.index + 1) of \(run.routine.steps.count)").font(.sora(.caption, .semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(run.index) + (1 - run.left / run.step.seconds), total: Double(run.routine.steps.count))
                .tint(.voice)
            VStack(alignment: .leading, spacing: 6) {
                Text(run.step.title).font(.display(.title2))
                Text(run.step.cue).font(.sora(.body, .medium))
                ForEach(run.step.detail, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.voice.opacity(0.6)).frame(width: 5, height: 5).padding(.top, 7)
                        Text(line).font(.sora(.subheadline)).foregroundStyle(.secondary)
                    }
                }
                Text(run.step.why).font(.sora(.caption)).italic().foregroundStyle(.tertiary).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            enginePanel
                .frame(height: 240)

            HStack {
                Text(Formatting.clock(run.left)).font(.display(size: 44)).monospacedDigit()
                Spacer()
                if run.step.needsMic, !session.demo {
                    Button {
                        if session.recording { session.finishRecording() }
                        else if Entitlements.canSaveTake(count: library.takes.count, pro: store.isPro) { Task { await session.startRecording(context: .daily) } }
                    } label: {
                        Image(systemName: session.recording ? "stop.circle.fill" : "record.circle").font(.display(.title))
                    }.tint(session.recording ? .red : .voice)
                }
            }
            HStack(spacing: 12) {
                Button { session.previousStep() } label: { Image(systemName: "backward.end.fill") }.disabled(run.index == 0)
                Button { run.playing ? session.pauseRoutine() : session.resumeRoutine() } label: {
                    Image(systemName: run.playing ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.voice).controlSize(.large)
                Button { session.restartStep() } label: { Image(systemName: "arrow.counterclockwise") }
                Button { session.nextStep() } label: { Image(systemName: "forward.end.fill") }
                Button(role: .destructive) { confirmStop = true } label: { Image(systemName: "xmark") }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .confirmationDialog("Stop the routine?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { session.stopRoutine(logPartial: true) }
        } message: { Text("Steps you finished still count toward today.") }
        .sheet(item: session.pendingBinding(for: .daily)) { pending in SaveTakeSheet(pending: pending) }
    }

    @ViewBuilder
    private var enginePanel: some View {
        switch run.step.engine {
        case .none:
            VStack(spacing: 10) {
                Image(systemName: "figure.mind.and.body").font(.system(size: 44)).foregroundStyle(Color.voice)
                Text("No microphone for this one. Follow the cue and breathe.").font(.sora(.footnote)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        case .breath:
            BreathPacer(cycle: run.step.breath ?? (4, 2, 8), elapsed: run.step.seconds - run.left, playing: run.playing)
                .card()
        case .mic:
            PianoRollView(frames: session.frames, now: session.now, currentMidi: session.pitch, target: session.target,
                          playedNote: session.playedNote, follow: settings.followPitch, demo: session.demo, onKeyTap: { session.playKey($0) })
        case .hold:
            VStack(spacing: 10) {
                HStack {
                    StatTile(label: "Hold", value: run.step.hold.map { Pitch.noteName(Double($0)) } ?? "—", tint: .singGreen)
                    StatTile(label: "You", value: session.nearestNote.map { Pitch.noteName(Double($0)) } ?? "—", tint: .voice)
                    StatTile(label: "Steadiness", value: session.steadiness.map { "\(Int(($0 * 100).rounded()))" } ?? "—", unit: "%")
                    Button { if let h = run.step.hold { session.playKey(h) } } label: { Image(systemName: "speaker.wave.2.fill") }
                }
                .card()
                PianoRollView(frames: session.frames, now: session.now, currentMidi: session.pitch, target: session.target,
                              playedNote: session.playedNote, follow: true, demo: session.demo, onKeyTap: { session.playKey($0) })
            }
        }
    }
}

/// Expanding ring for inhale, still for hold, shrinking for exhale.
struct BreathPacer: View {
    var cycle: (Double, Double, Double)
    var elapsed: Double
    var playing: Bool

    private var phase: (label: String, scale: Double, remaining: Double) {
        let total = cycle.0 + cycle.1 + cycle.2
        let t = elapsed.truncatingRemainder(dividingBy: total)
        if t < cycle.0 { return ("Inhale", 0.55 + 0.45 * (t / cycle.0), cycle.0 - t) }
        if t < cycle.0 + cycle.1 { return ("Hold", 1.0, cycle.0 + cycle.1 - t) }
        let e = t - cycle.0 - cycle.1
        return ("Exhale", 1.0 - 0.45 * (e / cycle.2), total - t)
    }

    var body: some View {
        let p = phase
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.voice.opacity(0.15), lineWidth: 10)
                Circle().fill(Color.voice.opacity(0.18)).scaleEffect(p.scale)
                    .animation(.linear(duration: 0.25), value: p.scale)
                VStack(spacing: 2) {
                    Text(p.label).font(.display(.title3))
                    Text("\(Int(p.remaining.rounded(.up)))").font(.display(.largeTitle)).monospacedDigit()
                }
            }
            .frame(width: 150, height: 150)
            Text("In \(Int(cycle.0)) · hold \(Int(cycle.1)) · out \(Int(cycle.2))").font(.sora(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
