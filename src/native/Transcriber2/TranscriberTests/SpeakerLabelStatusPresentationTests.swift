import Foundation
import Testing
@testable import Transcriber

struct SpeakerLabelStatusPresentationTests {
    @Test func sharedPresentationCoversRequiredSpeakerLabelStates() {
        let approximate = SpeakerLabelStatusPresentation.make(
            status: .complete,
            speakerCount: 2,
            completionNote: "Speaker labels are approximate because the detailed pass took too long."
        )
        #expect(approximate.kind == .approximate)
        #expect(approximate.title == "Speaker labels approximate")
        #expect(!approximate.showsRetry)
        #expect(approximate.needsAttention)

        let failed = SpeakerLabelStatusPresentation.make(
            status: .speakerLabelsFailed,
            speakerCount: 2,
            diarizationNeedsRetry: true,
            completionNote: "Speaker labeling could not finish. Your transcript remains saved."
        )
        #expect(failed.kind == .failed)
        #expect(failed.title == "Speaker labels need retry")
        #expect(failed.showsRetry)

        let canceled = SpeakerLabelStatusPresentation.make(
            status: .complete,
            speakerCount: 1,
            diarizationNeedsRetry: true,
            completionNote: "Speaker labeling was canceled. Your transcript is available and speaker labels can be retried later."
        )
        #expect(canceled.kind == .canceled)
        #expect(canceled.compactText == "Speaker labels need retry")
        #expect(canceled.showsRetry)

        let retryable = SpeakerLabelStatusPresentation.make(
            status: .speakerLabelsFailed,
            speakerCount: 1,
            diarizationNeedsRetry: true
        )
        #expect(retryable.kind == .retryable)
        #expect(retryable.detail.contains("without re-running transcription"))

        let active = SpeakerLabelStatusPresentation.make(status: .speakerLabeling, speakerCount: 2)
        #expect(active.kind == .identifying)
        #expect(active.compactText == "Identifying speakers")

        let complete = SpeakerLabelStatusPresentation.make(status: .complete, speakerCount: 2)
        #expect(complete.kind == .complete)
        #expect(complete.compactText == "2 speaker labels")
        #expect(!complete.needsAttention)
    }

    @Test func recordingMetadataUsesSharedSpeakerLabelCompactText() {
        let recording = Recording(
            title: "Interview",
            durationSeconds: 2,
            audioFileName: "interview.caf",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Hi"),
                TranscriptSegment(startMs: 1_000, endMs: 2_000, speaker: "SPEAKER_01", text: "Hello"),
            ]
        )

        let helperText = SpeakerLabelStatusPresentation.make(
            status: .complete,
            speakerCount: 2
        ).compactText

        #expect(RecordingLibraryMetadata.speakerLabelText(for: recording, status: .complete) == helperText)
        #expect(RecordingLibraryMetadata.speakerLabelText(for: recording, status: .speakerLabelsFailed) == "Speaker labels need retry")
    }

    @Test func editAvailabilityRequiresPersistedEditableTranscriptSegments() {
        #expect(TranscriptEditingAvailability.canRenameOrReassignSpeakers(
            segmentCount: 1,
            isPersistedEditableRecording: true
        ))
        #expect(!TranscriptEditingAvailability.canRenameOrReassignSpeakers(
            segmentCount: 0,
            isPersistedEditableRecording: true
        ))
        #expect(!TranscriptEditingAvailability.canRenameOrReassignSpeakers(
            segmentCount: 1,
            isPersistedEditableRecording: false
        ))
    }
}
