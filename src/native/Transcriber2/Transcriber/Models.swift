import Foundation
import Combine
import os
import SwiftData

private nonisolated let modelsLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Models")

nonisolated struct TranscriptionSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var startMs: Int
    var endMs: Int
    var text: String
}

nonisolated struct DiarizationSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var startMs: Int
    var endMs: Int
    var speaker: String
}

nonisolated struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
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

nonisolated enum TranscriptSegmentReassignment {
    static func availableSpeakers(in segments: [TranscriptSegment]) -> [String] {
        var seen: Set<String> = []
        var speakers: [String] = []
        for segment in segments where !seen.contains(segment.speaker) {
            seen.insert(segment.speaker)
            speakers.append(segment.speaker)
        }
        return speakers
    }

    static func reassign(
        segmentID: TranscriptSegment.ID,
        to speaker: String,
        in segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        segments.map { segment in
            guard segment.id == segmentID else { return segment }
            var updated = segment
            updated.speaker = speaker
            return updated
        }
    }

    @MainActor
    static func reassign(segmentID: TranscriptSegment.ID, to speaker: String, in recording: Recording) {
        recording.segments = reassign(segmentID: segmentID, to: speaker, in: recording.segments)
    }
}

nonisolated enum RecordingStatus: String, CaseIterable, Equatable, Sendable {
    case recordingSaved
    case needsTranscription
    case transcribing
    case speakerLabeling
    case speakerLabelsFailed
    case complete

    var display: RecordingStatusDisplay {
        switch self {
        case .recordingSaved:
            RecordingStatusDisplay(title: "Recording saved", systemImage: "waveform")
        case .needsTranscription:
            RecordingStatusDisplay(title: "Needs transcription", systemImage: "text.badge.exclamationmark")
        case .transcribing:
            RecordingStatusDisplay(title: "Transcribing", systemImage: "text.quote")
        case .speakerLabeling:
            RecordingStatusDisplay(title: "Speaker labeling", systemImage: "person.3.sequence.fill")
        case .speakerLabelsFailed:
            RecordingStatusDisplay(title: "Speaker labels need retry", systemImage: "person.crop.circle.badge.exclamationmark")
        case .complete:
            RecordingStatusDisplay(title: "Complete", systemImage: "checkmark.circle.fill")
        }
    }
}

nonisolated struct RecordingStatusDisplay: Equatable, Sendable {
    let title: String
    let systemImage: String
}

nonisolated enum RecordingStatusActivity: Equatable, Sendable {
    case transcribing
    case speakerLabeling
}

@MainActor
final class RecordingStatusActivityStore: ObservableObject {
    static let shared = RecordingStatusActivityStore()

    @Published private var activitiesByAudioFileName: [String: RecordingStatusActivity] = [:]

    func activity(for recording: Recording) -> RecordingStatusActivity? {
        activitiesByAudioFileName[recording.audioFileName]
    }

    func set(_ activity: RecordingStatusActivity, forAudioFileName audioFileName: String) {
        activitiesByAudioFileName[audioFileName] = activity
    }

    func clear(audioFileName: String) {
        activitiesByAudioFileName.removeValue(forKey: audioFileName)
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

    var recordingStatus: RecordingStatus {
        recordingStatus(activity: nil)
    }

    func recordingStatus(activity: RecordingStatusActivity?) -> RecordingStatus {
        if activity == .transcribing {
            return .transcribing
        }
        if activity == .speakerLabeling {
            return .speakerLabeling
        }
        if transcriptionNeedsRetry {
            return .needsTranscription
        }
        if diarizationNeedsRetry {
            return .speakerLabelsFailed
        }
        if segments.isEmpty {
            return .recordingSaved
        }
        return .complete
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

enum RecordingLibraryMetadata {
    static func durationText(seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func modelName(for modelID: String) -> String {
        guard !modelID.isEmpty else { return "Model not recorded" }
        return FinalTranscriptionModelChoice.all.first { $0.id == modelID }?.name ?? "Unknown model"
    }

    static func speakerLabelText(for recording: Recording, status: RecordingStatus) -> String {
        switch status {
        case .recordingSaved, .needsTranscription, .transcribing:
            return "Speaker labels not available yet"
        case .speakerLabeling:
            return "Identifying speakers"
        case .speakerLabelsFailed:
            return "Speaker labels need retry"
        case .complete:
            let count = Set(recording.segments.map(\.speaker)).count
            if count <= 0 { return "Speaker labels not available" }
            if count == 1 { return "1 speaker label" }
            return "\(count) speaker labels"
        }
    }
}

enum RecordingAudioReconciliation {
    static func missingAudioFileNames(
        in recordings: [Recording],
        fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Set<String> {
        Set(recordings.compactMap { recording in
            fileExistsAtPath(recording.audioURL.path) ? nil : recording.audioFileName
        })
    }
}

@MainActor
final class RecordingAudioAvailabilityStore: ObservableObject {
    static let shared = RecordingAudioAvailabilityStore()

    @Published private(set) var missingAudioFileNames: Set<String> = []

    func reconcile(recordings: [Recording]) {
        missingAudioFileNames = RecordingAudioReconciliation.missingAudioFileNames(in: recordings)
    }

    func isAudioMissing(for recording: Recording) -> Bool {
        missingAudioFileNames.contains(recording.audioFileName)
            || !FileManager.default.fileExists(atPath: recording.audioURL.path)
    }
}
