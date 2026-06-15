import AVFoundation
import Foundation
import WhisperKit

protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func beginLive(onSegment: @escaping @Sendable (TranscriptionSegment) -> Void)
    func prepareLive(audioFormat: AVAudioFormat) async throws
    func append(_ buffer: AVAudioPCMBuffer) async throws
    func finishLive() async throws
    func transcribeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment]
    func currentLoadedModelID() -> String?
    func unload() async
}

actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var loadedModelID: String?
    private var onSegment: (@Sendable (TranscriptionSegment) -> Void)?
    private var liveSamples: [Float] = []
    private var nextLiveUpdateSample = WhisperKit.sampleRate * 2
    private var liveReady = false
    private var inferenceInProgress = false
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare() async throws {
        _ = try await model()
    }

    func beginLive(onSegment: @escaping @Sendable (TranscriptionSegment) -> Void) {
        self.onSegment = onSegment
        liveSamples = []
        nextLiveUpdateSample = WhisperKit.sampleRate * 2
        liveReady = false
    }

    func prepareLive(audioFormat: AVAudioFormat) async throws {
        _ = audioFormat
        _ = try await model()
        liveReady = true
        try await publishLiveSnapshot()
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        guard let resampled = AudioProcessor.resampleAudio(
            fromBuffer: buffer,
            toSampleRate: Double(WhisperKit.sampleRate),
            channelCount: 1
        ) else { return }
        liveSamples.append(contentsOf: AudioProcessor.convertBufferToArray(buffer: resampled))

        guard liveReady, liveSamples.count >= nextLiveUpdateSample else { return }
        nextLiveUpdateSample = liveSamples.count + WhisperKit.sampleRate * 3
        try await publishLiveSnapshot()
    }

    func finishLive() async throws {
        await acquireInference()
        releaseInference()
        onSegment = nil
        liveSamples = []
        liveReady = false
    }

    func transcribeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
        await acquireInference()
        defer { releaseInference() }
        let duration = (try? AVAudioFile(forReading: url)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 30
        let estimatedWindows = max(1, Int(ceil(duration / 30)))
        let results = try await model().transcribe(
            audioPath: url.path,
            decodeOptions: Self.decodingOptions,
            callback: { update in
                progress(min(0.99, Double(update.windowId + 1) / Double(estimatedWindows)))
                return true
            }
        )
        progress(1)
        return Self.convert(results)
    }

    func currentLoadedModelID() -> String? {
        loadedModelID
    }

    func unload() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
        loadedModelID = nil
    }

    private func publishLiveSnapshot() async throws {
        guard !liveSamples.isEmpty, let onSegment else { return }
        await acquireInference()
        defer { releaseInference() }
        let snapshot = liveSamples
        let results = try await model().transcribe(
            audioArray: snapshot,
            decodeOptions: Self.liveDecodingOptions
        )
        let segments = Self.convert(results)
        guard let first = segments.first, let last = segments.last else { return }
        onSegment(
            TranscriptionSegment(
                startMs: first.startMs,
                endMs: last.endMs,
                text: segments.map(\.text).joined(separator: " ")
            )
        )
    }

    private func model() async throws -> WhisperKit {
        let selectedModel = WhisperModelChoice.allowedID(
            UserDefaults.standard.string(forKey: "whisperModel")
        )
        UserDefaults.standard.set(selectedModel, forKey: "whisperModel")
        if loadedModelID != selectedModel {
            whisperKit = nil
            loadedModelID = nil
        }
        if let whisperKit { return whisperKit }

        let config = WhisperKitConfig(
            model: selectedModel,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        let created = try await WhisperKit(config)
        whisperKit = created
        loadedModelID = selectedModel
        return created
    }

    private static let decodingOptions = DecodingOptions(
        language: "en",
        wordTimestamps: true,
        concurrentWorkerCount: 1,
        chunkingStrategy: .vad
    )

    private static let liveDecodingOptions = DecodingOptions(
        language: "en",
        wordTimestamps: true,
        concurrentWorkerCount: 1,
        chunkingStrategy: .vad
    )

    private func acquireInference() async {
        if !inferenceInProgress {
            inferenceInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            inferenceWaiters.append(continuation)
        }
    }

    private func releaseInference() {
        guard !inferenceWaiters.isEmpty else {
            inferenceInProgress = false
            return
        }
        inferenceWaiters.removeFirst().resume()
    }

    private static func convert(_ results: [TranscriptionResult]) -> [TranscriptionSegment] {
        results.flatMap { result in
            result.segments.flatMap { segment -> [TranscriptionSegment] in
                if let words = segment.words, !words.isEmpty {
                    return words.compactMap { word in
                        let text = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        return TranscriptionSegment(
                            startMs: Int(word.start * 1_000),
                            endMs: max(Int(word.start * 1_000) + 1, Int(word.end * 1_000)),
                            text: text
                        )
                    }
                }
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return [] }
                return [
                    TranscriptionSegment(
                        startMs: Int(segment.start * 1_000),
                        endMs: max(Int(segment.start * 1_000) + 1, Int(segment.end * 1_000)),
                        text: text
                    )
                ]
            }
        }
    }
}
