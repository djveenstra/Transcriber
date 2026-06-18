import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var activeMicrophoneName = MicrophoneRecordingRoute.systemDefaultInputName
    @Published private(set) var microphoneFallbackNotice: String?

    var onBuffer: (@Sendable (CapturedAudioChunk) -> Void)?
    var levelUpdates: AnyPublisher<Float, Never> { $level.eraseToAnyPublisher() }

    private var engine: AVAudioEngine?
    private var fileWriter: AudioFileWriter?
    private var startedAt: Date?

    var elapsedDuration: TimeInterval {
        startedAt.map { Date.now.timeIntervalSince($0) } ?? duration
    }

    func requestPermission() async -> Bool {
#if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
#else
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
#endif
    }

    func prepareForRecording() throws -> AVAudioFormat {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
#endif
        let route = MicrophoneService.shared.applyPreferredInputForRecording()
        activeMicrophoneName = route.activeDisplayName
        microphoneFallbackNotice = route.notice
        let engine = AVAudioEngine()
        self.engine = engine
        return engine.inputNode.outputFormat(forBus: 0)
    }

    func start(at url: URL) throws {
        try startEngine(writingTo: url)
    }

    func startMetering() throws {
        _ = try prepareForRecording()
        try startEngine(writingTo: nil)
    }

    private func startEngine(writingTo url: URL?) throws {
        let engine = engine ?? AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let writer = try url.map { try AudioFileWriter(url: $0, settings: format.settings) }
        fileWriter = writer

        let onBuffer = onBuffer
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            if writer != nil || onBuffer != nil, let chunk = CapturedAudioChunk(copying: buffer) {
                writer?.write(chunk)
                onBuffer?(chunk)
            }
            let level = Self.rms(buffer)
            Task { @MainActor [weak self] in self?.level = level }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        startedAt = .now
        duration = 0
    }

    /// Stops recording and returns the first write error encountered during the
    /// session (if any). A non-nil error means the audio file may be incomplete.
    @discardableResult
    func stop() -> (any Error)? {
        if let startedAt {
            duration = Date.now.timeIntervalSince(startedAt)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        var writeError: (any Error)?
        do {
            try fileWriter?.close()
        } catch {
            writeError = error
        }
        fileWriter = nil
        engine = nil
        level = 0
        activeMicrophoneName = MicrophoneRecordingRoute.systemDefaultInputName
        microphoneFallbackNotice = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
        return writeError
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let values = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        return AudioLevelMeter.normalizedRMS(values)
    }
}

enum AudioLevelMeter {
    static func normalizedRMS<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
        var total: Float = 0
        var count = 0
        for sample in samples {
            total += sample * sample
            count += 1
        }
        guard count > 0 else { return 0 }
        return normalizedLevel(sqrt(total / Float(count)) * 8)
    }

    static func normalizedLevel(_ level: Float) -> Float {
        guard level.isFinite else { return 0 }
        return min(1, max(0, level))
    }
}
