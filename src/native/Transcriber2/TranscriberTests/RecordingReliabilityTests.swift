import Foundation
import Testing
@testable import Transcriber

@MainActor
struct RecordingReliabilityTests {
    @Test func recordingWindowClosePolicyProtectsActiveWork() {
        #expect(!TranscriptionSession.requiresCloseConfirmation(for: .idle, isIdentifyingSpeakers: false))
        #expect(TranscriptionSession.requiresCloseConfirmation(for: .preparing, isIdentifyingSpeakers: false))
        #expect(TranscriptionSession.requiresCloseConfirmation(for: .recording, isIdentifyingSpeakers: false))
        #expect(TranscriptionSession.requiresCloseConfirmation(
            for: .processing(.transcribing),
            isIdentifyingSpeakers: false
        ))
        #expect(TranscriptionSession.requiresCloseConfirmation(for: .completed, isIdentifyingSpeakers: true))
        #expect(!TranscriptionSession.requiresCloseConfirmation(for: .completed, isIdentifyingSpeakers: false))
        #expect(!TranscriptionSession.requiresCloseConfirmation(for: .failed("Retry"), isIdentifyingSpeakers: false))
    }

    @Test func interruptedRecordingCreatesRetryableLibraryRecordWithoutTranscriptData() {
        let audioURL = URL(fileURLWithPath: "/tmp/interrupted-recording.caf")

        let recording = RecordingInterruptionRecovery.makeRetryableRecording(
            title: "Interrupted",
            duration: 42,
            audioURL: audioURL,
            finalTranscriptionModelID: "parakeet-tdt-ctc-110m"
        )

        #expect(recording.audioFileName == "interrupted-recording.caf")
        #expect(recording.durationSeconds == 42)
        #expect(recording.transcriptionNeedsRetry)
        #expect(recording.segments.isEmpty)
        #expect(recording.rawTranscription.isEmpty)
        #expect(recording.finalTranscriptionModelID == "parakeet-tdt-ctc-110m")
    }

    @Test func interruptionFailureMessageExplainsSavedRetryableAudio() {
        let message = RecordingInterruptionRecovery.failureMessage(
            reason: .audioSessionInterrupted,
            writeErrorMessage: nil
        )

        #expect(message.contains("Recording stopped"))
        #expect(message.contains("captured audio was saved"))
        #expect(message.contains("transcribed from the Library"))
    }

    @Test func interruptionFailureMessageIncludesIncompleteFileWarningOnWriteError() {
        let message = RecordingInterruptionRecovery.failureMessage(
            reason: .mediaServicesReset,
            writeErrorMessage: "disk write failed"
        )

        #expect(message.contains("iOS reset audio services"))
        #expect(message.contains("audio file may be incomplete"))
        #expect(message.contains("disk write failed"))
    }

    @Test func unavailableSaveContextMessageDoesNotClaimLibraryPersistence() {
        let message = RecordingInterruptionRecovery.unavailableSaveContextMessage(
            reason: .audioSessionInterrupted
        )

        #expect(message.contains("remains on disk"))
        #expect(message.contains("could not be added to the Library automatically"))
    }
}
