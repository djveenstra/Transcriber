import Foundation

/// A single segment of transcribed text with timestamps.
struct TranscriptionSegment: Identifiable, Codable, Equatable {
    let id = UUID()
    let startMs: Int    // Start time in milliseconds
    let endMs: Int      // End time in milliseconds
    let text: String    // Transcribed text

    /// Formatted timestamp string
    var timestamp: String {
        let totalSeconds = startMs / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // Codable conformance (exclude id)
    enum CodingKeys: String, CodingKey {
        case startMs, endMs, text
    }
}
