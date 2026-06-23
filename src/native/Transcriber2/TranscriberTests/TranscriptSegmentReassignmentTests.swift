import AVFoundation
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

    @Test func transcriptAccessibilityLabelReadsSpeakerTimeTextAndEditState() {
        let segment = TranscriptSegment(
            startMs: 1_500,
            endMs: 4_000,
            speaker: "SPEAKER_00",
            text: "Hello from the transcript."
        )

        let label = TranscriptAccessibility.label(
            for: segment,
            speakerNames: ["SPEAKER_00": "Daniel"],
            canReassignSpeaker: true
        )

        #expect(label == "Daniel. 1 second to 4 seconds. Hello from the transcript. Speaker can be changed.")
    }

    @Test func speakerCueAddsNonColorSpeakerIdentity() {
        #expect(TranscriptAccessibility.speakerCue(for: "SPEAKER_00") == "S1")
        #expect(TranscriptAccessibility.speakerCue(for: "SPEAKER_01") == "S2")
        #expect(TranscriptAccessibility.speakerCue(for: "SPEAKER_00", names: ["SPEAKER_00": "Daniel Jones"]) == "DJ")
    }

    @Test func compactTranscriptActionsHaveAccessibleLabelsHintsAndIcons() {
        let actions: [CompactTranscriptAction] = [
            .play(isPlaying: false),
            .play(isPlaying: true),
            .editSpeakers,
            .renameSpeakers,
            .share,
            .newRecording,
            .transcribeRecording,
            .cancelProcessing,
        ]

        for action in actions {
            #expect(!action.label.isEmpty)
            #expect(!action.compactTitle.isEmpty)
            #expect(!action.hint.isEmpty)
            #expect(!action.systemImage.isEmpty)
        }

        #expect(CompactTranscriptAction.share.label == "Share Transcript")
        #expect(CompactTranscriptAction.newRecording.hint.contains("completed transcript"))
        #expect(CompactTranscriptAction.cancelProcessing.compactTitle == "Cancel")
        #expect(CompactTranscriptAction.cancelProcessing.hint.contains("processing"))
    }

    @Test func playbackFileInspectorReadsRecordedCAFDurations() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-playback-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        try file.write(from: buffer)

        let duration = try #require(AudioPlaybackFileInspector.duration(for: url))
        #expect(abs(duration - 1) < 0.01)
    }

    @Test func completedRecordingPlaybackCacheCreatesM4ADerivativeForRecordedCAF() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-playback-cache-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
        buffer.frameLength = 32_000
        try file.write(from: buffer)

        let playbackURL = try await CompletedRecordingPlaybackCache.playbackURL(for: url)
        defer { try? FileManager.default.removeItem(at: playbackURL) }

        #expect(playbackURL.pathExtension == "m4a")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: playbackURL.path))
        let duration = try #require(AudioPlaybackFileInspector.duration(for: playbackURL))
        #expect(abs(duration - 2) < 0.1)
    }

    @Test func completedRecordingPlaybackPresentationClampsAndFormatsTime() {
        #expect(CompletedRecordingPlaybackPresentation.clampedTime(-5, duration: 30) == 0)
        #expect(CompletedRecordingPlaybackPresentation.clampedTime(35, duration: 30) == 30)
        #expect(CompletedRecordingPlaybackPresentation.clampedTime(12, duration: 30) == 12)
        #expect(CompletedRecordingPlaybackPresentation.timeText(65) == "1:05")
        #expect(CompletedRecordingPlaybackPresentation.timeRangeText(currentTime: 5, duration: 65) == "0:05 / 1:05")
        #expect(CompletedRecordingPlaybackPresentation.accessibilityProgressValue(currentTime: 5, duration: 65) == "0:05 of 1:05")
    }
}
