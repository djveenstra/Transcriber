import Foundation

/// A final transcript segment with speaker label, timestamps, and text.
struct MergedSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let startMs: Int
    let endMs: Int
    let speaker: String
    let text: String

    init(startMs: Int, endMs: Int, speaker: String, text: String) {
        self.id = UUID()
        self.startMs = startMs
        self.endMs = endMs
        self.speaker = speaker
        self.text = text
    }

    /// Formatted timestamp string "M:SS" or "H:MM:SS"
    var timestamp: String {
        let totalSeconds = startMs / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Friendly speaker name: "SPEAKER_00" → "Speaker 1"
    var speakerName: String {
        if speaker.hasPrefix("SPEAKER_"),
           let numStr = speaker.split(separator: "_").last,
           let num = Int(numStr) {
            return "Speaker \(num + 1)"
        }
        return speaker
    }

    /// Speaker color index (for UI coloring)
    var speakerColorIndex: Int {
        if speaker.hasPrefix("SPEAKER_"),
           let numStr = speaker.split(separator: "_").last,
           let num = Int(numStr) {
            return num
        }
        return 0
    }

    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, startMs, endMs, speaker, text
    }
}

/// Aligns whisper transcription segments with diarization speaker segments.
/// Same algorithm as the Mac app's merger.py but in Swift.
class SegmentMerger {

    /// Merge transcription segments with diarization segments.
    ///
    /// For each transcription segment, find the diarization segment with
    /// the greatest temporal overlap and assign that speaker label.
    /// Then merge consecutive same-speaker segments within gapThresholdMs.
    ///
    /// - Parameters:
    ///   - transcription: Segments from Whisper (text + timestamps)
    ///   - diarization: Segments from diarization pipeline (speakers + timestamps)
    ///   - gapThresholdMs: Max gap between same-speaker segments to merge (default 1500ms)
    /// - Returns: Merged segments with speaker labels and text
    static func merge(
        transcription: [TranscriptionSegment],
        diarization: [DiarizationSegment],
        gapThresholdMs: Int = 1500
    ) -> [MergedSegment] {
        guard !transcription.isEmpty else { return [] }

        // Step 1: Assign speakers by temporal overlap
        var assigned: [MergedSegment] = []

        for tseg in transcription {
            var bestSpeaker = "Unknown"
            var bestOverlap = 0

            for dseg in diarization {
                let overlapStart = max(tseg.startMs, dseg.startMs)
                let overlapEnd = min(tseg.endMs, dseg.endMs)
                let overlap = max(0, overlapEnd - overlapStart)

                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = dseg.speaker
                }
            }

            assigned.append(MergedSegment(
                startMs: tseg.startMs,
                endMs: tseg.endMs,
                speaker: bestSpeaker,
                text: tseg.text
            ))
        }

        // Step 2: Merge consecutive same-speaker segments within gap threshold
        return mergeConsecutive(assigned, gapThresholdMs: gapThresholdMs)
    }

    /// Merge consecutive segments that have the same speaker and are close together.
    private static func mergeConsecutive(
        _ segments: [MergedSegment],
        gapThresholdMs: Int
    ) -> [MergedSegment] {
        guard var current = segments.first else { return [] }
        var merged: [MergedSegment] = []

        for seg in segments.dropFirst() {
            if seg.speaker == current.speaker &&
               (seg.startMs - current.endMs) <= gapThresholdMs {
                // Merge: combine text and extend time range
                current = MergedSegment(
                    startMs: current.startMs,
                    endMs: seg.endMs,
                    speaker: current.speaker,
                    text: current.text + " " + seg.text
                )
            } else {
                merged.append(current)
                current = seg
            }
        }
        merged.append(current)

        return merged
    }
}
