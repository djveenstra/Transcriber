import SwiftData
import Foundation

/// Persisted recording with its transcript, stored via SwiftData.
@Model
class Recording {
    var title: String
    var dateCreated: Date
    var durationSeconds: Int
    var audioFileName: String        // Relative filename within app's documents
    var transcriptJSON: String       // JSON-encoded [MergedSegment]
    var numSpeakers: Int

    init(title: String, durationSeconds: Int, audioFileName: String, segments: [MergedSegment]) {
        self.title = title
        self.dateCreated = Date()
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.numSpeakers = Set(segments.map(\.speaker)).count

        // Encode segments to JSON
        if let data = try? JSONEncoder().encode(segments),
           let json = String(data: data, encoding: .utf8) {
            self.transcriptJSON = json
        } else {
            self.transcriptJSON = "[]"
        }
    }

    /// Decode stored transcript back into segments.
    var segments: [MergedSegment] {
        guard let data = transcriptJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MergedSegment].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Full path to the audio file.
    var audioURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(audioFileName)
    }

    /// Formatted duration string "MM:SS" or "H:MM:SS"
    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateCreated)
    }

    /// Plain text export of the transcript
    var plainTextTranscript: String {
        TranscriptExporter.toText(segments)
    }
}
