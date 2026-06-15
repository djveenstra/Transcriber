import Foundation
import SwiftData

struct TranscriptionSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var startMs: Int
    var endMs: Int
    var text: String
}

struct DiarizationSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var startMs: Int
    var endMs: Int
    var speaker: String
}

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var startMs: Int
    var endMs: Int
    var speaker: String
    var text: String

    var timestamp: String {
        let total = startMs / 1_000
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

@Model
final class Recording {
    var title: String
    var createdAt: Date
    var durationSeconds: Double
    var audioFileName: String
    var transcriptData: Data
    var rawTranscriptionData: Data = Data()
    var speakerNamesData: Data
    var transcriptionNeedsRetry: Bool = false
    var diarizationNeedsRetry: Bool = false
    var finalTranscriptionModelID: String = ""

    init(
        title: String,
        createdAt: Date = .now,
        durationSeconds: Double,
        audioFileName: String,
        segments: [TranscriptSegment],
        rawTranscription: [TranscriptionSegment] = [],
        transcriptionNeedsRetry: Bool = false,
        diarizationNeedsRetry: Bool = false,
        finalTranscriptionModelID: String = ""
    ) {
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.transcriptData = (try? JSONEncoder().encode(segments)) ?? Data()
        self.rawTranscriptionData = (try? JSONEncoder().encode(rawTranscription)) ?? Data()
        self.speakerNamesData = Data()
        self.transcriptionNeedsRetry = transcriptionNeedsRetry
        self.diarizationNeedsRetry = diarizationNeedsRetry
        self.finalTranscriptionModelID = finalTranscriptionModelID
    }

    var segments: [TranscriptSegment] {
        get { (try? JSONDecoder().decode([TranscriptSegment].self, from: transcriptData)) ?? [] }
        set { transcriptData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var speakerNames: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: speakerNamesData)) ?? [:] }
        set { speakerNamesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var rawTranscription: [TranscriptionSegment] {
        get { (try? JSONDecoder().decode([TranscriptionSegment].self, from: rawTranscriptionData)) ?? [] }
        set { rawTranscriptionData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var audioURL: URL {
        AppStoragePaths.recordingsDirectory.appendingPathComponent(audioFileName)
    }
}

enum AppStoragePaths {
    static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Transcriber2Beta", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let recordingsDirectory: URL = {
        let url = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
