@preconcurrency import AVFoundation
import Foundation
import WhisperKit

protocol TranscriptionEngine: Actor {
    func prepare() async throws
    func beginLive(onSegment: @escaping @Sendable (TranscriptionSegment) -> Void)
    func prepareLive(audioFormat: AVAudioFormat) async throws
    func append(_ chunk: CapturedAudioChunk) async throws
    func finishLive() async throws
    func transcribeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment]
    func currentLoadedModelID() -> String?
    func unload() async
}

actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    /// Rolling live-window bounds: grow up to `liveMaxSamples`, then discard
    /// `liveDiscardSamples` from the front to fall back to `liveRetainSamples`.
    /// Not private: exposed so unit tests can verify the window-trimming math.
    static let liveRetainSamples = WhisperKit.sampleRate * 30
    static let liveMaxSamples = WhisperKit.sampleRate * 45
    static let liveDiscardSamples = WhisperKit.sampleRate * 15

    private var whisperKit: WhisperKit?
    private var loadedModelID: String?
    private var onSegment: (@Sendable (TranscriptionSegment) -> Void)?
    private var liveSamples: [Float] = []
    private var totalAppendedSamples = 0
    private var nextLiveUpdateSample = WhisperKit.sampleRate * 2
    /// Number of samples discarded from the front of `liveSamples` so far. Used to
    /// convert window-relative Whisper timestamps back to recording-absolute ones.
    private var discardedSampleCount = 0
    private var liveReady = false
    private var inferenceInProgress = false
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    /// If `sampleCount` exceeds `liveMaxSamples`, returns how many samples should be
    /// discarded from the front of the rolling window to fall back toward
    /// `liveRetainSamples`; otherwise returns 0.
    static func discardCount(forSampleCount sampleCount: Int) -> Int {
        guard sampleCount > liveMaxSamples else { return 0 }
        return min(liveDiscardSamples, sampleCount)
    }

    /// Converts a count of samples discarded from the front of the rolling window
    /// into a millisecond offset, used to translate window-relative Whisper
    /// timestamps back to recording-absolute ones.
    static func offsetMs(forDiscardedSampleCount discardedSampleCount: Int) -> Int {
        Int((Double(discardedSampleCount) / Double(WhisperKit.sampleRate)) * 1_000)
    }

    func prepare() async throws {
        _ = try await model()
    }

    func beginLive(onSegment: @escaping @Sendable (TranscriptionSegment) -> Void) {
        self.onSegment = onSegment
        liveSamples = []
        totalAppendedSamples = 0
        nextLiveUpdateSample = WhisperKit.sampleRate * 2
        discardedSampleCount = 0
        liveReady = false
    }

    func prepareLive(audioFormat: AVAudioFormat) async throws {
        _ = audioFormat
        _ = try await model()
        liveReady = true
        try await publishLiveSnapshot()
    }

    func append(_ chunk: CapturedAudioChunk) async throws {
        guard let resampled = AudioProcessor.resampleAudio(
            fromBuffer: chunk.buffer,
            toSampleRate: Double(WhisperKit.sampleRate),
            channelCount: 1
        ) else { return }
        let newSamples = AudioProcessor.convertBufferToArray(buffer: resampled)
        liveSamples.append(contentsOf: newSamples)
        totalAppendedSamples += newSamples.count

        let discardCount = Self.discardCount(forSampleCount: liveSamples.count)
        if discardCount > 0 {
            liveSamples.removeFirst(discardCount)
            discardedSampleCount += discardCount
        }

        guard liveReady, totalAppendedSamples >= nextLiveUpdateSample else { return }
        nextLiveUpdateSample = totalAppendedSamples + WhisperKit.sampleRate * 3
        try await publishLiveSnapshot()
    }

    func finishLive() async throws {
        await acquireInference()
        releaseInference()
        onSegment = nil
        liveSamples = []
        totalAppendedSamples = 0
        discardedSampleCount = 0
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
        let offsetMs = Self.offsetMs(forDiscardedSampleCount: discardedSampleCount)
        let results = try await model().transcribe(
            audioArray: snapshot,
            decodeOptions: Self.liveDecodingOptions
        )
        for segment in Self.convert(results) {
            onSegment(
                TranscriptionSegment(
                    startMs: segment.startMs + offsetMs,
                    endMs: segment.endMs + offsetMs,
                    text: segment.text
                )
            )
        }
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
