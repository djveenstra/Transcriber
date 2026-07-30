import Foundation

/// The narrow invocation seam for a final transcription engine.
///
/// Model selection, preparation, fallback, unload pacing, state publication, and
/// persistence remain owned by `TranscriptionSession`.
protocol FinalTranscriptionRunning: Sendable {
    func transcribe(
        using engine: any TranscriptionEngine,
        audioURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment]
}

struct FinalTranscriptionRunner: FinalTranscriptionRunning {
    func transcribe(
        using engine: any TranscriptionEngine,
        audioURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
        try await engine.transcribeFile(audioURL, progress: progress)
    }
}
