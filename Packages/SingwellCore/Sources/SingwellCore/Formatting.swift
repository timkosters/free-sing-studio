import Foundation

public enum Formatting {
    /// "2:05" for 125 seconds.
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// "12 min" style label; under a minute shows seconds so early practice is visible.
    public static func minutes(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s < 60 { return "\(s) sec" }
        let minutes = Int((Double(s) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Semitone span between two notes, or nil when the range is not yet known.
    public static func rangeSpan(_ low: Int?, _ high: Int?) -> Int? {
        guard let low, let high else { return nil }
        return high - low
    }
}
