import Foundation
import Observation

/// Saved recordings live in Application Support/Takes as .m4a files plus one JSON index.
/// Files are excluded from iCloud backup of nothing: they are the user's data and back up normally.
@MainActor
@Observable
final class TakeLibrary {
    private(set) var takes: [Take] = []
    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Take].self, from: data) else { return }
        // Drop entries whose audio file vanished so the list never shows a take that cannot play.
        takes = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(takes) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func url(for take: Take) -> URL { directory.appendingPathComponent(take.fileName) }

    /// A fresh destination for the recorder. The take is only indexed once `add` is called.
    func newRecordingURL() -> URL {
        directory.appendingPathComponent("take-\(UUID().uuidString).m4a")
    }

    func add(_ take: Take) {
        takes.insert(take, at: 0)
        persist()
    }

    func update(_ take: Take) {
        guard let i = takes.firstIndex(where: { $0.id == take.id }) else { return }
        takes[i] = take
        persist()
    }

    func toggleFavorite(_ take: Take) {
        var t = take; t.favorite.toggle(); update(t)
    }

    func rename(_ take: Take, to title: String) {
        var t = take
        t.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? take.title : title
        update(t)
    }

    /// Removes the take and its audio. Called only from an explicit user action in the app.
    func delete(_ take: Take) {
        takes.removeAll { $0.id == take.id }
        try? FileManager.default.removeItem(at: url(for: take))
        persist()
    }

    /// Discard a recording that was never saved (user cancelled the save sheet).
    func discardUnsaved(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    var totalSeconds: Double { takes.reduce(0) { $0 + $1.duration } }
}
