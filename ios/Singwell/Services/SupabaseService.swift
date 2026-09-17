import Foundation
import Supabase
import SingwellCore

/// One client for the backend the web app already uses: the same Supabase project, tables
/// and accounts, so a singer who signs in on either surface sees one streak and one profile.
enum Backend {
    static let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "")
    static let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
    static var configured: Bool { url != nil && !anonKey.isEmpty }
    /// Where a sign-in email's link lands: straight back into this app.
    static let redirect = URL(string: "singwell://auth-callback")!

    static let client: SupabaseClient? = {
        guard let url, !anonKey.isEmpty else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey,
                              options: .init(auth: .init(redirectToURL: redirect, flowType: .implicit)))
    }()
}

/// Wire shape of `practice_days` including the owner column.
struct PracticeDayWire: Codable {
    var user_id: UUID
    var day: String
    var seconds: Int
    var steps: Int
    var completed: Bool
}

/// Wire shape of `singer_profile` including the owner column.
struct ProfileWire: Codable {
    var user_id: UUID
    var low_note: Int?
    var high_note: Int?
    var break_low: Int?
    var break_high: Int?
    var songs: [String]
    var hard_line: String?
}

/// Thin, typed calls against the shared tables. Everything else (merge rules, personalization)
/// is pure and lives in SingwellCore so both apps agree on it.
enum Remote {
    static func fetchCalendar(userID: UUID) async throws -> Daily.Log {
        guard let client = Backend.client else { return Daily.Log() }
        let rows: [Sync.Row] = try await client.from("practice_days")
            .select("day, seconds, steps, completed").eq("user_id", value: userID.uuidString)
            .execute().value
        return Sync.log(from: rows)
    }

    static func pushCalendar(_ log: Daily.Log, userID: UUID) async throws {
        guard let client = Backend.client else { return }
        let wire = Sync.rows(from: log).map { PracticeDayWire(user_id: userID, day: $0.day, seconds: $0.seconds, steps: $0.steps, completed: $0.completed) }
        guard !wire.isEmpty else { return }
        try await client.from("practice_days").upsert(wire, onConflict: "user_id,day").execute()
    }

    static func fetchProfile(userID: UUID) async throws -> Profile {
        guard let client = Backend.client else { return Profile() }
        let rows: [Profile.Row] = try await client.from("singer_profile")
            .select("low_note, high_note, break_low, break_high, songs, hard_line")
            .eq("user_id", value: userID.uuidString).limit(1).execute().value
        return rows.first.map { Profile(row: $0) } ?? Profile()
    }

    static func saveProfile(_ profile: Profile, userID: UUID) async throws {
        guard let client = Backend.client else { return }
        let r = profile.row
        let wire = ProfileWire(user_id: userID, low_note: r.low_note, high_note: r.high_note, break_low: r.break_low,
                               break_high: r.break_high, songs: r.songs, hard_line: r.hard_line)
        try await client.from("singer_profile").upsert(wire, onConflict: "user_id").execute()
    }
}
