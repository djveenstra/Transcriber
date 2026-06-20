import Foundation
import Testing
@testable import Transcriber

@MainActor
struct TranscriptSegmentReassignmentTests {
    @Test func reassigningSegmentUpdatesOnlySpeakerAttribution() throws {
        let targetID = UUID()
        let segments = [
            TranscriptSegment(id: UUID(), startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Hello"),
            TranscriptSegment(id: targetID, startMs: 1_000, endMs: 2_500, speaker: "SPEAKER_01", text: "There"),
        ]

        let updated = TranscriptSegmentReassignment.reassign(
            segmentID: targetID,
            to: "SPEAKER_00",
            in: segments
        )

        #expect(updated[0] == segments[0])
        #expect(updated[1].id == segments[1].id)
        #expect(updated[1].startMs == segments[1].startMs)
        #expect(updated[1].endMs == segments[1].endMs)
        #expect(updated[1].text == segments[1].text)
        #expect(updated[1].speaker == "SPEAKER_00")
    }

    @Test func reassignmentPersistsThroughRecordingSegmentsBlob() {
        let targetID = UUID()
        let recording = Recording(
            title: "Interview",
            durationSeconds: 3,
            audioFileName: "interview.caf",
            segments: [
                TranscriptSegment(id: UUID(), startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Question"),
                TranscriptSegment(id: targetID, startMs: 1_000, endMs: 3_000, speaker: "SPEAKER_01", text: "Answer"),
            ]
        )

        TranscriptSegmentReassignment.reassign(segmentID: targetID, to: "SPEAKER_00", in: recording)

        #expect(recording.segments.map(\.speaker) == ["SPEAKER_00", "SPEAKER_00"])
        #expect(recording.segments.map(\.text) == ["Question", "Answer"])
    }

    @Test func reassignmentSurvivesEncodeDecodeRoundTrip() throws {
        let targetID = UUID()
        let reassigned = TranscriptSegmentReassignment.reassign(
            segmentID: targetID,
            to: "SPEAKER_02",
            in: [
                TranscriptSegment(id: UUID(), startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "First"),
                TranscriptSegment(id: targetID, startMs: 1_000, endMs: 2_000, speaker: "SPEAKER_01", text: "Second"),
            ]
        )

        let data = try JSONEncoder().encode(reassigned)
        let decoded = try JSONDecoder().decode([TranscriptSegment].self, from: data)

        #expect(decoded == reassigned)
        #expect(decoded[1].speaker == "SPEAKER_02")
        #expect(decoded[1].text == "Second")
    }

    @Test func availableSpeakersPreservesFirstAppearanceOrder() {
        let speakers = TranscriptSegmentReassignment.availableSpeakers(in: [
            TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_01", text: "One"),
            TranscriptSegment(startMs: 1_000, endMs: 2_000, speaker: "SPEAKER_00", text: "Two"),
            TranscriptSegment(startMs: 2_000, endMs: 3_000, speaker: "SPEAKER_01", text: "Three"),
        ])

        #expect(speakers == ["SPEAKER_01", "SPEAKER_00"])
    }
}
