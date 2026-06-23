@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import os

nonisolated private let diarizationLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Diarization")

protocol DiarizationEngine: Actor {
    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void,
        stage: @escaping @Sendable (DiarizationStageEvent) -> Void
    ) async throws -> [DiarizationSegment]
}

nonisolated enum DiarizationDiagnosticStage: String, CaseIterable, Equatable, Sendable {
    case starting
    case audioInspection
    case conversionPrep
    case modelLoad
    case process
    case finalize
    case finished

    var displayText: String {
        switch self {
        case .starting: "Starting speaker labeling"
        case .audioInspection: "Audio inspection"
        case .conversionPrep: "Audio conversion/prep"
        case .modelLoad: "Model/resource loading"
        case .process: "Sortformer processing"
        case .finalize: "Finalize speaker timeline"
        case .finished: "Finished"
        }
    }
}

nonisolated enum DiarizationStageEventKind: Equatable, Sendable {
    case started
    case ended
}

nonisolated struct DiarizationStageEvent: Equatable, Sendable {
    let stage: DiarizationDiagnosticStage
    let kind: DiarizationStageEventKind
    let detail: String?

    init(_ kind: DiarizationStageEventKind, _ stage: DiarizationDiagnosticStage, detail: String? = nil) {
        self.stage = stage
        self.kind = kind
        self.detail = detail
    }
}

actor FluidDiarizationEngine: DiarizationEngine {
    private let config: SortformerConfig
    private var diarizer: SortformerDiarizer?

    static let targetSampleRate: Double = 16_000
    static let chunkFrameCount: AVAudioFrameCount = 16_000

    init(config: SortformerConfig = .balancedV2) {
        self.config = config
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void,
        stage: @escaping @Sendable (DiarizationStageEvent) -> Void
    ) async throws -> [DiarizationSegment] {
        diarizationLogger.info("diarization.audio_inspection.start file=\(url.lastPathComponent, privacy: .private)")
        stage(DiarizationStageEvent(.started, .audioInspection))
        let audioFile = try AVAudioFile(forReading: url)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let inputFormat = audioFile.processingFormat
        let inputDuration = inputFormat.sampleRate > 0 ? Double(audioFile.length) / inputFormat.sampleRate : 0
        diarizationLogger.info(
            """
            diarization.audio_inspection.end file=\(url.lastPathComponent, privacy: .private) \
            sampleRate=\(inputFormat.sampleRate, privacy: .public) \
            channels=\(inputFormat.channelCount, privacy: .public) \
            format=\(String(describing: inputFormat.commonFormat), privacy: .public) \
            interleaved=\(inputFormat.isInterleaved, privacy: .public) \
            frames=\(audioFile.length, privacy: .public) \
            duration=\(inputDuration, privacy: .public)
            """
        )
        stage(DiarizationStageEvent(.ended, .audioInspection))
        guard totalFrames > 0 else { return [] }

        diarizationLogger.info("diarization.conversion_prep.start targetSampleRate=\(Self.targetSampleRate, privacy: .public) targetChannels=1 targetFormat=Float32")
        stage(DiarizationStageEvent(.started, .conversionPrep))
        let converter = try Self.makeConverter(from: audioFile.processingFormat)
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: Self.chunkFrameCount
        )!
        diarizationLogger.info("diarization.conversion_prep.end chunkFrames=\(Self.chunkFrameCount, privacy: .public)")
        stage(DiarizationStageEvent(.ended, .conversionPrep))

        stage(DiarizationStageEvent(.started, .modelLoad))
        let diarizer = try await loadDiarizer(progress: progress)
        stage(DiarizationStageEvent(.ended, .modelLoad))
        diarizationLogger.info("diarization.model_load.ready config=\(String(describing: self.config), privacy: .public)")
        diarizer.reset()

        var framesRead: AVAudioFrameCount = 0
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: Self.chunkFrameCount
        )!
        var chunkIndex = 0

        while framesRead < totalFrames {
            try Task.checkCancellation()

            let remaining = totalFrames - framesRead
            let toRead = min(Self.chunkFrameCount, remaining)
            inputBuffer.frameLength = 0
            try audioFile.read(into: inputBuffer, frameCount: toRead)
            guard inputBuffer.frameLength > 0 else { break }
            framesRead += inputBuffer.frameLength

            try Task.checkCancellation()

            let samples = try Self.convert(inputBuffer, using: converter, into: outputBuffer)

            try Task.checkCancellation()
            diarizationLogger.info("diarization.process.start chunk=\(chunkIndex, privacy: .public) samples=\(samples.count, privacy: .public)")
            stage(DiarizationStageEvent(.started, .process, detail: "chunk \(chunkIndex)"))
            _ = try diarizer.process(samples: samples, sourceSampleRate: Self.targetSampleRate)
            stage(DiarizationStageEvent(.ended, .process, detail: "chunk \(chunkIndex)"))
            diarizationLogger.info("diarization.process.end chunk=\(chunkIndex, privacy: .public)")
            chunkIndex += 1

            let fileProgress = Double(framesRead) / Double(totalFrames)
            progress(0.15 + fileProgress * 0.80)
        }

        try Task.checkCancellation()
        diarizationLogger.info("diarization.finalize.start chunks=\(chunkIndex, privacy: .public)")
        stage(DiarizationStageEvent(.started, .finalize))
        _ = try diarizer.finalizeSession()
        stage(DiarizationStageEvent(.ended, .finalize))
        diarizationLogger.info("diarization.finalize.end")
        progress(1)
        let segments = Self.convertTimeline(diarizer.timeline.speakers.values.flatMap(\.finalizedSegments))
        diarizationLogger.info("diarization.result.success segments=\(segments.count, privacy: .public)")
        stage(DiarizationStageEvent(.started, .finished))
        return segments
    }

    private func loadDiarizer(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SortformerDiarizer {
        if let existing = self.diarizer {
            diarizationLogger.info("diarization.model_load.reuse config=\(String(describing: self.config), privacy: .public)")
            return existing
        }
        diarizationLogger.info("diarization.model_load.start config=\(String(describing: self.config), privacy: .public)")
        let created = SortformerDiarizer(config: config)
        let models = try await SortformerModels.loadFromHuggingFace(config: config) { download in
            progress(download.fractionCompleted * 0.15)
        }
        diarizationLogger.info("diarization.model_load.resources_ready config=\(String(describing: self.config), privacy: .public)")
        created.initialize(models: models)
        diarizationLogger.info("diarization.model_load.initialized config=\(String(describing: self.config), privacy: .public)")
        self.diarizer = created
        return created
    }

    private static func makeConverter(from inputFormat: AVAudioFormat) throws -> AVAudioConverter {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DiarizationEngineError.unsupportedFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DiarizationEngineError.unsupportedFormat
        }
        return converter
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        into output: AVAudioPCMBuffer
    ) throws -> [Float] {
        output.frameLength = 0
        // The data-proc closure is called synchronously by AVAudioConverter, but
        // the compiler treats it as @Sendable. Use a class box to avoid the
        // "mutation of captured var in concurrently-executing code" warning.
        let gate = ConverterInputGate(buffer: input)
        let status = converter.convert(to: output, error: nil) { _, outStatus in
            guard let buffer = gate.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else {
            throw DiarizationEngineError.conversionFailed
        }
        guard let channelData = output.floatChannelData?[0], output.frameLength > 0 else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(output.frameLength)))
    }

    private static func convertTimeline(_ segments: [DiarizerSegment]) -> [DiarizationSegment] {
        segments.map {
            DiarizationSegment(
                startMs: Int(Double($0.startTime) * 1_000),
                endMs: Int(Double($0.endTime) * 1_000),
                speaker: String(format: "SPEAKER_%02d", $0.speakerIndex)
            )
        }
    }
}

private final class ConverterInputGate: @unchecked Sendable {
    nonisolated(unsafe) private var buffer: AVAudioPCMBuffer?

    nonisolated init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    nonisolated func take() -> AVAudioPCMBuffer? {
        let b = buffer
        buffer = nil
        return b
    }
}

nonisolated enum DiarizationEngineError: LocalizedError {
    case unsupportedFormat
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "The audio format is not supported for speaker labeling."
        case .conversionFailed: "Audio conversion failed during speaker labeling."
        }
    }
}
