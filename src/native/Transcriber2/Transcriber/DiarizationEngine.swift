@preconcurrency import AVFoundation
import FluidAudio
import Foundation

protocol DiarizationEngine: Actor {
    func diarizeFile(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [DiarizationSegment]
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
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [DiarizationSegment] {
        let diarizer = try await loadDiarizer(progress: progress)
        diarizer.reset()

        let audioFile = try AVAudioFile(forReading: url)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        guard totalFrames > 0 else { return [] }

        let converter = try Self.makeConverter(from: audioFile.processingFormat)
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: Self.chunkFrameCount
        )!

        var framesRead: AVAudioFrameCount = 0
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: Self.chunkFrameCount
        )!

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
            _ = try diarizer.process(samples: samples, sourceSampleRate: Self.targetSampleRate)

            let fileProgress = Double(framesRead) / Double(totalFrames)
            progress(0.15 + fileProgress * 0.80)
        }

        try Task.checkCancellation()
        _ = try diarizer.finalizeSession()
        progress(1)
        return Self.convertTimeline(diarizer.timeline.speakers.values.flatMap(\.finalizedSegments))
    }

    private func loadDiarizer(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SortformerDiarizer {
        if let existing = self.diarizer { return existing }
        let created = SortformerDiarizer(config: config)
        let models = try await SortformerModels.loadFromHuggingFace(config: config) { download in
            progress(download.fractionCompleted * 0.15)
        }
        created.initialize(models: models)
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
