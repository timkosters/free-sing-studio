import Foundation

/// Pitch maths shared by the live view, warm-ups and the quest.
public enum Pitch {
    /// Note names use the sharp symbol so labels stay compact on the piano roll.
    public static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    public static func midiToFrequency(_ midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    public static func frequencyToMidi(_ frequency: Double) -> Double {
        69 + 12 * log2(frequency / 440)
    }

    /// "D♯4" for MIDI 63. Rounds to the nearest semitone first.
    public static func noteName(_ midi: Double) -> String {
        let n = Int(midi.rounded())
        let index = ((n % 12) + 12) % 12
        let octave = Int((Double(n) / 12).rounded(.down)) - 1
        return noteNames[index] + String(octave)
    }

    /// Letter without the octave, for compact key labels.
    public static func pitchClass(_ midi: Int) -> String {
        noteNames[((midi % 12) + 12) % 12]
    }

    public static func isBlackKey(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
    }

    public struct Detection: Equatable, Sendable {
        public var frequency: Double
        public var confidence: Double
        public init(frequency: Double, confidence: Double) {
            self.frequency = frequency
            self.confidence = confidence
        }
    }

    /// Lowest fundamental treated as a voice: just under A1. Below is rumble, not singing.
    public static let minHz = 54.0
    /// Highest fundamental treated as a voice, comfortably above any sung note.
    public static let maxHz = 2200.0

    /// Flatten a slow amplitude envelope while leaving the pitch periodicity alone.
    /// A lip trill flutters loudness at roughly 20–35 Hz; on low notes that flutter beats the
    /// vocal period and YIN reports a note two octaves down. Dividing by a short running
    /// magnitude equalises loudness so only the vocal period is left. Vibrato passes through.
    static func flattenEnvelope(_ buffer: [Float], sampleRate: Double) -> [Float] {
        let window = max(8, Int(sampleRate / 500))
        var magnitude = [Float](repeating: 0, count: buffer.count)
        var sum: Float = 0
        for i in buffer.indices {
            sum += abs(buffer[i])
            if i >= window { sum -= abs(buffer[i - window]) }
            magnitude[i] = sum / Float(min(i + 1, window))
        }
        let peak = magnitude.max() ?? 0
        let floor = peak * 0.15
        var out = [Float](repeating: 0, count: buffer.count)
        for i in buffer.indices { out[i] = buffer[i] / max(magnitude[i], floor) }
        return out
    }

    /// YIN with cumulative mean normalisation and parabolic interpolation.
    /// Returns nil for silence, noise, or anything outside the voice band.
    public static func detect(_ input: [Float], sampleRate inputRate: Double) -> Detection? {
        guard inputRate.isFinite, inputRate > 0, input.count >= 1024 else { return nil }
        var buffer = input
        var sampleRate = inputRate
        // Average blocks before decimation at high device sample rates.
        let stride = max(1, Int(sampleRate / 48000))
        if stride > 1 {
            let reducedCount = buffer.count / stride
            var reduced = [Float](repeating: 0, count: reducedCount)
            for i in 0..<reducedCount {
                var sum: Float = 0
                for j in 0..<stride { sum += buffer[i * stride + j] }
                reduced[i] = sum / Float(stride)
            }
            buffer = reduced
            sampleRate /= Double(stride)
        }
        let count = buffer.count
        var mean: Double = 0
        for v in buffer { mean += Double(v) }
        mean /= Double(count)
        var power: Double = 0
        for v in buffer { let d = Double(v) - mean; power += d * d }
        // Judge silence on the original signal: flattening normalises loudness away.
        if (power / Double(count)).squareRoot() < 0.008 { return nil }
        buffer = flattenEnvelope(buffer, sampleRate: sampleRate)

        let maxLag = min(Int(sampleRate / minHz), count / 2 - 1)
        let minLag = max(2, Int(sampleRate / maxHz))
        guard maxLag > minLag + 1 else { return nil }
        let size = count - maxLag
        var diff = [Double](repeating: 1, count: maxLag + 1)
        var running: Double = 0
        buffer.withUnsafeBufferPointer { p in
            for lag in 1...maxLag {
                var sum: Float = 0
                var j = 0
                while j < size {
                    let d = p[j] - p[j + lag]
                    sum += d * d
                    j += 1
                }
                running += Double(sum)
                diff[lag] = running == 0 ? 1 : (Double(sum) * Double(lag)) / running
            }
        }
        var lag = minLag
        while lag < maxLag {
            if diff[lag] < 0.15 {
                while lag + 1 < maxLag && diff[lag + 1] < diff[lag] { lag += 1 }
                break
            }
            lag += 1
        }
        if lag >= maxLag || diff[lag] > 0.15 { return nil }
        let a = diff[lag - 1], b = diff[lag], c = diff[lag + 1]
        let den = a - 2 * b + c
        let refined = Double(lag) + (den == 0 ? 0 : (a - c) / (2 * den))
        let frequency = sampleRate / refined
        guard frequency >= minHz, frequency <= maxHz else { return nil }
        return Detection(frequency: frequency, confidence: 1 - b)
    }

    /// Keep at least C2–C6 visible and expand by octaves for lower or higher singing.
    public static func chartBounds(_ notes: [Double]) -> (low: Int, high: Int) {
        let valid = notes.filter { $0.isFinite }
        let lowest = min(36, valid.min() ?? 36)
        let highest = max(84, valid.max() ?? 84)
        let low = max(23, min(35, Int((lowest / 12).rounded(.down)) * 12 - 1))
        let high = min(97, max(85, Int((highest / 12).rounded(.up)) * 12 + 1))
        return (low, high)
    }

    /// Signed cents from the nearest semitone, rounded, or nil when silent.
    public static func cents(_ midi: Double?) -> Int? {
        guard let midi else { return nil }
        return Int(((midi - midi.rounded()) * 100).rounded())
    }
}
