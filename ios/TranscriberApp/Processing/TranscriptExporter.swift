import Foundation

/// Supported export formats for transcripts.
enum ExportFormat: String, CaseIterable, Identifiable {
    case text = "txt"
    case srt = "srt"
    case json = "json"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Plain Text"
        case .srt: return "SRT Subtitles"
        case .json: return "JSON"
        }
    }

    var fileExtension: String { rawValue }

    var mimeType: String {
        switch self {
        case .text: return "text/plain"
        case .srt: return "application/x-subrip"
        case .json: return "application/json"
        }
    }
}

/// Exports transcript segments in various text formats.
class TranscriptExporter {

    /// Export segments in the specified format.
    static func export(segments: [MergedSegment], format: ExportFormat) -> String {
        switch format {
        case .text: return toText(segments)
        case .srt: return toSRT(segments)
        case .json: return toJSON(segments)
        }
    }

    /// Plain text format with timestamps and speaker labels.
    /// Example: [0:00] Speaker 1: Hello there
    static func toText(_ segments: [MergedSegment]) -> String {
        segments.map { seg in
            "[\(seg.timestamp)] \(seg.speakerName): \(seg.text)"
        }.joined(separator: "\n\n")
    }

    /// SRT subtitle format with speaker prefix.
    static func toSRT(_ segments: [MergedSegment]) -> String {
        segments.enumerated().map { i, seg in
            let start = srtTimestamp(ms: seg.startMs)
            let end = srtTimestamp(ms: seg.endMs)
            return "\(i + 1)\n\(start) --> \(end)\n\(seg.speakerName): \(seg.text)"
        }.joined(separator: "\n\n")
    }

    /// JSON array format.
    static func toJSON(_ segments: [MergedSegment]) -> String {
        let data = segments.map { seg -> [String: Any] in
            [
                "start": Double(seg.startMs) / 1000.0,
                "end": Double(seg.endMs) / 1000.0,
                "speaker": seg.speakerName,
                "text": seg.text,
            ]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }

    // MARK: - Helpers

    /// Convert milliseconds to SRT timestamp format: HH:MM:SS,mmm
    private static func srtTimestamp(ms: Int) -> String {
        let h = ms / 3_600_000
        let m = (ms % 3_600_000) / 60_000
        let s = (ms % 60_000) / 1_000
        let remainder = ms % 1_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, remainder)
    }
}
