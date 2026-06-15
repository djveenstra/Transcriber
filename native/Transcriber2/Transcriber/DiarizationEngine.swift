import AVFoundation
import FluidAudio
import Foundation

protocol DiarizationEngine: Actor {
    func prepareLive() async throws
    func resetLive()
    func appendLive(_ buffer: AVAudioPCMBuffer) throws -> [DiarizationSegment]
    func finishLive() throws -> [DiarizationSegment]
    func diarizeFile(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [DiarizationSegment]
}

actor FluidDiarizationEngine: DiarizationEngine {
    private var liveDiarizer: SortformerDiarizer?
    private var finalDiarizer: SortformerDiarizer?
    private var pendingLiveSamples: [Float] = []
    private var pendingLiveSampleRate: Double?

    func prepareLive() async throws {
        guard liveDiarizer == nil else { return }
        let config = SortformerConfig.fastV2
        let diarizer = SortformerDiarizer(config: config)
        let models = try await SortformerModels.loadFromHuggingFace(config: config)
        diarizer.initialize(models: models)
        liveDiarizer = diarizer
        if !pendingLiveSamples.isEmpty {
            _ = try diarizer.process(
                samples: pendingLiveSamples,
                sourceSampleRate: pendingLiveSampleRate ?? Double(config.sampleRate)
            )
            pendingLiveSamples = []
            pendingLiveSampleRate = nil
        }
    }

    func resetLive() {
        liveDiarizer?.reset()
        pendingLiveSamples = []
        pendingLiveSampleRate = nil
    }

    func appendLive(_ buffer: AVAudioPCMBuffer) throws -> [DiarizationSegment] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard let liveDiarizer else {
            pendingLiveSamples.append(contentsOf: samples)
            pendingLiveSampleRate = buffer.format.sampleRate
            return []
        }
        _ = try liveDiarizer.process(samples: samples, sourceSampleRate: buffer.format.sampleRate)
        return Self.convert(
            liveDiarizer.timeline.speakers.values.flatMap { $0.finalizedSegments + $0.tentativeSegments }
        )
    }

    func finishLive() throws -> [DiarizationSegment] {
        guard let liveDiarizer else { return [] }
        _ = try liveDiarizer.finalizeSession()
        return Self.convert(liveDiarizer.timeline.speakers.values.flatMap(\.finalizedSegments))
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [DiarizationSegment] {
        let diarizer: SortformerDiarizer
        if let finalDiarizer {
            diarizer = finalDiarizer
        } else {
            let config = SortformerConfig.balancedV2
            let created = SortformerDiarizer(config: config)
            let models = try await SortformerModels.loadFromHuggingFace(config: config) { download in
                progress(download.fractionCompleted * 0.15)
            }
            created.initialize(models: models)
            finalDiarizer = created
            diarizer = created
        }

        let timeline = try diarizer.processComplete(audioFileURL: url) { complete, total, _ in
            let fileProgress = total > 0 ? Double(complete) / Double(total) : 0
            progress(0.15 + fileProgress * 0.85)
        }
        progress(1)
        return Self.convert(timeline.speakers.values.flatMap(\.finalizedSegments))
    }

    private static func convert(_ segments: [DiarizerSegment]) -> [DiarizationSegment] {
        segments.map {
            DiarizationSegment(
                startMs: Int(Double($0.startTime) * 1_000),
                endMs: Int(Double($0.endTime) * 1_000),
                speaker: String(format: "SPEAKER_%02d", $0.speakerIndex)
            )
        }
    }
}
