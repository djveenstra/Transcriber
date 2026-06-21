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

    @Test func jsonExportProducesCodableSegmentArrayWithCompatibleShape() throws {
        let json = TranscriptExporter.export(segments, as: .json)
        let data = Data(json.utf8)
        let entries = try JSONDecoder().decode([TranscriptExporter.ExportedSegment].self, from: data)

        #expect(entries.count == 2)
        #expect(entries[0] == TranscriptExporter.ExportedSegment(
            start: 0,
            end: 1.5,
            speaker: "Speaker 1",
            text: "Hello there"
        ))
        #expect(json.contains("\"start\""))
        #expect(json.contains("\"end\""))
        #expect(json.contains("\"speaker\""))
        #expect(json.contains("\"text\""))
    }

    @Test func displayNamePrefersCustomNamesOverDefaults() {
        #expect(TranscriptExporter.displayName("SPEAKER_00", names: ["SPEAKER_00": "Daniel"]) == "Daniel")
        #expect(TranscriptExporter.displayName("SPEAKER_02", names: [:]) == "Speaker 3")
        #expect(TranscriptExporter.displayName("S1", names: [:]) == "Speaker 1")
    }

    @Test func exportsReflectReassignedSpeakers() throws {
        let reassigned = TranscriptSegmentReassignment.reassign(
            segmentID: segments[1].id,
            to: "SPEAKER_00",
            in: segments
        )

        let text = TranscriptExporter.export(reassigned, as: .text)
        let srt = TranscriptExporter.export(reassigned, as: .subtitles)
        let json = TranscriptExporter.export(reassigned, as: .json)
        let entries = try JSONDecoder().decode([TranscriptExporter.ExportedSegment].self, from: Data(json.utf8))

        #expect(text.contains("[0:01] Speaker 1: Hi"))
        #expect(srt.contains("00:00:01,500 --> 00:00:04,000\nSpeaker 1: Hi"))
        #expect(entries[1].speaker == "Speaker 1")
        #expect(entries[1].text == "Hi")
    }

    @Test func renamedSpeakersExportInEveryFormat() throws {
        let names = ["SPEAKER_00": "Daniel", "SPEAKER_01": "Alex"]

        let text = TranscriptExporter.export(segments, speakerNames: names, as: .text)
        let srt = TranscriptExporter.export(segments, speakerNames: names, as: .subtitles)
        let json = TranscriptExporter.export(segments, speakerNames: names, as: .json)
        let entries = try JSONDecoder().decode([TranscriptExporter.ExportedSegment].self, from: Data(json.utf8))

        #expect(text.contains("[0:00] Daniel: Hello there"))
        #expect(text.contains("[0:01] Alex: Hi"))
        #expect(srt.contains("00:00:00,000 --> 00:00:01,500\nDaniel: Hello there"))
        #expect(srt.contains("00:00:01,500 --> 00:00:04,000\nAlex: Hi"))
        #expect(entries.map(\.speaker) == ["Daniel", "Alex"])
    }

    @Test func renamedSpeakerAndReassignedSegmentExportTogether() throws {
        let reassigned = TranscriptSegmentReassignment.reassign(
            segmentID: segments[1].id,
            to: "SPEAKER_00",
            in: segments
        )
        let names = ["SPEAKER_00": "Daniel"]

        let text = TranscriptExporter.export(reassigned, speakerNames: names, as: .text)
        let srt = TranscriptExporter.export(reassigned, speakerNames: names, as: .subtitles)
        let json = TranscriptExporter.export(reassigned, speakerNames: names, as: .json)
        let entries = try JSONDecoder().decode([TranscriptExporter.ExportedSegment].self, from: Data(json.utf8))

        #expect(text.contains("[0:00] Daniel: Hello there"))
        #expect(text.contains("[0:01] Daniel: Hi"))
        #expect(srt.contains("Daniel: Hi"))
        #expect(entries[0].speaker == "Daniel")
        #expect(entries[1].speaker == "Daniel")
    }

    @Test func subtitlesExportFormatsMillisecondsAndHours() {
        let longSegments = [
            TranscriptSegment(startMs: 3_723_004, endMs: 3_724_567, speaker: "SPEAKER_00", text: "Past the hour"),
        ]

        let srt = TranscriptExporter.export(longSegments, as: .subtitles)

        #expect(srt == "1\n01:02:03,004 --> 01:02:04,567\nSpeaker 1: Past the hour")
    }

    @Test func subtitlesExportKeepsSequentialNumbersAndTimestampSyntax() {
        let srt = TranscriptExporter.export(segments, as: .subtitles)
        let blocks = srt.components(separatedBy: "\n\n")

        #expect(blocks[0].hasPrefix("1\n00:00:00,000 --> 00:00:01,500\n"))
        #expect(blocks[1].hasPrefix("2\n00:00:01,500 --> 00:00:04,000\n"))
    }
}
