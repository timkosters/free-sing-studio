import Foundation

/// Cross-device sync of the practice calendar. Pure merge rules shared with the web app:
/// practice only accumulates, so the larger value per field per day wins. Commutative,
/// idempotent, and safe to run in either direction without trusting any clock.
public enum Sync {
    /// One row of the `practice_days` table.
    public struct Row: Codable, Equatable, Sendable {
        public var day: String
        public var seconds: Int
        public var steps: Int
        public var completed: Bool
        public init(day: String, seconds: Int, steps: Int, completed: Bool) {
            self.day = day; self.seconds = seconds; self.steps = steps; self.completed = completed
        }
    }

    static let keyPattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")

    /// Fold server rows into a log. Rows are remote data, so anything malformed is dropped.
    public static func log(from rows: [Row]) -> Daily.Log {
        var log = Daily.Log()
        for row in rows {
            let key = String(row.day.prefix(10))
            guard keyPattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil else { continue }
            var day = Daily.Day()
            day.seconds = Double(max(0, row.seconds))
            day.steps = max(0, row.steps)
            day.completed = row.completed
            log.days[key] = day
        }
        return log
    }

    /// The rows to write back for a merged calendar.
    public static func rows(from log: Daily.Log) -> [Row] {
        log.days.keys.sorted().map { key in
            let d = log.days[key]!
            return Row(day: key, seconds: Int(d.seconds.rounded(.down)), steps: d.steps, completed: d.completed)
        }
    }

    /// Merge two calendars by taking the larger value per field and OR-ing completion.
    public static func merge(_ a: Daily.Log, _ b: Daily.Log) -> Daily.Log {
        var out = a
        for (key, right) in b.days {
            if let left = out.days[key] {
                var d = Daily.Day()
                d.seconds = max(left.seconds, right.seconds)
                d.steps = max(left.steps, right.steps)
                d.completed = left.completed || right.completed
                out.days[key] = d
            } else {
                out.days[key] = right
            }
        }
        out.updated = max(a.updated, b.updated)
        return out
    }

    /// True when the merge would change what the server already holds.
    public static func needsPush(remote: Daily.Log, merged: Daily.Log) -> Bool {
        if remote.days.count != merged.days.count { return true }
        for (key, m) in merged.days {
            guard let r = remote.days[key] else { return true }
            if r.seconds != m.seconds || r.steps != m.steps || r.completed != m.completed { return true }
        }
        return false
    }

    /// Good enough to catch a typo before spending a send on it.
    public static func looksLikeEmail(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespaces)
        return t.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$", options: .regularExpression) != nil
    }

    /// Translate raw auth errors into something a singer can act on.
    public static func authMessage(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "Something went wrong. Please try again." }
        let text = raw.lowercased()
        if text.contains("offline") || text.contains("network") || text.contains("could not connect") || text.contains("failed to fetch") {
            return "Could not reach the server. Check your connection and try again."
        }
        if text.contains("rate limit") || text.contains("too many") { return "Too many sign-in emails requested. Wait a minute, then try again." }
        if text.contains("expired") { return "That link has expired. Send a new one." }
        if text.contains("invalid") && text.contains("token") { return "That link did not match. Request a new one." }
        return raw
    }
}
