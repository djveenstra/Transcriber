import AVFoundation
import Combine
import Foundation

enum RecordingInterruptionReason: String, Equatable, Sendable {
    case audioSessionInterrupted
    case mediaServicesReset

    var displayMessage: String {
        switch self {
        case .audioSessionInterrupted:
            "iOS interrupted audio capture"
        case .mediaServicesReset:
            "iOS reset audio services"
        }
    }
}

enum AudioRecorderSystemEvent: Equatable, Sendable {
    case routeChanged(activeMicrophoneName: String, notice: String?)
    case stoppedBySystem(reason: RecordingInterruptionReason, writeErrorMessage: String?)
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var activeMicrophoneName = MicrophoneRecordingRoute.systemDefaultInputName
    @Published private(set) var microphoneFallbackNotice: String?

    var onBuffer: (@Sendable (CapturedAudioChunk) -> Void)?
    var onSystemEvent: (@Sendable (AudioRecorderSystemEvent) -> Void)?
    var levelUpdates: AnyPublisher<Float, Never> { $level.eraseToAnyPublisher() }

    private var engine: AVAudioEngine?
    private var fileWriter: AudioFileWriter?
    private var startedAt: Date?
#if os(iOS)
    private var notificationObservers: [NSObjectProtocol] = []
#endif

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
#if os(iOS)
        registerAudioSessionObservers()
#endif
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
        removeAudioSessionObservers()
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
        return writeError
    }

#if os(iOS)
    private func registerAudioSessionObservers() {
        removeAudioSessionObservers()
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleRouteChange(notification)
                }
            },
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopAfterSystemEvent(.mediaServicesReset)
                }
            },
        ]
    }

    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers = []
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            stopAfterSystemEvent(.audioSessionInterrupted)
        case .ended:
            break
        @unknown default:
            stopAfterSystemEvent(.audioSessionInterrupted)
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard engine != nil else { return }
        let route = MicrophoneService.shared.applyPreferredInputForRecording()
        activeMicrophoneName = route.activeDisplayName
        microphoneFallbackNotice = route.notice
        onSystemEvent?(.routeChanged(
            activeMicrophoneName: route.activeDisplayName,
            notice: route.notice
        ))
    }

    private func stopAfterSystemEvent(_ reason: RecordingInterruptionReason) {
        guard engine != nil else { return }
        let writeErrorMessage = stop()?.localizedDescription
        onSystemEvent?(.stoppedBySystem(reason: reason, writeErrorMessage: writeErrorMessage))
    }
#endif

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
