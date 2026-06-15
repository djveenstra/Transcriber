import Foundation
import os
import SwiftData

private nonisolated let modelsLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Models")

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
        do {
            self.transcriptData = try JSONEncoder().encode(segments)
        } catch {
            modelsLogger.error("Failed to encode transcript segments: \(error.localizedDescription, privacy: .public)")
            self.transcriptData = Data()
        }
        do {
            self.rawTranscriptionData = try JSONEncoder().encode(rawTranscription)
        } catch {
            modelsLogger.error("Failed to encode raw transcription: \(error.localizedDescription, privacy: .public)")
            self.rawTranscriptionData = Data()
        }
        self.speakerNamesData = Data()
        self.transcriptionNeedsRetry = transcriptionNeedsRetry
        self.diarizationNeedsRetry = diarizationNeedsRetry
        self.finalTranscriptionModelID = finalTranscriptionModelID
    }

    var segments: [TranscriptSegment] {
        get {
            guard !transcriptData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([TranscriptSegment].self, from: transcriptData)
            } catch {
                modelsLogger.error("Failed to decode transcript segments: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        set {
            do {
                transcriptData = try JSONEncoder().encode(newValue)
            } catch {
                modelsLogger.error("Failed to encode transcript segments, keeping previous data: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var speakerNames: [String: String] {
        get {
            guard !speakerNamesData.isEmpty else { return [:] }
            do {
                return try JSONDecoder().decode([String: String].self, from: speakerNamesData)
            } catch {
                modelsLogger.error("Failed to decode speaker names: \(error.localizedDescription, privacy: .public)")
                return [:]
            }
        }
        set {
            do {
                speakerNamesData = try JSONEncoder().encode(newValue)
            } catch {
                modelsLogger.error("Failed to encode speaker names, keeping previous data: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var rawTranscription: [TranscriptionSegment] {
        get {
            guard !rawTranscriptionData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([TranscriptionSegment].self, from: rawTranscriptionData)
            } catch {
                modelsLogger.error("Failed to decode raw transcription: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        set {
            do {
                rawTranscriptionData = try JSONEncoder().encode(newValue)
            } catch {
                modelsLogger.error("Failed to encode raw transcription, keeping previous data: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var audioURL: URL {
        AppStoragePaths.recordingsDirectory.appendingPathComponent(audioFileName)
    }
}

enum AppStoragePaths {
    nonisolated static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Transcriber2Beta", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    nonisolated static let recordingsDirectory: URL = {
        let url = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
