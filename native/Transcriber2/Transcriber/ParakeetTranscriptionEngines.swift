#if os(iOS)
import AVFoundation
import FluidAudio
import Foundation

actor ParakeetEOULiveEngine {
    private var manager: StreamingEouAsrManager?
    private var onSegment: (@Sendable (TranscriptionSegment) -> Void)?
    private var latestText = ""
    private var latestTimestampMs = 1
    private var ready = false
    private var stopped = false
    private var queueURL: URL?
    private var queueWriter: AVAudioFile?
    private var queuedFrames: AVAudioFramePosition = 0
    private var maximumQueuedFrames: AVAudioFramePosition = 0

    func begin(
        audioFormat: AVAudioFormat,
        queueURL: URL,
        onSegment: @escaping @Sendable (TranscriptionSegment) -> Void
    ) throws {
        self.onSegment = onSegment
        latestText = ""
        latestTimestampMs = 1
        ready = false
        stopped = false
        queuedFrames = 0
        maximumQueuedFrames = AVAudioFramePosition(audioFormat.sampleRate * 3_600)
        self.queueURL = queueURL
        queueWriter = try AVAudioFile(forWriting: queueURL, settings: audioFormat.settings)
    }

    func prepare() async throws {
        let created = StreamingEouAsrManager(chunkSize: .ms320)
        await created.setPartialCallback { [weak self] text in
            Task { await self?.publish(text) }
        }
        try await created.loadModels()
        guard !stopped else {
            await created.cleanup()
            return
        }
        manager = created

        try await processQueuedAudio(with: created)
        cleanupQueue()
        ready = true
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        guard !stopped else { return }
        guard ready, let manager else {
            if queuedFrames < maximumQueuedFrames {
                try queueWriter?.write(from: buffer)
                queuedFrames += AVAudioFramePosition(buffer.frameLength)
            }
            return
        }
        _ = try await manager.process(audioBuffer: buffer)
    }

    func finish() async {
        stopped = true
        cleanupQueue()
        if let manager {
            _ = try? await manager.finish()
            await manager.cleanup()
        }
        manager = nil
        onSegment = nil
        ready = false
    }

    private func processQueuedAudio(with manager: StreamingEouAsrManager) async throws {
        guard let queueURL else { return }
        let reader = try AVAudioFile(forReading: queueURL)
        let format = reader.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else { return }

        while !stopped {
            let targetFrames = queuedFrames
            while reader.framePosition < targetFrames {
                let remaining = targetFrames - reader.framePosition
                buffer.frameLength = 0
                try reader.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining)))
                guard buffer.frameLength > 0 else { return }
                _ = try await manager.process(audioBuffer: buffer)
            }
            if reader.framePosition >= queuedFrames { return }
        }
    }

    private func cleanupQueue() {
        queueWriter = nil
        if let queueURL {
            try? FileManager.default.removeItem(at: queueURL)
        }
        queueURL = nil
        queuedFrames = 0
    }

    private func publish(_ text: String) async {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != latestText, let onSegment else { return }
        latestText = cleaned
        if let manager, let timestamp = await manager.getTokenTimestampsMs().last {
            latestTimestampMs = max(timestamp, latestTimestampMs)
        }
        onSegment(TranscriptionSegment(startMs: 0, endMs: latestTimestampMs, text: cleaned))
    }
}

actor ParakeetFinalTranscriptionEngine {
    private let model: FinalTranscriptionModelChoice
    private var manager: AsrManager?

    init(model: FinalTranscriptionModelChoice) {
        self.model = model
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard manager == nil, let version = model.parakeetVersion else { return }
        let models = try await AsrModels.downloadAndLoad(version: version) { download in
            progress(download.fractionCompleted)
        }
        manager = AsrManager(
            config: ASRConfig(parallelChunkConcurrency: 2),
            models: models
        )
    }

    func transcribeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
        try await prepare { progress($0 * 0.1) }
        guard let manager else { throw ParakeetEngineError.notReady }
        let progressTask = Task {
            do {
                for try await value in await manager.transcriptionProgressStream {
                    progress(0.1 + value * 0.9)
                }
            } catch {
                // The transcription call reports the actionable error.
            }
        }
        defer { progressTask.cancel() }

        var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(url, decoderState: &state, language: .english)
        progress(1)
        return Self.convert(result)
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    static func convert(_ result: ASRResult) -> [TranscriptionSegment] {
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [
                TranscriptionSegment(startMs: 0, endMs: max(1, Int(result.duration * 1_000)), text: text)
            ]
        }

        var words: [TranscriptionSegment] = []
        var currentText = ""
        var currentStart = 0
        var currentEnd = 1

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                words.append(TranscriptionSegment(startMs: currentStart, endMs: max(currentStart + 1, currentEnd), text: text))
            }
            currentText = ""
        }

        for timing in timings {
            let raw = timing.token.replacingOccurrences(of: "▁", with: " ")
            let beginsWord = raw.first?.isWhitespace == true
            if beginsWord, !currentText.isEmpty { flush() }
            if currentText.isEmpty { currentStart = Int(timing.startTime * 1_000) }
            currentText += raw
            currentEnd = Int(timing.endTime * 1_000)
        }
        flush()
        return words
    }
}

private enum ParakeetEngineError: LocalizedError {
    case notReady
    var errorDescription: String? { "The Parakeet model could not be prepared." }
}
#endif
