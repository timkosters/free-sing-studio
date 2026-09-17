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

    private static let profileKey = "singwell-profile-v1"

    private(set) var history: History.Record
    private(set) var daily: Daily.Log
    /// The singer's own voice: range, break, songs. Synced with the web app when signed in.
    private(set) var profile: Profile
    private(set) var syncing = false
    private(set) var lastSyncError: String?
    private(set) var lastSyncedAt: Date?
    private var userID: UUID?
    private var pushTask: Task<Void, Never>?

    init() {
        history = History.parse(UserDefaults.standard.data(forKey: Self.historyKey))
        daily = Daily.parse(UserDefaults.standard.data(forKey: Self.dailyKey))
        profile = (UserDefaults.standard.data(forKey: Self.profileKey)).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
    }

    /// The routine with this singer's profile folded into the step wording.
    func routine(_ id: Daily.RoutineID) -> Daily.Routine {
        var r = Daily.routine(id)
        r.steps = profile.personalize(r.steps)
        return r
    }

    // MARK: Sync with the shared backend

    /// Called once a session exists: pull the server calendar and profile, merge, push back.
    func connect(userID: UUID) {
        self.userID = userID
        Task { await sync() }
    }

    func disconnect() {
        userID = nil
        pushTask?.cancel()
    }

    func sync() async {
        guard let userID, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let remote = try await Remote.fetchCalendar(userID: userID)
            let merged = Sync.merge(remote, daily)
            if merged != daily { daily = merged; defaults.set(Daily.serialize(merged), forKey: Self.dailyKey) }
            if Sync.needsPush(remote: remote, merged: merged) { try await Remote.pushCalendar(merged, userID: userID) }
            let remoteProfile = try await Remote.fetchProfile(userID: userID)
            if !remoteProfile.isEmpty { setProfile(remoteProfile, push: false) }
            else if !profile.isEmpty { try await Remote.saveProfile(profile, userID: userID) }
            lastSyncedAt = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = Sync.authMessage(error.localizedDescription)
        }
    }

    /// Debounced push after local changes so a routine does not hit the network per step.
    private func schedulePush() {
        guard userID != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, let userID = self.userID else { return }
            do { try await Remote.pushCalendar(self.daily, userID: userID); self.lastSyncedAt = Date() }
            catch { self.lastSyncError = Sync.authMessage(error.localizedDescription) }
        }
    }

    func setProfile(_ next: Profile, push: Bool = true) {
        profile = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.profileKey) }
        if push, let userID {
            Task { do { try await Remote.saveProfile(next, userID: userID) } catch { lastSyncError = Sync.authMessage(error.localizedDescription) } }
        }
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
        schedulePush()
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
        // Server copy is left alone on purpose: clearing this device must not erase the account.
    }

    var streak: Int { daily.streak() }
    var practisedToday: Bool { daily.days[Daily.dayKey()]?.practised ?? false }
    var completedToday: Bool { daily.days[Daily.dayKey()]?.completed ?? false }
}
