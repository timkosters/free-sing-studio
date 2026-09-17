import Foundation

/// Synthetic voice for the labelled demo mode. Deterministic in time, never touches the microphone.
public enum Demo {
    public struct Sample: Equatable, Sendable {
        public var midi: Double?
        public var level: Double
        public init(midi: Double?, level: Double) { self.midi = midi; self.level = level }
    }

    /// Breath gap at the start of every phrase, in seconds.
    public static let breath = 0.3
    /// Seconds it takes the synthetic voice to settle onto a target after the breath.
    public static let settle = 0.45

    /// A pitch that breathes, scoops up to the target, settles and sustains with light vibrato.
    /// Targets whose semitone is divisible by three overshoot and correct first.
    public static func voice(local: Double, target: Double, global: Double? = nil) -> Sample {
        let g = global ?? local
        guard local.isFinite, local >= breath else { return Sample(midi: nil, level: 0.05) }
        let t = local - breath
        let wobbly = Int(target.rounded()) % 3 == 0
        var offset = -1.4 * exp(-t / (settle / 3))
        if wobbly && t < 1.1 {
            offset += 1.2 * max(0, 1 - exp(-t / 0.08)) * exp(-max(0, t - 0.5) / 0.14)
        }
        let vibrato = 0.08 * sin(2 * .pi * 5.4 * g) * min(1, t / 0.6)
        let drift = 0.03 * sin(g * 0.7)
        return Sample(midi: target + offset + vibrato + drift,
                      level: 0.45 + 0.1 * sin(2 * .pi * 5.4 * g) + 0.15 * min(1, t / 0.4))
    }

    static let melody: [Double] = [60, 62, 64, 65, 67, 65, 64, 62, 60, 64, 67, 72, 67, 64, 60, 55]
    public static let melodyNoteSeconds = 1.3

    public static func melody(at t: Double) -> (target: Double, local: Double) {
        let time = t.isFinite && t > 0 ? t : 0
        let index = Int((time / melodyNoteSeconds).rounded(.down)) % melody.count
        return (melody[index], time.truncatingRemainder(dividingBy: melodyNoteSeconds))
    }

    /// Free-singing demo: wander through the melody with the synthetic voice.
    public static func freeSample(at t: Double) -> Sample {
        let (target, local) = melody(at: t)
        return voice(local: local, target: target, global: t)
    }
}
