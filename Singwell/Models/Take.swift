import Foundation

/// One detected pitch at a moment in time. `t` is seconds; absolute for the live
/// trail, relative to the start of the take once saved.
struct PitchFrame: Codable, Equatable, Sendable {
    var t: Double
    var midi: Double?
    var target: Double?
}

/// Where a take was recorded, so the library can badge it.
enum TakeContext: String, Codable, CaseIterable, Sendable {
    case sing, warmup, quest, daily
    var label: String {
        switch self {
        case .sing: return "Free sing"
        case .warmup: return "Warm-up"
        case .quest: return "Pitch Quest"
        case .daily: return "Daily practice"
        }
    }
    var symbol: String {
        switch self {
        case .sing: return "music.note"
        case .warmup: return "list.bullet"
        case .quest: return "target"
        case .daily: return "flame"
        }
    }
}

/// A saved recording plus the pitch trail captured alongside it.
struct Take: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var fileName: String
    var frames: [PitchFrame]
    var context: TakeContext
    var favorite: Bool
    var notes: String

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), duration: Double, fileName: String,
         frames: [PitchFrame], context: TakeContext, favorite: Bool = false, notes: String = "") {
        self.id = id; self.title = title; self.createdAt = createdAt; self.duration = duration
        self.fileName = fileName; self.frames = frames; self.context = context
        self.favorite = favorite; self.notes = notes
    }

    /// Lowest and highest sustained-looking notes in the take, for the list row.
    var observedRange: (low: Int, high: Int)? {
        let notes = frames.compactMap { $0.midi }.map { Int($0.rounded()) }
        guard let low = notes.min(), let high = notes.max() else { return nil }
        return (low, high)
    }

    static func defaultTitle(for date: Date = Date(), context: TakeContext) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "\(context == .sing ? "Take" : context.label) · \(f.string(from: date))"
    }
}
