import SwiftUI
import SingwellCore

/// Every saved take, newest first. Swipe to favorite or delete; tap to replay with the pitch trail.
struct LibraryView: View {
    @Environment(TakeLibrary.self) private var library
    @Environment(StoreService.self) private var store
    @State private var filter: Filter = .all
    @State private var showPaywall = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, favorites
        var id: String { rawValue }
    }

    private var shown: [Take] {
        filter == .favorites ? library.takes.filter { $0.favorite } : library.takes
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "waveform",
                                           description: Text("Record in Sing, or during the daily routine, and your takes collect here with their pitch trails."))
                } else {
                    List {
                        if !store.isPro {
                            Section {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(library.takes.count) of \(Entitlements.freeTakeLimit) free takes used").font(.sora(.subheadline, .semibold))
                                        Text("Pro keeps every recording.").font(.sora(.caption)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Go Pro") { showPaywall = true }.buttonStyle(.borderedProminent).tint(.voice).controlSize(.small)
                                }
                            }
                        }
                        Section {
                            ForEach(shown) { take in
                                NavigationLink(value: take.id) { TakeRow(take: take) }
                                    .swipeActions(edge: .leading) {
                                        Button { library.toggleFavorite(take) } label: {
                                            Label(take.favorite ? "Unfavorite" : "Favorite", systemImage: take.favorite ? "star.slash" : "star")
                                        }.tint(.yellow)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { library.delete(take) } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        } header: {
                            Text("\(shown.count) take\(shown.count == 1 ? "" : "s") · \(Formatting.minutes(library.totalSeconds)) recorded")
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: UUID.self) { id in
                if let take = library.takes.first(where: { $0.id == id }) { TakeDetailView(take: take) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag(Filter.all)
                        Text("Favorites").tag(Filter.favorites)
                    }.pickerStyle(.segmented).frame(width: 170)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Keep every take you record.") }
        }
    }
}

struct TakeRow: View {
    var take: Take
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: take.context.symbol)
                .font(.display(.title3))
                .foregroundStyle(Color.voice)
                .frame(width: 34, height: 34)
                .background(Color.voice.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(take.title).font(.sora(.body, .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(Formatting.clock(take.duration)).monospacedDigit()
                    if let r = take.observedRange { Text("· \(Pitch.noteName(Double(r.low)))–\(Pitch.noteName(Double(r.high)))") }
                    Text("· \(take.createdAt.formatted(.relative(presentation: .named)))")
                }
                .font(.sora(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            if take.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.sora(.caption)) }
        }
    }
}

/// Replay with the pitch trail scrolling under the playhead, rename, share, delete.
struct TakeDetailView: View {
    @Environment(TakeLibrary.self) private var library
    @Environment(PracticeSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var player = TakePlayer()
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var loadError: String?
    var take: Take

    private var current: Take { library.takes.first { $0.id == take.id } ?? take }

    var body: some View {
        VStack(spacing: 14) {
            PianoRollView(frames: current.frames, now: player.currentTime, window: 10,
                          currentMidi: frameAt(player.currentTime)?.midi, target: nil, follow: false)
                .frame(maxHeight: .infinity)
            if let loadError { ErrorBanner(message: loadError) { self.loadError = nil } }
            VStack(spacing: 8) {
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(0.1, player.duration))
                    .tint(.voice)
                HStack {
                    Text(Formatting.clock(player.currentTime)).monospacedDigit()
                    Spacer()
                    Text(Formatting.clock(player.duration)).monospacedDigit()
                }.font(.sora(.caption)).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button { player.seek(to: max(0, player.currentTime - 5)) } label: { Image(systemName: "gobackward.5").font(.display(.title2)) }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 56))
                }.tint(.voice)
                Button { player.seek(to: min(player.duration, player.currentTime + 5)) } label: { Image(systemName: "goforward.5").font(.display(.title2)) }
            }
            if let r = current.observedRange {
                Text("Notes reached: \(Pitch.noteName(Double(r.low))) to \(Pitch.noteName(Double(r.high))) · \(Formatting.rangeSpan(r.low, r.high) ?? 0) semitones")
                    .font(.sora(.footnote)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.pageBackground)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { library.toggleFavorite(current) } label: { Label(current.favorite ? "Remove favorite" : "Favorite", systemImage: current.favorite ? "star.slash" : "star") }
                    Button { newTitle = current.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    ShareLink(item: library.url(for: current), preview: SharePreview(current.title, image: Image(systemName: "waveform"))) {
                        Label("Share audio", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete take", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Rename take", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { library.rename(current, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this take?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { player.stop(); library.delete(current); dismiss() }
        } message: { Text("The audio and its pitch trail are removed from this device.") }
        .onAppear {
            session.stopEverything()
            do { try player.load(library.url(for: current)) } catch { loadError = "This take could not be opened." }
        }
        .onDisappear { player.stop() }
    }

    private func frameAt(_ t: Double) -> PitchFrame? {
        current.frames.last { $0.t <= t && t - $0.t < 0.3 }
    }
}
