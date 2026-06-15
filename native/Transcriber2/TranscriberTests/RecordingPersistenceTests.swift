import Foundation
import Testing
@testable import Transcriber

struct RecordingPersistenceTests {
    private func makeRecording() -> Recording {
        Recording(
            title: "Corrupt",
            durationSeconds: 1,
            audioFileName: "recording.caf",
            segments: []
        )
    }

    @Test func corruptTranscriptDataDecodesToEmptySegments() {
        let recording = makeRecording()
        recording.transcriptData = Data("not json".utf8)

        #expect(recording.segments.isEmpty)
    }

    @Test func corruptRawTranscriptionDataDecodesToEmptyArray() {
        let recording = makeRecording()
        recording.rawTranscriptionData = Data("not json".utf8)

        #expect(recording.rawTranscription.isEmpty)
    }

    @Test func corruptSpeakerNamesDataDecodesToEmptyDictionary() {
        let recording = makeRecording()
        recording.speakerNamesData = Data("not json".utf8)

        #expect(recording.speakerNames.isEmpty)
    }

    @Test func segmentsRoundTripThroughSetterAndGetter() {
        let recording = makeRecording()
        let segments = [TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "S1", text: "Hello")]

        recording.segments = segments

        #expect(recording.segments == segments)
    }

    @Test func speakerNamesRoundTripThroughSetterAndGetter() {
        let recording = makeRecording()

        recording.speakerNames = ["SPEAKER_00": "Daniel"]

        #expect(recording.speakerNames == ["SPEAKER_00": "Daniel"])
    }

    @Test func rawTranscriptionRoundTripsThroughSetterAndGetter() {
        let recording = makeRecording()
        let raw = [TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Hello")]

        recording.rawTranscription = raw

        #expect(recording.rawTranscription == raw)
    }
}
