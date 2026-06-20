import SwiftUI

nonisolated enum SpeakerLabelStatusKind: Equatable, Sendable {
    case notAvailable
    case identifying
    case approximate
    case failed
    case canceled
    case retryable
    case complete
}

nonisolated struct SpeakerLabelStatusPresentation: Equatable, Sendable {
    let kind: SpeakerLabelStatusKind
    let title: String
    let detail: String
    let compactText: String
    let systemImage: String
    let showsRetry: Bool
    let needsAttention: Bool

    static func make(
        status: RecordingStatus,
        speakerCount: Int,
        diarizationNeedsRetry: Bool = false,
        completionNote: String? = nil
    ) -> SpeakerLabelStatusPresentation {
        if status == .speakerLabeling {
            return identifying
        }

        if diarizationNeedsRetry || status == .speakerLabelsFailed {
            return retryable(from: completionNote)
        }

        if let classified = classifiedNote(completionNote) {
            return classified
        }

        switch status {
        case .recordingSaved, .needsTranscription, .transcribing:
            return notAvailable
        case .speakerLabeling:
            return identifying
        case .speakerLabelsFailed:
            return retryable(from: completionNote)
        case .complete:
            return complete(speakerCount: speakerCount)
        }
    }

    static func makeForSession(
        isIdentifyingSpeakers: Bool,
        diarizationNeedsRetry: Bool,
        completionNote: String?,
        speakerCount: Int
    ) -> SpeakerLabelStatusPresentation {
        let status: RecordingStatus = isIdentifyingSpeakers ? .speakerLabeling : .complete
        return make(
            status: status,
            speakerCount: speakerCount,
            diarizationNeedsRetry: diarizationNeedsRetry,
            completionNote: completionNote
        )
    }

    static func complete(speakerCount: Int) -> SpeakerLabelStatusPresentation {
        let labelCount = speakerLabelCountText(speakerCount)
        return SpeakerLabelStatusPresentation(
            kind: .complete,
            title: "Speaker labels complete",
            detail: "\(labelCount) available.",
            compactText: labelCount,
            systemImage: "person.3.fill",
            showsRetry: false,
            needsAttention: false
        )
    }

    static var notAvailable: SpeakerLabelStatusPresentation {
        SpeakerLabelStatusPresentation(
            kind: .notAvailable,
            title: "Speaker labels not available",
            detail: "Create the transcript first.",
            compactText: "Speaker labels not available yet",
            systemImage: "person.3.fill",
            showsRetry: false,
            needsAttention: false
        )
    }

    static var identifying: SpeakerLabelStatusPresentation {
        SpeakerLabelStatusPresentation(
            kind: .identifying,
            title: "Identifying speakers",
            detail: "The transcript is ready. Speaker labels are being applied.",
            compactText: "Identifying speakers",
            systemImage: "person.3.sequence.fill",
            showsRetry: false,
            needsAttention: false
        )
    }

    private static func retryable(from note: String?) -> SpeakerLabelStatusPresentation {
        if let classified = classifiedNote(note), classified.showsRetry {
            return classified
        }
        return SpeakerLabelStatusPresentation(
            kind: .retryable,
            title: "Speaker labels need retry",
            detail: "The transcript is safe. Speaker labels can be retried without re-running transcription.",
            compactText: "Speaker labels need retry",
            systemImage: "person.crop.circle.badge.questionmark",
            showsRetry: true,
            needsAttention: true
        )
    }

    private static func classifiedNote(_ note: String?) -> SpeakerLabelStatusPresentation? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        let normalized = note.localizedLowercase

        if normalized.contains("canceled") {
            return SpeakerLabelStatusPresentation(
                kind: .canceled,
                title: "Speaker labeling canceled",
                detail: note,
                compactText: "Speaker labels need retry",
                systemImage: "person.crop.circle.badge.xmark",
                showsRetry: true,
                needsAttention: true
            )
        }

        if normalized.contains("could not finish") || normalized.contains("timed out") {
            return SpeakerLabelStatusPresentation(
                kind: .failed,
                title: "Speaker labels need retry",
                detail: note,
                compactText: "Speaker labels need retry",
                systemImage: "person.crop.circle.badge.exclamationmark",
                showsRetry: true,
                needsAttention: true
            )
        }

        if normalized.contains("approximate") || normalized.contains("faster pass") {
            return SpeakerLabelStatusPresentation(
                kind: .approximate,
                title: "Speaker labels approximate",
                detail: note,
                compactText: "Speaker labels approximate",
                systemImage: "person.crop.circle.badge.questionmark",
                showsRetry: false,
                needsAttention: true
            )
        }

        return nil
    }

    private static func speakerLabelCountText(_ count: Int) -> String {
        if count <= 0 { return "Speaker labels not available" }
        if count == 1 { return "1 speaker label" }
        return "\(count) speaker labels"
    }
}

nonisolated enum TranscriptEditingAvailability {
    static func canRenameOrReassignSpeakers(
        segmentCount: Int,
        isPersistedEditableRecording: Bool
    ) -> Bool {
        isPersistedEditableRecording && segmentCount > 0
    }
}

struct SpeakerLabelStatusView: View {
    let presentation: SpeakerLabelStatusPresentation
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(presentation.title, systemImage: presentation.systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(presentation.needsAttention ? .yellow : Theme.muted)
            Text(presentation.detail)
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.showsRetry, let retryAction {
                Button(action: retryAction) {
                    Label("Retry Speaker Labels", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(presentation.needsAttention ? Color.yellow.opacity(0.65) : Theme.border)
        )
    }
}
