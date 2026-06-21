import AVFoundation
import Combine
import Foundation
import SwiftUI

nonisolated enum SpeakerLabelDiagnosticStatus: Equatable, Sendable {
    case notStarted
    case identifying
    case complete
    case approximate
    case retryNeeded
    case canceled
    case notAvailable

    var displayText: String {
        switch self {
        case .notStarted: "Not started"
        case .identifying: "Identifying speakers"
        case .complete: "Complete"
        case .approximate: "Approximate"
        case .retryNeeded: "Needs retry"
        case .canceled: "Canceled"
        case .notAvailable: "Not available yet"
        }
    }
}

nonisolated struct ProcessingDiagnostics: Equatable, Sendable {
    var audioFileName: String?
    var finalTranscriptionModelID: String?
    var finalTranscriptionModelName: String?
    var modelLoadTime: TimeInterval?
    var transcriptionTime: TimeInterval?
    var audioDuration: TimeInterval?
    var diarizationTime: TimeInterval?
    var transcriptionFallbackUsed: Bool
    var diarizationFallbackUsed: Bool
    var speakerLabelStatus: SpeakerLabelDiagnosticStatus
    var failureMessage: String?
    var isSessionOnly: Bool

    init(
        audioFileName: String? = nil,
        finalTranscriptionModelID: String? = nil,
        finalTranscriptionModelName: String? = nil,
        modelLoadTime: TimeInterval? = nil,
        transcriptionTime: TimeInterval? = nil,
        audioDuration: TimeInterval? = nil,
        diarizationTime: TimeInterval? = nil,
        transcriptionFallbackUsed: Bool = false,
        diarizationFallbackUsed: Bool = false,
        speakerLabelStatus: SpeakerLabelDiagnosticStatus = .notStarted,
        failureMessage: String? = nil,
        isSessionOnly: Bool = true
    ) {
        self.audioFileName = audioFileName
        self.finalTranscriptionModelID = finalTranscriptionModelID
        self.finalTranscriptionModelName = finalTranscriptionModelName
        self.modelLoadTime = modelLoadTime
        self.transcriptionTime = transcriptionTime
        self.audioDuration = audioDuration
        self.diarizationTime = diarizationTime
        self.transcriptionFallbackUsed = transcriptionFallbackUsed
        self.diarizationFallbackUsed = diarizationFallbackUsed
        self.speakerLabelStatus = speakerLabelStatus
        self.failureMessage = failureMessage
        self.isSessionOnly = isSessionOnly
    }

    var realtimeFactor: Double? {
        guard let audioDuration, let transcriptionTime, transcriptionTime > 0 else {
            return nil
        }
        return audioDuration / transcriptionTime
    }

    static func measuredAudioDuration(for url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    @MainActor
    static func derivedSummary(for recording: Recording, activity: RecordingStatusActivity?) -> ProcessingDiagnostics {
        ProcessingDiagnostics(
            audioFileName: recording.audioFileName,
            finalTranscriptionModelID: recording.finalTranscriptionModelID.isEmpty ? nil : recording.finalTranscriptionModelID,
            finalTranscriptionModelName: RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID),
            audioDuration: recording.durationSeconds,
            speakerLabelStatus: speakerStatus(
                for: recording.recordingStatus(activity: activity),
                diarizationNeedsRetry: recording.diarizationNeedsRetry
            ),
            isSessionOnly: false
        )
    }

    static func speakerStatus(
        for status: RecordingStatus,
        diarizationNeedsRetry: Bool
    ) -> SpeakerLabelDiagnosticStatus {
        if diarizationNeedsRetry || status == .speakerLabelsFailed {
            return .retryNeeded
        }
        switch status {
        case .recordingSaved, .needsTranscription, .transcribing:
            return .notAvailable
        case .speakerLabeling:
            return .identifying
        case .speakerLabelsFailed:
            return .retryNeeded
        case .complete:
            return .complete
        }
    }
}

nonisolated enum DiagnosticsMetricFormatter {
    static func formatSeconds(_ value: TimeInterval?) -> String {
        guard let value else { return "Not measured" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) seconds"
    }

    static func speedDescription(audioDuration: TimeInterval?, processingTime: TimeInterval?) -> String {
        guard let audioDuration, let processingTime, processingTime > 0 else {
            return "Not measured"
        }
        return String(format: "%.1f× real time", audioDuration / processingTime)
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

nonisolated struct DiagnosticsRow: Equatable, Sendable {
    let label: String
    let value: String
}

nonisolated struct DiagnosticsPresentation: Equatable, Sendable {
    static let isExpandedByDefault = false
    let rows: [DiagnosticsRow]
    let footer: String?

    static func make(for diagnostics: ProcessingDiagnostics) -> DiagnosticsPresentation {
        var rows: [DiagnosticsRow] = []
        if let modelName = diagnostics.finalTranscriptionModelName {
            rows.append(DiagnosticsRow(label: "Model", value: modelName))
        }
        if let modelID = diagnostics.finalTranscriptionModelID {
            rows.append(DiagnosticsRow(label: "Model ID", value: modelID))
        }
        rows.append(DiagnosticsRow(label: "Model load", value: DiagnosticsMetricFormatter.formatSeconds(diagnostics.modelLoadTime)))
        rows.append(DiagnosticsRow(label: "Transcription", value: DiagnosticsMetricFormatter.formatSeconds(diagnostics.transcriptionTime)))
        rows.append(DiagnosticsRow(label: "Audio length", value: DiagnosticsMetricFormatter.formatSeconds(diagnostics.audioDuration)))
        rows.append(DiagnosticsRow(label: "Speed", value: DiagnosticsMetricFormatter.speedDescription(
            audioDuration: diagnostics.audioDuration,
            processingTime: diagnostics.transcriptionTime
        )))
        if let diarizationTime = diagnostics.diarizationTime {
            rows.append(DiagnosticsRow(label: "Speaker labeling", value: DiagnosticsMetricFormatter.formatSeconds(diarizationTime)))
        }
        rows.append(DiagnosticsRow(label: "Transcription fallback", value: DiagnosticsMetricFormatter.yesNo(diagnostics.transcriptionFallbackUsed)))
        rows.append(DiagnosticsRow(label: "Diarization fallback", value: DiagnosticsMetricFormatter.yesNo(diagnostics.diarizationFallbackUsed)))
        rows.append(DiagnosticsRow(label: "Speaker labels", value: diagnostics.speakerLabelStatus.displayText))
        if let failureMessage = diagnostics.failureMessage, !failureMessage.isEmpty {
            rows.append(DiagnosticsRow(label: "Failure", value: failureMessage))
        }

        let footer = diagnostics.isSessionOnly
            ? "These details are kept for the current session and are not written into the recording database."
            : "Stored recordings keep stable details like model, audio length, and speaker status. Timing appears after a current processing run."
        return DiagnosticsPresentation(rows: rows, footer: footer)
    }
}

@MainActor
final class ProcessingDiagnosticsStore: ObservableObject {
    static let shared = ProcessingDiagnosticsStore()

    @Published private var diagnosticsByAudioFileName: [String: ProcessingDiagnostics] = [:]

    func diagnostics(forAudioFileName audioFileName: String) -> ProcessingDiagnostics? {
        diagnosticsByAudioFileName[audioFileName]
    }

    func record(_ diagnostics: ProcessingDiagnostics) {
        guard let audioFileName = diagnostics.audioFileName else { return }
        diagnosticsByAudioFileName[audioFileName] = diagnostics
    }
}

struct DiagnosticsRowsView: View {
    let diagnostics: ProcessingDiagnostics

    private var presentation: DiagnosticsPresentation {
        DiagnosticsPresentation.make(for: diagnostics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(presentation.rows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let footer = presentation.footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

struct DiagnosticsDisclosureView: View {
    let diagnostics: ProcessingDiagnostics

    var body: some View {
        DisclosureGroup("Diagnostics") {
            DiagnosticsRowsView(diagnostics: diagnostics)
                .padding(.top, 6)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.muted)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border)
        )
    }
}
