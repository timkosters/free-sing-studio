import AVFoundation
import SingwellCore

/// One pitch estimate from the microphone.
struct PitchReading: Sendable {
    var midi: Double?
    var level: Double
    /// Monotonic seconds (system uptime) when the buffer arrived.
    var time: Double
}

enum AudioEngineError: LocalizedError {
    case permissionDenied
    case noInput
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access is off. Allow it in Settings › Singwell to see your pitch."
        case .noInput: return "No microphone input is available right now."
        case .startFailed(let s): return "Audio could not start: \(s)"
        }
    }
}

/// Owns the AVAudioEngine: microphone in, reference tones out, optional file recording.
/// All public methods are called from the main actor; the tap runs on the audio thread and
/// hands results back through `onReading`.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private(set) var synth: ToneSynth
    private var tapInstalled = false
    private var analysisWindow: [Float] = []
    private var windowSize = 4096
    private var recorder: TakeRecorder?
    private let recorderLock = NSLock()
    /// All pitch analysis happens here, never on the audio render thread.
    private let analysisQueue = DispatchQueue(label: "live.singwell.analysis", qos: .userInteractive)
    private(set) var inputSampleRate: Double = 48000
    var onReading: (@MainActor (PitchReading) -> Void)?
    private var interruptionObserver: NSObjectProtocol?
    var onInterruption: (@MainActor () -> Void)?

    init() {
        let session = AVAudioSession.sharedInstance()
        synth = ToneSynth(sampleRate: session.sampleRate > 0 ? session.sampleRate : 48000)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            guard let self, let handler = self.onInterruption else { return }
            Task { @MainActor in handler() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    var isRunning: Bool { engine.isRunning }
    var isListening: Bool { tapInstalled }

    static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Output only: reference tones and playback, no microphone. Safe to call repeatedly.
    func startOutput() throws {
        try configureSession(record: false)
        try startEngineIfNeeded()
    }

    /// Microphone plus output. Requests nothing itself; call `requestMicrophonePermission` first.
    func startListening() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else { throw AudioEngineError.permissionDenied }
        try configureSession(record: true)
        if tapInstalled { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioEngineError.noInput }
        let rate = format.sampleRate
        analysisQueue.sync {
            inputSampleRate = rate
            windowSize = rate > 48000 ? 8192 : 4096
            analysisWindow = []
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // Recording and analysis both take a copy; the render thread does nothing else.
            self.recorderLock.lock()
            let rec = self.recorder
            self.recorderLock.unlock()
            rec?.append(buffer)
            guard let copy = buffer.monoCopy() else { return }
            self.analysisQueue.async { self.consume(copy) }
        }
        tapInstalled = true
        try startEngineIfNeeded()
    }

    func stopListening() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        _ = stopRecording()
        try? configureSession(record: false)
    }

    func stopAll() {
        stopListening()
        synth.stopAll()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Recording

    func startRecording(to url: URL) throws {
        guard tapInstalled else { throw AudioEngineError.noInput }
        let format = engine.inputNode.outputFormat(forBus: 0)
        let rec = try TakeRecorder(url: url, format: format)
        recorderLock.lock(); recorder = rec; recorderLock.unlock()
    }

    /// Returns the seconds of audio written, or nil when nothing was recording.
    func stopRecording() -> Double? {
        recorderLock.lock()
        let rec = recorder
        recorder = nil
        recorderLock.unlock()
        return rec?.finish()
    }

    var isRecording: Bool {
        recorderLock.lock(); defer { recorderLock.unlock() }
        return recorder != nil
    }

    // MARK: Internals

    private func configureSession(record: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            if record {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true)
        } catch {
            throw AudioEngineError.startFailed(error.localizedDescription)
        }
        let rate = session.sampleRate
        if rate > 0, abs(rate - synth.sampleRate) > 1, !engine.isRunning {
            rebuildSynth(sampleRate: rate)
        }
    }

    private var synthAttached = false

    private func rebuildSynth(sampleRate: Double) {
        if synthAttached, let node = synth.node { engine.detach(node) }
        synthAttached = false
        synth = ToneSynth(sampleRate: sampleRate, startingAt: synth.currentTime)
    }

    private func startEngineIfNeeded() throws {
        if !synthAttached, let node = synth.node {
            engine.attach(node)
            let format = AVAudioFormat(standardFormatWithSampleRate: synth.sampleRate, channels: 1)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            synthAttached = true
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { throw AudioEngineError.startFailed(error.localizedDescription) }
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        analysisWindow.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        if analysisWindow.count > windowSize {
            analysisWindow.removeFirst(analysisWindow.count - windowSize)
        }
        guard analysisWindow.count >= windowSize else { return }
        var sum: Float = 0
        for v in analysisWindow { sum += v * v }
        let level = min(1, Double((sum / Float(windowSize)).squareRoot()) * 8)
        let detection = Pitch.detect(analysisWindow, sampleRate: inputSampleRate)
        let reading = PitchReading(midi: detection.map { Pitch.frequencyToMidi($0.frequency) },
                                   level: level, time: ProcessInfo.processInfo.systemUptime)
        guard let handler = onReading else { return }
        Task { @MainActor in handler(reading) }
    }
}
