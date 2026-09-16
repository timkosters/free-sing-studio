import AVFoundation
import SingwellCore

/// A struck, decaying additive tone generated locally: a piano-like reference note,
/// plus a short click for the metronome. Runs inside an AVAudioSourceNode.
final class ToneSynth {
    private struct Voice {
        var frequencies: [Double]
        var peaks: [Double]
        var phases: [Double]
        var startSample: Int64
        var durationSamples: Int64
    }

    private let lock = NSLock()
    private var pending: [Voice] = []
    private var voices: [Voice] = []
    private var sampleTime: Int64 = 0
    private(set) var sampleRate: Double = 48000
    private(set) var node: AVAudioSourceNode!

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            self.render(frameCount: Int(frameCount), list: audioBufferList)
            return noErr
        }
    }

    /// Seconds of audio rendered so far. Schedules are expressed on this clock.
    var currentTime: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(sampleTime) / sampleRate
    }

    /// Play a reference note. `time` is on the synth clock; nil means now.
    func play(midi: Int, at time: Double? = nil, duration: Double) {
        let f = Pitch.midiToFrequency(Double(midi))
        enqueue(frequencies: [f, f * 2, f * 3], peaks: [0.13, 0.035, 0.012], at: time, duration: duration)
    }

    /// Metronome click. Accented beats are pitched higher.
    func click(accent: Bool, at time: Double? = nil) {
        enqueue(frequencies: [accent ? 1500 : 1000], peaks: [0.045], at: time, duration: 0.035)
    }

    /// A short rising two-note flourish for a completed quest.
    func fanfare(midi: Int) {
        let now = currentTime
        play(midi: midi, at: now, duration: 0.5)
        play(midi: midi + 7, at: now + 0.18, duration: 0.9)
    }

    private func enqueue(frequencies: [Double], peaks: [Double], at time: Double?, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        let start = time.map { Int64(max(0, $0) * sampleRate) } ?? sampleTime
        pending.append(Voice(frequencies: frequencies, peaks: peaks, phases: Array(repeating: 0, count: frequencies.count),
                             startSample: max(start, sampleTime), durationSamples: Int64(duration * sampleRate)))
    }

    func stopAll() {
        lock.lock(); defer { lock.unlock() }
        pending.removeAll()
        voices.removeAll()
    }

    private func render(frameCount: Int, list: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        // Pull newly scheduled voices. tryLock keeps the render thread from blocking on the UI thread.
        if lock.try() {
            if !pending.isEmpty { voices.append(contentsOf: pending); pending.removeAll() }
            lock.unlock()
        }
        let attack = Int64(0.005 * sampleRate)
        for i in 0..<frameCount {
            let t = sampleTime + Int64(i)
            var sample: Double = 0
            for v in voices.indices {
                let voice = voices[v]
                let rel = t - voice.startSample
                if rel < 0 || rel >= voice.durationSamples { continue }
                for p in voice.frequencies.indices {
                    let peak = voice.peaks[p]
                    let env: Double
                    if rel < attack {
                        env = peak * Double(rel) / Double(attack)
                    } else {
                        let progress = Double(rel - attack) / Double(max(1, voice.durationSamples - attack))
                        env = peak * pow(0.0001 / peak, progress)
                    }
                    sample += env * sin(voices[v].phases[p])
                    voices[v].phases[p] += 2 * .pi * voice.frequencies[p] / sampleRate
                    if voices[v].phases[p] > 2 * .pi { voices[v].phases[p] -= 2 * .pi }
                }
            }
            out[i] = Float(max(-1, min(1, sample)))
        }
        // Copy mono into any extra channels the engine asked for.
        for extra in buffers.dropFirst() {
            if let dst = extra.mData?.assumingMemoryBound(to: Float.self) {
                dst.update(from: out, count: frameCount)
            }
        }
        let end = sampleTime + Int64(frameCount)
        voices.removeAll { $0.startSample + $0.durationSamples <= end }
        if lock.try() { sampleTime = end; lock.unlock() } else { sampleTime = end }
    }
}
