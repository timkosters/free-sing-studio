import SwiftUI
import SingwellCore

/// Free sing: live note, frequency and cents over the piano roll, with one-tap recording.
struct SingView: View {
    @Environment(PracticeSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(TakeLibrary.self) private var library
    @Environment(StoreService.self) private var store
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                statsRow
                PianoRollView(frames: session.frames, now: session.now, currentMidi: session.pitch, target: session.target,
                              playedNote: session.playedNote, follow: settings.followPitch, demo: session.demo,
                              onKeyTap: { session.playKey($0) })
                    .frame(maxHeight: .infinity)
                if let error = session.error {
                    ErrorBanner(message: error) { session.error = nil }
                }
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.pageBackground)
            .navigationTitle("Sing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        if session.inputActive { LiveDot(color: session.recording ? .red : .singGreen) }
                        Text(statusLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Follow my pitch", isOn: Bindable(settings).followPitch)
                        Button(session.demo ? "Exit demo voice" : "Try demo voice") {
                            session.demo ? session.exitDemo() : session.enterDemo()
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(item: session.pendingBinding(for: .sing)) { pending in
                SaveTakeSheet(pending: pending)
            }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Keep every take. Free saves \(Entitlements.freeTakeLimit) recordings; Pro saves them all.") }
        }
    }

    private var statusLabel: String {
        if session.recording { return "RECORDING" }
        if session.demo { return "DEMO" }
        if session.busy { return "STARTING" }
        return session.listening ? "LISTENING" : "READY"
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(label: session.demo ? "Synthetic note" : "Your note",
                     value: session.nearestNote.map { Pitch.noteName(Double($0)) } ?? "—",
                     tint: session.demo ? .voiceSoft : .voice)
            StatTile(label: "Frequency", value: session.pitch.map { String(format: "%.1f", Pitch.midiToFrequency($0)) } ?? "—", unit: "Hz")
            StatTile(label: "Off by", value: session.currentCents.map { ($0 > 0 ? "+" : "") + String($0) } ?? "—", unit: "cents",
                     tint: (session.currentCents.map { abs($0) <= 35 } ?? false) ? .singGreen : nil)
        }
        .card()
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                session.toggleListening()
            } label: {
                Label(session.inputActive ? "Stop" : "Start listening", systemImage: session.inputActive ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(session.busy)

            Button {
                if session.recording {
                    session.finishRecording()
                } else if !Entitlements.canSaveTake(count: library.takes.count, pro: store.isPro) {
                    showPaywall = true
                } else {
                    Task { await session.startRecording(context: .sing) }
                }
            } label: {
                Label(session.recording ? Formatting.clock(session.recordSeconds) : "Record", systemImage: session.recording ? "stop.circle.fill" : "record.circle")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.recording ? .red : .voice)
            .controlSize(.large)
            .disabled(session.demo || session.busy)
        }
    }
}

/// Name and keep a finished recording, or let it go.
struct SaveTakeSheet: View {
    @Environment(PracticeSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var pending: PendingTake
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    LabeledContent("Length", value: Formatting.clock(pending.duration))
                    if let range = rangeLabel { LabeledContent("Notes reached", value: range) }
                } footer: {
                    Text("Saved takes stay on this device. Share or export them any time from the Library.")
                }
            }
            .navigationTitle("Keep this take?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { session.discardPendingTake(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { session.savePendingTake(title: title); dismiss() }.bold()
                }
            }
            .onAppear { title = Take.defaultTitle(for: Date(), context: pending.context) }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private var rangeLabel: String? {
        let notes = pending.frames.compactMap { $0.midi }
        guard let lo = notes.min(), let hi = notes.max() else { return nil }
        return "\(Pitch.noteName(lo)) – \(Pitch.noteName(hi))"
    }
}
