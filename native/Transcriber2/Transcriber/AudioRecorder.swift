import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var duration: TimeInterval = 0

    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
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
        let engine = AVAudioEngine()
        self.engine = engine
        return engine.inputNode.outputFormat(forBus: 0)
    }

    func start(at url: URL) throws {
        let engine = engine ?? AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        file = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            guard let copied = Self.copy(buffer) else { return }
            try? self?.file?.write(from: buffer)
            self?.onBuffer?(copied)
            let level = Self.rms(buffer)
            Task { @MainActor [weak self] in self?.level = level }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        startedAt = .now
        duration = 0
    }

    func stop() {
        if let startedAt {
            duration = Date.now.timeIntervalSince(startedAt)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            guard let source = buffer.floatChannelData?[channel], let destination = copy.floatChannelData?[channel] else {
                continue
            }
            destination.update(from: source, count: Int(buffer.frameLength))
        }
        return copy
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let values = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        return min(1, sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(values.count)) * 8)
    }
}
