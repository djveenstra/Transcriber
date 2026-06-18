import Foundation

nonisolated enum TranscriptMerger {
    static func merge(
        transcription: [TranscriptionSegment],
        diarization: [DiarizationSegment],
        minimumDiarizationMs: Int = 200,
        gapThresholdMs: Int = 1_500,
        maximumFlipMs: Int = 400
    ) -> [TranscriptSegment] {
        guard !diarization.isEmpty else {
            return mergeConsecutive(
                transcription.map {
                    TranscriptSegment(
                        startMs: $0.startMs,
                        endMs: $0.endMs,
                        speaker: "SPEAKER_00",
                        text: $0.text
                    )
                },
                gapThresholdMs: gapThresholdMs
            )
        }
        let filtered = diarization.filter { $0.endMs - $0.startMs >= minimumDiarizationMs }
        let timedPieces = transcription.flatMap(splitLongSegment)
        var assigned = timedPieces.map { transcript in
            let speaker = filtered.max { first, second in
                overlap(transcript, first) < overlap(transcript, second)
            }.flatMap { overlap(transcript, $0) > 0 ? $0.speaker : nil } ?? "Unknown"
            return TranscriptSegment(
                startMs: transcript.startMs,
                endMs: transcript.endMs,
                speaker: speaker,
                text: transcript.text
            )
        }

        fillUnknownSpeakers(&assigned)
        assigned = mergeConsecutive(assigned, gapThresholdMs: gapThresholdMs)
        smoothShortFlips(&assigned, maximumFlipMs: maximumFlipMs)
        return mergeConsecutive(assigned, gapThresholdMs: gapThresholdMs)
    }

    private static func splitLongSegment(_ segment: TranscriptionSegment) -> [TranscriptionSegment] {
        guard segment.endMs - segment.startMs > 4_000 else { return [segment] }

        let textPieces = sentencePieces(from: segment.text)
        guard textPieces.count > 1 else { return [segment] }

        let duration = segment.endMs - segment.startMs
        let totalWeight = textPieces.reduce(0) { $0 + max(1, $1.count) }
        var elapsedWeight = 0

        return textPieces.enumerated().map { index, text in
            let startMs = segment.startMs + duration * elapsedWeight / totalWeight
            elapsedWeight += max(1, text.count)
            let endMs = index == textPieces.indices.last
                ? segment.endMs
                : segment.startMs + duration * elapsedWeight / totalWeight
            return TranscriptionSegment(startMs: startMs, endMs: endMs, text: text)
        }
    }

    private static func sentencePieces(from text: String) -> [String] {
        var result: [String] = []
        var current = ""

        func appendCurrent() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                result.append(piece)
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if character == "." || character == "?" || character == "!" {
                appendCurrent()
            }
        }
        appendCurrent()
        return result
    }

    private static func overlap(_ transcript: TranscriptionSegment, _ speaker: DiarizationSegment) -> Int {
        max(0, min(transcript.endMs, speaker.endMs) - max(transcript.startMs, speaker.startMs))
    }

    private static func fillUnknownSpeakers(_ segments: inout [TranscriptSegment]) {
        guard segments.contains(where: { $0.speaker != "Unknown" }) else { return }
        for index in segments.indices where segments[index].speaker == "Unknown" {
            let previous = segments[..<index].last(where: { $0.speaker != "Unknown" })
            let next = segments[(index + 1)...].first(where: { $0.speaker != "Unknown" })
            switch (previous, next) {
            case let (previous?, next?):
                let previousDistance = segments[index].startMs - previous.endMs
                let nextDistance = next.startMs - segments[index].endMs
                segments[index].speaker = previousDistance <= nextDistance ? previous.speaker : next.speaker
            case let (previous?, nil): segments[index].speaker = previous.speaker
            case let (nil, next?): segments[index].speaker = next.speaker
            default: break
            }
        }
    }

    private static func smoothShortFlips(_ segments: inout [TranscriptSegment], maximumFlipMs: Int) {
        guard segments.count >= 3 else { return }
        for index in 1..<(segments.count - 1)
        where segments[index - 1].speaker == segments[index + 1].speaker
            && segments[index].speaker != segments[index - 1].speaker
            && segments[index].endMs - segments[index].startMs < maximumFlipMs {
            segments[index].speaker = segments[index - 1].speaker
        }
    }

    private static func mergeConsecutive(
        _ segments: [TranscriptSegment],
        gapThresholdMs: Int
    ) -> [TranscriptSegment] {
        guard var current = segments.first else { return [] }
        var result: [TranscriptSegment] = []
        for segment in segments.dropFirst() {
            if segment.speaker == current.speaker && segment.startMs - current.endMs <= gapThresholdMs {
                current.endMs = segment.endMs
                current.text += " " + segment.text
            } else {
                result.append(current)
                current = segment
            }
        }
        result.append(current)
        return result
    }
}
