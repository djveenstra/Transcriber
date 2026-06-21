import Foundation

nonisolated enum TranscriptExportFormat: String, CaseIterable, Identifiable, Sendable {
    case text = "txt"
    case subtitles = "srt"
    case json
    var id: Self { self }
}

nonisolated enum TranscriptExporter {
    struct ExportedSegment: Codable, Equatable, Sendable {
        let start: Double
        let end: Double
        let speaker: String
        let text: String
    }

    static func exportFile(
        _ segments: [TranscriptSegment],
        speakerNames: [String: String] = [:],
        as format: TranscriptExportFormat
    ) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriberExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = directory
            .appendingPathComponent("Transcript-\(formatter.string(from: .now))")
            .appendingPathExtension(format.rawValue)
        try? export(segments, speakerNames: speakerNames, as: format)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func export(
        _ segments: [TranscriptSegment],
        speakerNames: [String: String] = [:],
        as format: TranscriptExportFormat
    ) -> String {
        switch format {
        case .text:
            return segments.map {
                "[\($0.timestamp)] \(displayName($0.speaker, names: speakerNames)): \($0.text)"
            }.joined(separator: "\n\n")
        case .subtitles:
            return segments.enumerated().map { index, segment in
                "\(index + 1)\n\(srtTime(segment.startMs)) --> \(srtTime(segment.endMs))\n\(displayName(segment.speaker, names: speakerNames)): \(segment.text)"
            }.joined(separator: "\n\n")
        case .json:
            let values = segments.map {
                ExportedSegment(
                    start: Double($0.startMs) / 1_000,
                    end: Double($0.endMs) / 1_000,
                    speaker: displayName($0.speaker, names: speakerNames),
                    text: $0.text
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try? encoder.encode(values)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    static func displayName(_ speaker: String, names: [String: String]) -> String {
        if let name = names[speaker], !name.isEmpty { return name }
        if speaker.hasPrefix("SPEAKER_"), let number = Int(speaker.split(separator: "_").last ?? "") {
            return "Speaker \(number + 1)"
        }
        if speaker.hasPrefix("S"), let number = Int(speaker.dropFirst()) {
            return "Speaker \(number)"
        }
        return speaker
    }

    private static func srtTime(_ milliseconds: Int) -> String {
        String(
            format: "%02d:%02d:%02d,%03d",
            milliseconds / 3_600_000,
            (milliseconds % 3_600_000) / 60_000,
            (milliseconds % 60_000) / 1_000,
            milliseconds % 1_000
        )
    }
}
