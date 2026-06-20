import Foundation
import Testing
@testable import Transcriber

@MainActor
struct RecordingStatusTests {
    @Test func derivesStatusTruthTableFromRecordingAndActivityState() {
        let saved = makeRecording(segments: [])
        #expect(saved.recordingStatus == .recordingSaved)

        let needsTranscription = makeRecording(segments: [], transcriptionNeedsRetry: true)
        #expect(needsTranscription.recordingStatus == .needsTranscription)

        let failedLabels = makeRecording(
            segments: [segment(speaker: "SPEAKER_00")],
            diarizationNeedsRetry: true
        )
        #expect(failedLabels.recordingStatus == .speakerLabelsFailed)

        let complete = makeRecording(segments: [segment(speaker: "SPEAKER_00")])
        #expect(complete.recordingStatus == .complete)

        #expect(needsTranscription.recordingStatus(activity: .transcribing) == .transcribing)
        #expect(complete.recordingStatus(activity: .speakerLabeling) == .speakerLabeling)
    }

    @Test func eachStatusHasBadgeCopyAndSymbol() {
        let expected: [RecordingStatus: RecordingStatusDisplay] = [
            .recordingSaved: .init(title: "Recording saved", systemImage: "waveform"),
            .needsTranscription: .init(title: "Needs transcription", systemImage: "text.badge.exclamationmark"),
            .transcribing: .init(title: "Transcribing", systemImage: "text.quote"),
            .speakerLabeling: .init(title: "Speaker labeling", systemImage: "person.3.sequence.fill"),
            .speakerLabelsFailed: .init(title: "Speaker labels need retry", systemImage: "person.crop.circle.badge.exclamationmark"),
            .complete: .init(title: "Complete", systemImage: "checkmark.circle.fill"),
        ]

        for status in RecordingStatus.allCases {
            #expect(status.display == expected[status])
        }
    }

    @Test func metadataHelpersFormatDurationModelAndSpeakerLabels() {
        let recording = makeRecording(
            durationSeconds: 3_725.2,
            segments: [
                segment(speaker: "SPEAKER_00"),
                segment(speaker: "SPEAKER_01"),
            ],
            finalTranscriptionModelID: "parakeet-tdt-ctc-110m"
        )

        #expect(RecordingLibraryMetadata.durationText(seconds: recording.durationSeconds) == "1:02:05")
        #expect(RecordingLibraryMetadata.durationText(seconds: 65) == "1:05")
        #expect(RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID) == "Parakeet 110M - Lightweight")
        #expect(RecordingLibraryMetadata.modelName(for: "") == "Model not recorded")
        #expect(RecordingLibraryMetadata.modelName(for: "removed-model") == "Unknown model")
        #expect(RecordingLibraryMetadata.speakerLabelText(for: recording, status: .complete) == "2 speaker labels")
        #expect(RecordingLibraryMetadata.speakerLabelText(for: recording, status: .speakerLabelsFailed) == "Speaker labels need retry")
        #expect(RecordingLibraryMetadata.speakerLabelText(for: recording, status: .speakerLabeling) == "Identifying speakers")
    }

    @Test func missingAudioReconciliationReportsRowsWithoutMutatingThem() {
        let intact = makeRecording(
            audioFileName: "intact.caf",
            segments: [segment(speaker: "SPEAKER_00")],
            finalTranscriptionModelID: "base.en"
        )
        let missing = makeRecording(
            audioFileName: "missing.caf",
            segments: [segment(speaker: "SPEAKER_01")],
            finalTranscriptionModelID: "parakeet-tdt-v2"
        )
        let originalMissingSegments = missing.segments
        let originalMissingModelID = missing.finalTranscriptionModelID

        let missingNames = RecordingAudioReconciliation.missingAudioFileNames(
            in: [intact, missing]
        ) { path in
            path.hasSuffix("intact.caf")
        }

        #expect(missingNames == Set(["missing.caf"]))
        #expect(missing.segments == originalMissingSegments)
        #expect(missing.finalTranscriptionModelID == originalMissingModelID)
        #expect(!missing.transcriptionNeedsRetry)
        #expect(!missing.diarizationNeedsRetry)
    }

    private func makeRecording(
        durationSeconds: Double = 42,
        audioFileName: String = "recording.caf",
        segments: [TranscriptSegment],
        transcriptionNeedsRetry: Bool = false,
        diarizationNeedsRetry: Bool = false,
        finalTranscriptionModelID: String = ""
    ) -> Recording {
        Recording(
            title: "Fixture",
            durationSeconds: durationSeconds,
            audioFileName: audioFileName,
            segments: segments,
            transcriptionNeedsRetry: transcriptionNeedsRetry,
            diarizationNeedsRetry: diarizationNeedsRetry,
            finalTranscriptionModelID: finalTranscriptionModelID
        )
    }

    private func segment(speaker: String) -> TranscriptSegment {
        TranscriptSegment(startMs: 0, endMs: 1_000, speaker: speaker, text: "Hello")
    }
}
