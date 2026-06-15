import Testing
@testable import Transcriber

struct TranscriptMergerTests {
    @Test func removesTinySpeakerFlipAndMergesConversation() {
        let transcription = [
            TranscriptionSegment(startMs: 0, endMs: 4_000, text: "Hello"),
            TranscriptionSegment(startMs: 4_500, endMs: 6_000, text: "how are you"),
            TranscriptionSegment(startMs: 6_500, endMs: 9_000, text: "I am fine"),
        ]
        let diarization = [
            DiarizationSegment(startMs: 0, endMs: 5_000, speaker: "S1"),
            DiarizationSegment(startMs: 5_000, endMs: 5_200, speaker: "S2"),
            DiarizationSegment(startMs: 5_200, endMs: 10_000, speaker: "S1"),
        ]

        let result = TranscriptMerger.merge(transcription: transcription, diarization: diarization)

        #expect(result.count == 1)
        #expect(result[0].speaker == "S1")
        #expect(result[0].text == "Hello how are you I am fine")
    }

    @Test func exporterCreatesSpeakerLabeledText() {
        let segment = TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "S1", text: "Hello")
        #expect(TranscriptExporter.export([segment], as: .text).contains("Speaker 1: Hello"))
    }

    @Test func splitsLongWhisperParagraphAcrossSpeakers() {
        let transcription = [
            TranscriptionSegment(
                startMs: 0,
                endMs: 12_000,
                text: "Are you working now? No, not yet. Should I try again? Yes, please."
            )
        ]
        let diarization = [
            DiarizationSegment(startMs: 0, endMs: 3_300, speaker: "S1"),
            DiarizationSegment(startMs: 3_300, endMs: 5_500, speaker: "S2"),
            DiarizationSegment(startMs: 5_500, endMs: 9_300, speaker: "S1"),
            DiarizationSegment(startMs: 9_300, endMs: 12_000, speaker: "S2"),
        ]

        let result = TranscriptMerger.merge(transcription: transcription, diarization: diarization)

        #expect(result.map(\.speaker) == ["S1", "S2", "S1", "S2"])
        #expect(result.map(\.text) == [
            "Are you working now?",
            "No, not yet.",
            "Should I try again?",
            "Yes, please.",
        ])
    }

    @Test func preservesShortRealReply() {
        let transcription = [
            TranscriptionSegment(startMs: 0, endMs: 2_000, text: "Did it work?"),
            TranscriptionSegment(startMs: 2_000, endMs: 3_000, text: "No."),
            TranscriptionSegment(startMs: 3_000, endMs: 5_000, text: "I will try again."),
        ]
        let diarization = [
            DiarizationSegment(startMs: 0, endMs: 2_000, speaker: "S1"),
            DiarizationSegment(startMs: 2_000, endMs: 3_000, speaker: "S2"),
            DiarizationSegment(startMs: 3_000, endMs: 5_000, speaker: "S1"),
        ]

        let result = TranscriptMerger.merge(transcription: transcription, diarization: diarization)

        #expect(result.map(\.speaker) == ["S1", "S2", "S1"])
        #expect(result[1].text == "No.")
    }

    @Test func preservesFourDistinctSortformerSpeakers() {
        let transcription = (0..<4).map {
            TranscriptionSegment(startMs: $0 * 2_000, endMs: ($0 + 1) * 2_000, text: "Speaker \($0)")
        }
        let diarization = (0..<4).map {
            DiarizationSegment(startMs: $0 * 2_000, endMs: ($0 + 1) * 2_000, speaker: "SPEAKER_0\($0)")
        }

        let result = TranscriptMerger.merge(transcription: transcription, diarization: diarization)

        #expect(result.map(\.speaker) == ["SPEAKER_00", "SPEAKER_01", "SPEAKER_02", "SPEAKER_03"])
    }

    @Test func recordingPersistsRawWhisperTimingForDiarizationRetry() {
        let raw = [TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Hello")]
        let recording = Recording(
            title: "Test",
            durationSeconds: 1,
            audioFileName: "test.caf",
            segments: [],
            rawTranscription: raw,
            diarizationNeedsRetry: true
        )

        #expect(recording.rawTranscription == raw)
        #expect(recording.diarizationNeedsRetry)
    }

    @Test func emptyDiarizationBecomesSingleSpeakerTranscript() {
        let transcription = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Welcome"),
            TranscriptionSegment(startMs: 1_200, endMs: 2_000, text: "to the lecture"),
        ]

        let result = TranscriptMerger.merge(transcription: transcription, diarization: [])

        #expect(result.count == 1)
        #expect(result[0].speaker == "SPEAKER_00")
        #expect(result[0].text == "Welcome to the lecture")
    }

    @Test func recordingCanPersistBeforeTranscriptionFinishes() {
        let recording = Recording(
            title: "Protected recording",
            durationSeconds: 42,
            audioFileName: "protected.caf",
            segments: [],
            transcriptionNeedsRetry: true
        )

        #expect(recording.segments.isEmpty)
        #expect(recording.transcriptionNeedsRetry)
        #expect(!recording.diarizationNeedsRetry)
    }

    @Test func recordingPersistsFinalTranscriptionModel() {
        let recording = Recording(
            title: "Model metadata",
            durationSeconds: 1,
            audioFileName: "model.caf",
            segments: [],
            finalTranscriptionModelID: "parakeet-tdt-ctc-110m"
        )

        #expect(recording.finalTranscriptionModelID == "parakeet-tdt-ctc-110m")
    }

    @Test func finalModelCatalogKeepsWhisperDefaultAndAddsParakeet() {
        #expect(FinalTranscriptionModelChoice.defaultID == WhisperModelChoice.defaultID)
        #expect(FinalTranscriptionModelChoice.parakeet.count == 3)
        #expect(FinalTranscriptionModelChoice.whisper.count == 5)
        #expect(FinalTranscriptionModelChoice.all.count == 8)
    }
}
