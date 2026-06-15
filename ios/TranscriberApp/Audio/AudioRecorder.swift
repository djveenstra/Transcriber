import AVFoundation
import Foundation

/// Records audio from the device microphone using AVAudioEngine.
/// Outputs 16kHz mono Float32 PCM — the format required by Whisper and diarization.
///
/// Dual output:
/// 1. Saves full audio to a .wav file (for diarization after recording ends)
/// 2. Delivers audio buffers to a callback in real-time (for streaming transcription)
class AudioRecorder: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var audioLevel: Float = 0.0  // 0.0 to 1.0, for waveform display
    @Published var recordingDuration: TimeInterval = 0.0

    /// Called with each audio buffer (~0.5s of 16kHz mono PCM Float32)
    var onAudioBuffer: (([Float]) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    /// The target format: 16kHz, mono, Float32
    private let targetSampleRate: Double = 16000.0
    private let targetChannels: AVAudioChannelCount = 1

    private var targetFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: targetSampleRate,
                      channels: targetChannels,
                      interleaved: false)!
    }

    // MARK: - Public API

    /// Request microphone permission. Must call before first recording.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording to the specified URL.
    /// Audio is saved as 16kHz mono WAV and also streamed via onAudioBuffer.
    func startRecording(to url: URL) throws {
        outputURL = url

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create the output audio file (16kHz mono WAV)
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: targetSampleRate,
                AVNumberOfChannelsKey: targetChannels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        // Create a converter from input format to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }

        // Install tap on input node
        // Buffer size: ~0.5 seconds of input audio
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.5)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, converter: converter)
        }

        // Start the engine
        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0

        // Update duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordingStartTime else { return }
            DispatchQueue.main.async {
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    /// Stop recording. Returns the URL of the saved .wav file.
    @discardableResult
    func stopRecording() -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        isRecording = false
        return outputURL
    }

    // MARK: - Private

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Calculate audio level (RMS) for visualization
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var rms: Float = 0
            for i in 0..<frameCount {
                rms += channelData[i] * channelData[i]
            }
            rms = sqrt(rms / Float(frameCount))
            let level = min(1.0, rms * 5.0)  // Scale up for visibility
            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }

        // Convert to target format (16kHz mono)
        let ratio = targetSampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                   frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Write to file
        try? audioFile?.write(from: outputBuffer)

        // Extract float samples and send to callback
        if let channelData = outputBuffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(start: channelData,
                                                     count: Int(outputBuffer.frameLength)))
            onAudioBuffer?(samples)
        }
    }

    enum RecorderError: LocalizedError {
        case converterCreationFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .converterCreationFailed: return "Failed to create audio format converter"
            case .permissionDenied: return "Microphone permission was denied"
            }
        }
    }
}
