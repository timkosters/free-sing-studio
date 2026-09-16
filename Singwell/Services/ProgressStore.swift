import Foundation
import Observation
import SingwellCore

/// Practice history, quest bests and the daily streak log. Written synchronously on
/// every change so a backgrounded or killed app never loses the last update.
@MainActor
@Observable
final class ProgressStore {
    private let defaults = UserDefaults.standard
    private static let historyKey = "singwell-history-v1"
    private static let dailyKey = "singwell-daily-v1"

    private(set) var history: History.Record
    private(set) var daily: Daily.Log

    init() {
        history = History.parse(UserDefaults.standard.data(forKey: Self.historyKey))
        daily = Daily.parse(UserDefaults.standard.data(forKey: Self.dailyKey))
    }

    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    func update(_ change: (History.Record) -> History.Record) {
        let next = change(history)
        guard next != history else { return }
        history = next
        defaults.set(History.serialize(next), forKey: Self.historyKey)
    }

    func updateDaily(_ change: (Daily.Log) -> Daily.Log) {
        let next = change(daily)
        guard next != daily else { return }
        daily = next
        defaults.set(Daily.serialize(next), forKey: Self.dailyKey)
    }

    func addPractice(seconds: Double) { update { $0.addingPractice(seconds: seconds, now: now) } }
    func recordSession() { update { $0.recordingSession(now: now) } }
    func recordRange(low: Int?, high: Int?) { update { $0.recordingRange(low: low, high: high, now: now) } }
    func recordQuest(_ summary: Quest.Summary) { update { $0.recordingQuest(summary, now: now) } }
    func logStep(seconds: Double) { updateDaily { $0.loggingStep(seconds: seconds, key: Daily.dayKey(), now: now) } }
    func logRoutineComplete() { updateDaily { $0.loggingComplete(key: Daily.dayKey(), now: now) } }

    func clearAll() {
        history = History.Record()
        daily = Daily.Log()
        defaults.removeObject(forKey: Self.historyKey)
        defaults.removeObject(forKey: Self.dailyKey)
    }

    var streak: Int { daily.streak() }
    var practisedToday: Bool { daily.days[Daily.dayKey()]?.practised ?? false }
    var completedToday: Bool { daily.days[Daily.dayKey()]?.completed ?? false }
}
