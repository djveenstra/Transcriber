import FluidAudio
import Foundation

protocol DiarizationEngine: Actor {
    func diarizeFile(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [DiarizationSegment]
}

actor FluidDiarizationEngine: DiarizationEngine {
    private let config: SortformerConfig
    private var diarizer: SortformerDiarizer?

    init(config: SortformerConfig = .balancedV2) {
        self.config = config
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [DiarizationSegment] {
        let diarizer: SortformerDiarizer
        if let existing = self.diarizer {
            diarizer = existing
        } else {
            let created = SortformerDiarizer(config: config)
            let models = try await SortformerModels.loadFromHuggingFace(config: config) { download in
                progress(download.fractionCompleted * 0.15)
            }
            created.initialize(models: models)
            self.diarizer = created
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
