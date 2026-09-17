import AVFoundation

/// Writes microphone buffers to an AAC file on a serial queue so the audio thread never blocks on disk.
final class TakeRecorder {
    let url: URL
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "live.singwell.recorder", qos: .userInitiated)
    private(set) var framesWritten: Int64 = 0
    private let sampleRate: Double

    init(url: URL, format: AVAudioFormat) throws {
        self.url = url
        self.sampleRate = format.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.monoCopy() else { return }
        queue.async { [weak self] in
            guard let self, let file = self.file else { return }
            do {
                try file.write(from: copy)
                self.framesWritten += Int64(copy.frameLength)
            } catch {
                // A failed write drops one buffer; the take keeps going.
            }
        }
    }

    /// Closes the file and returns the audio duration actually written, in seconds.
    func finish() -> Double {
        var seconds = 0.0
        queue.sync {
            file = nil
            seconds = Double(framesWritten) / sampleRate
        }
        return seconds
    }
}

extension AVAudioPCMBuffer {
    /// First channel only, as a fresh Float32 buffer the recorder can own.
    func monoCopy() -> AVAudioPCMBuffer? {
        guard let src = floatChannelData,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength) else { return nil }
        out.frameLength = frameLength
        out.floatChannelData![0].update(from: src[0], count: Int(frameLength))
        return out
    }
}
