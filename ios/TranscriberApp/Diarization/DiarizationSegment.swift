import Foundation

/// A time segment labeled with a speaker identity.
struct DiarizationSegment: Identifiable, Codable, Equatable {
    let id = UUID()
    let startMs: Int      // Start time in milliseconds
    let endMs: Int        // End time in milliseconds
    let speaker: String   // e.g. "SPEAKER_00", "SPEAKER_01"

    // Codable conformance (exclude id)
    enum CodingKeys: String, CodingKey {
        case startMs, endMs, speaker
    }
}
