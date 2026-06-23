import Foundation
import Testing
@testable import Transcriber

struct ProcessingPhaseTests {
    @Test func processingPhaseCoversPRDCorePhases() {
        #expect(ProcessingPhase.allCases == [
            .savingRecording,
            .preparingModel,
            .transcribing,
            .savingTranscript,
            .identifyingSpeakers,
            .savingSpeakerLabels,
            .exporting
        ])
    }

    @Test func legacyProcessingMessagesMapToStructuredPhases() {
        #expect(ProcessingPhase.legacyPhase(for: "Importing audio") == .savingRecording)
        #expect(ProcessingPhase.legacyPhase(for: "Finalizing live transcript") == .preparingModel)
        #expect(ProcessingPhase.legacyPhase(for: "Preparing transcription") == .preparingModel)
        #expect(ProcessingPhase.legacyPhase(for: "Transcribing") == .transcribing)
        #expect(ProcessingPhase.legacyPhase(for: "Identifying speakers") == .identifyingSpeakers)
        #expect(ProcessingPhase.legacyPhase(for: "Saving") == .savingSpeakerLabels)
    }

    @Test func phaseDisplayCopyStaysHumanReadable() {
        #expect(ProcessingPhase.savingRecording.title == "Saving recording")
        #expect(ProcessingPhase.preparingModel.activityText == "Loading the on-device model")
        #expect(ProcessingPhase.transcribing.detailText.contains("saved audio"))
        #expect(ProcessingPhase.identifyingSpeakers.systemImage == "person.3")
    }

    @Test func elapsedTimeFormattingCoversMinutesAndHours() {
        #expect(ProcessingProgressPresentation.elapsedText(0) == "00:00")
        #expect(ProcessingProgressPresentation.elapsedText(65) == "01:05")
        #expect(ProcessingProgressPresentation.elapsedText(3_661) == "1:01:01")
    }

    @Test func progressPresentationClampsPercentAndFallsBackToActivity() {
        let active = ProcessingProgressPresentation(
            phase: .transcribing,
            progress: nil,
            canCancel: true,
            showsRetry: false
        )
        #expect(active.statusText == "Creating the transcript")

        let overComplete = ProcessingProgressPresentation(
            phase: .savingTranscript,
            progress: 1.4,
            canCancel: true,
            showsRetry: false
        )
        #expect(overComplete.statusText == "100%")
    }

    @Test func cancelAndRetryAffordanceVisibilityIsExplicit() {
        let retryable = ProcessingProgressPresentation(
            phase: .identifyingSpeakers,
            progress: 0.6,
            canCancel: true,
            showsRetry: true
        )

        #expect(retryable.canCancel)
        #expect(retryable.showsRetry)
    }

    @Test func progressAccessibilityValueIncludesPhaseProgressElapsedAndDetail() {
        let presentation = ProcessingProgressPresentation(
            phase: .transcribing,
            progress: 0.42,
            canCancel: true,
            showsRetry: false
        )

        #expect(presentation.accessibilityValue(elapsed: 65) == "Transcribing. Progress 42%. Elapsed 01:05. The final pass creates the transcript from the saved audio.")
    }

    @Test func transcriptionSessionProcessingStateCarriesPhase() {
        let state = TranscriptionSession.State.processing(.transcribing)

        if case let .processing(phase) = state {
            #expect(phase == .transcribing)
        } else {
            Issue.record("Expected processing state to carry a structured phase.")
        }
    }
}
