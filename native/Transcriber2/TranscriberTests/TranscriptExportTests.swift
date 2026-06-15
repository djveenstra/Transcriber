import Foundation
import Testing
@testable import Transcriber

struct TranscriptExportTests {
    private let segments = [
        TranscriptSegment(startMs: 0, endMs: 1_500, speaker: "SPEAKER_00", text: "Hello there"),
        TranscriptSegment(startMs: 1_500, endMs: 4_000, speaker: "SPEAKER_01", text: "Hi"),
    ]

    @Test func textExportFormatsTimestampsAndSpeakers() {
        let text = TranscriptExporter.export(segments, as: .text)
        let lines = text.components(separatedBy: "\n\n")

        #expect(lines == [
            "[0:00] Speaker 1: Hello there",
            "[0:01] Speaker 2: Hi",
        ])
    }

    @Test func subtitlesExportIncludesIndexAndSrtTimestamps() {
        let srt = TranscriptExporter.export(segments, as: .subtitles)
        let blocks = srt.components(separatedBy: "\n\n")

        #expect(blocks == [
            "1\n00:00:00,000 --> 00:00:01,500\nSpeaker 1: Hello there",
            "2\n00:00:01,500 --> 00:00:04,000\nSpeaker 2: Hi",
        ])
    }

    @Test func jsonExportProducesArrayOfSegmentDictionaries() throws {
        let json = TranscriptExporter.export(segments, as: .json)
        let data = Data(json.utf8)
        let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(entries.count == 2)
        #expect(entries[0]["speaker"] as? String == "Speaker 1")
        #expect(entries[0]["text"] as? String == "Hello there")
        #expect(entries[0]["start"] as? Double == 0)
        #expect(entries[0]["end"] as? Double == 1.5)
    }

    @Test func displayNamePrefersCustomNamesOverDefaults() {
        #expect(TranscriptExporter.displayName("SPEAKER_00", names: ["SPEAKER_00": "Daniel"]) == "Daniel")
        #expect(TranscriptExporter.displayName("SPEAKER_02", names: [:]) == "Speaker 3")
        #expect(TranscriptExporter.displayName("S1", names: [:]) == "Speaker 1")
    }
}
