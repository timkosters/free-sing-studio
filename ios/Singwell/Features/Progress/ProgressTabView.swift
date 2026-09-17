import SwiftUI
import UIKit
import SingwellCore

/// Range map, practice history and quest bests. Observation, never a verdict on the voice.
struct ProgressTabView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(ProgressStore.self) private var progress
    @Environment(TakeLibrary.self) private var library
    @State private var confirmClear = false
    @State private var showAccount = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rangeCard
                    practiceCard
                    questCard
                    shareCard
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear practice history", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Text("Only notes held for half a second count toward your range. Everything on this page stays on your device.")
                        .font(.sora(.caption)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background(Color.pageBackground)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showAccount) { AccountView() }
            .task(id: "\(progress.history.low ?? -1)-\(progress.history.high ?? -1)-\(progress.streak)") { shareImage = renderShareImage() }
            .confirmationDialog("Clear all saved practice history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    progress.clearAll()
                    session.resetSessionRange()
                    session.resetSessionCount()
                }
            } message: { Text("Removes practice time, observed range, quest bests and your streak. Saved takes are kept. This cannot be undone.") }
        }
    }

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your range").font(.sora(.headline, .semibold))
            RangeMap(sessionLow: session.sessionLow, sessionHigh: session.sessionHigh, allLow: progress.history.low, allHigh: progress.history.high)
                .frame(height: 74)
            HStack {
                rangeLabel("This session", progress: (session.sessionLow, session.sessionHigh), tint: .voice)
                Spacer()
                rangeLabel("All time", progress: (progress.history.low, progress.history.high), tint: .singGreen)
            }
            if !session.inputActive {
                Button { Task { await session.startListening() } } label: {
                    Label("Start listening to map today's range", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            } else {
                Button { session.stopListening() } label: { Label("Stop listening", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
        }
        .card()
    }

    private func rangeLabel(_ title: String, progress: (Int?, Int?), tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.sora(.caption2, .semibold)).foregroundStyle(.secondary)
            if let lo = progress.0, let hi = progress.1 {
                Text("\(Pitch.noteName(Double(lo))) – \(Pitch.noteName(Double(hi)))").font(.display(.title3)).foregroundStyle(tint)
                Text("\(hi - lo) semitones").font(.sora(.caption)).foregroundStyle(.secondary)
            } else {
                Text("—").font(.display(.title3)).foregroundStyle(.secondary)
                Text("Sing to find out").font(.sora(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice").font(.sora(.headline, .semibold))
            HStack {
                StatTile(label: "Time listened", value: Formatting.minutes(progress.history.seconds))
                StatTile(label: "Sessions", value: "\(progress.history.sessions)")
                StatTile(label: "Streak", value: "\(progress.streak)", unit: "days", tint: progress.streak > 0 ? .orange : nil)
            }
            StreakStrip(log: progress.daily, days: 28)
            HStack {
                StatTile(label: "Routine days", value: "\(progress.daily.totalDays)")
                StatTile(label: "Routine time", value: Formatting.minutes(progress.daily.totalSeconds))
                StatTile(label: "Takes saved", value: "\(library.takes.count)")
            }
        }
        .card()
    }

    private var questCard: some View {
        let q = progress.history.quest
        return VStack(alignment: .leading, spacing: 12) {
            Text("Pitch Quest bests").font(.sora(.headline, .semibold))
            HStack {
                StatTile(label: "Runs", value: "\(q.runs)")
                StatTile(label: "Most matched", value: "\(q.mostMatched)")
                StatTile(label: "Quickest avg", value: q.quickestAverage.map { String(format: "%.1f", $0) } ?? "—", unit: "s")
            }
            if let lo = q.widestLow, let hi = q.widestHigh {
                Text("Widest quest: \(Pitch.noteName(Double(lo))) to \(Pitch.noteName(Double(hi))) (\(hi - lo) semitones)").font(.sora(.footnote)).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share your range").font(.sora(.headline, .semibold))
            RangeShareCard(low: progress.history.low, high: progress.history.high, streak: progress.streak)
                .frame(height: 170)
            if let image = shareImage {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("My vocal range", image: Image(uiImage: image))) {
                    Label("Share card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
        }
        .card()
    }

    @MainActor
    private func renderShareImage() -> UIImage? {
        let renderer = ImageRenderer(content: RangeShareCard(low: progress.history.low, high: progress.history.high, streak: progress.streak).frame(width: 720, height: 400))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// Horizontal C2–C6 scale with session and all-time bars.
struct RangeMap: View {
    var sessionLow: Int?
    var sessionHigh: Int?
    var allLow: Int?
    var allHigh: Int?
    private let low = Double(Quest.lowest) - 0.5
    private let span = Double(Quest.highest - Quest.lowest + 1)

    private func x(_ midi: Int, width: CGFloat) -> CGFloat {
        CGFloat((Double(min(Quest.highest, max(Quest.lowest, midi))) - low) / span) * width
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)).frame(height: 44)
                ForEach(Array(stride(from: Quest.lowest, through: Quest.highest, by: 12)), id: \.self) { c in
                    VStack(spacing: 2) {
                        Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1, height: 44)
                        Text(Pitch.noteName(Double(c))).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .position(x: x(c, width: w), y: 30)
                }
                if let lo = allLow, let hi = allHigh {
                    Capsule().fill(Color.singGreen.opacity(0.35))
                        .frame(width: max(6, x(hi, width: w) - x(lo, width: w) + 6), height: 14)
                        .offset(x: x(lo, width: w) - 3, y: -8)
                }
                if let lo = sessionLow, let hi = sessionHigh {
                    Capsule().fill(Color.voice)
                        .frame(width: max(6, x(hi, width: w) - x(lo, width: w) + 6), height: 14)
                        .offset(x: x(lo, width: w) - 3, y: 8)
                }
            }
        }
    }
}

/// The image people post. Brand colors, big notes, no judgment.
struct RangeShareCard: View {
    var low: Int?
    var high: Int?
    var streak: Int
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.09, blue: 0.32), Color(red: 0.44, green: 0.28, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "waveform"); Text("Singwell").font(.sora(.headline, .semibold)) }.foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("My observed range").font(.sora(.caption, .semibold)).foregroundStyle(.white.opacity(0.7))
                if let low, let high {
                    Text("\(Pitch.noteName(Double(low))) – \(Pitch.noteName(Double(high)))").font(.display(size: 44)).foregroundStyle(.white)
                    Text("\(high - low) semitones · \(streak) day streak").font(.sora(.subheadline)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("Still mapping").font(.display(size: 36)).foregroundStyle(.white)
                }
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
