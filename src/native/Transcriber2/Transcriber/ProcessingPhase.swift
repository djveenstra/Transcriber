import Foundation
import SwiftUI

enum ProcessingPhase: String, CaseIterable, Identifiable, Sendable {
    case savingRecording
    case preparingModel
    case transcribing
    case savingTranscript
    case identifyingSpeakers
    case savingSpeakerLabels
    case exporting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .savingRecording: "Saving recording"
        case .preparingModel: "Preparing model"
        case .transcribing: "Transcribing"
        case .savingTranscript: "Saving transcript"
        case .identifyingSpeakers: "Identifying speakers"
        case .savingSpeakerLabels: "Saving speaker labels"
        case .exporting: "Exporting"
        }
    }

    var activityText: String {
        switch self {
        case .savingRecording: "Keeping the audio safe"
        case .preparingModel: "Loading the on-device model"
        case .transcribing: "Creating the transcript"
        case .savingTranscript: "Preserving transcript text"
        case .identifyingSpeakers: "Applying speaker labels"
        case .savingSpeakerLabels: "Preserving speaker labels"
        case .exporting: "Preparing the share file"
        }
    }

    var detailText: String {
        switch self {
        case .savingRecording:
            "The original audio is saved before transcription continues."
        case .preparingModel:
            "The selected final transcription model is checked before processing."
        case .transcribing:
            "The final pass creates the transcript from the saved audio."
        case .savingTranscript:
            "Transcript text is saved before speaker labeling starts."
        case .identifyingSpeakers:
            "Speaker labels run after transcript text is available."
        case .savingSpeakerLabels:
            "Speaker labels are saved without replacing the original audio."
        case .exporting:
            "Export starts only from a user share action."
        }
    }

    var systemImage: String {
        switch self {
        case .savingRecording: "waveform.badge.checkmark"
        case .preparingModel: "cpu"
        case .transcribing: "text.quote"
        case .savingTranscript: "doc.text"
        case .identifyingSpeakers: "person.3"
        case .savingSpeakerLabels: "person.crop.circle.badge.checkmark"
        case .exporting: "square.and.arrow.up"
        }
    }

    static func legacyPhase(for message: String) -> ProcessingPhase {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("importing audio") { return .savingRecording }
        if normalized.contains("finalizing live transcript") { return .preparingModel }
        if normalized.contains("preparing transcription") { return .preparingModel }
        if normalized.contains("transcribing") { return .transcribing }
        if normalized.contains("identifying speakers") { return .identifyingSpeakers }
        if normalized == "saving" { return .savingSpeakerLabels }
        return .preparingModel
    }
}

struct ProcessingProgressPresentation: Equatable {
    let phase: ProcessingPhase
    let progress: Double?
    let canCancel: Bool
    let showsRetry: Bool

    var statusText: String {
        if let percentText {
            return percentText
        }
        return phase.activityText
    }

    var percentText: String? {
        guard let progress else { return nil }
        let clamped = min(max(progress, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func elapsedText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func accessibilityValue(elapsed: TimeInterval) -> String {
        let progressText = percentText.map { "Progress \($0)" } ?? phase.activityText
        return "\(phase.title). \(progressText). Elapsed \(Self.elapsedText(elapsed)). \(phase.detailText)"
    }
}

struct ProcessingTimelineView: View {
    let phase: ProcessingPhase
    let progress: Double?
    let startedAt: Date?
    let canCancel: Bool
    var cancelTitle = "Cancel"
    var cancelAction: (() -> Void)?
    var retryAction: (() -> Void)?
    var diagnostics: ProcessingDiagnostics?

    private var presentation: ProcessingProgressPresentation {
        ProcessingProgressPresentation(
            phase: phase,
            progress: progress,
            canCancel: canCancel,
            showsRetry: retryAction != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(phase.title, systemImage: phase.systemImage)
                    .font(.headline)
                Spacer()
                Text(presentation.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }

            ProgressView(value: progress.map { min(max($0, 0), 1) })
                .tint(Theme.accent)
                .accessibilityLabel("Progress")
                .accessibilityValue(presentation.statusText)

            TimelineView(.periodic(from: startedAt ?? .now, by: 1)) { context in
                let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            ProcessingProgressPresentation.elapsedText(elapsed),
                            systemImage: "clock"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Elapsed time")
                        Spacer()
                    }

                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow("Phase", phase.title)
                            detailRow("Elapsed", ProcessingProgressPresentation.elapsedText(elapsed))
                            if let diagnostics {
                                Divider()
                                DiagnosticsRowsView(diagnostics: diagnostics)
                            }
                            Text(phase.detailText)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    timelineControls
                }
                VStack(alignment: .leading, spacing: 10) {
                    timelineControls
                }
            }
        }
        .padding()
        .frame(maxWidth: 460, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var timelineControls: some View {
        if canCancel, let cancelAction {
            Button(action: cancelAction) {
                Label(cancelTitle, systemImage: "xmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Stops the current processing step and keeps saved audio or transcript work where available.")
        }
        if let retryAction {
            Button(action: retryAction) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Retries this processing step.")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
    }
}
