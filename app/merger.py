from dataclasses import dataclass
from app.transcriber import TranscriptionSegment
from app.diarizer import DiarizationSegment


@dataclass
class MergedSegment:
    start: float
    end: float
    speaker: str
    text: str


def compute_overlap(s1_start: float, s1_end: float, s2_start: float, s2_end: float) -> float:
    overlap_start = max(s1_start, s2_start)
    overlap_end = min(s1_end, s2_end)
    return max(0.0, overlap_end - overlap_start)


def filter_short_segments(
    diarization: list[DiarizationSegment],
    min_duration: float = 0.5,
) -> list[DiarizationSegment]:
    """Remove diarization segments shorter than min_duration seconds.

    Pyannote sometimes emits sub-500ms micro-segments from breaths,
    background noise, or segmentation artifacts.  These pollute speaker
    clustering and cause phantom speakers.  Filtering them before
    speaker assignment lets the Unknown-gap filler assign those time
    ranges to the correct neighbouring speaker instead.
    """
    return [seg for seg in diarization if (seg.end - seg.start) >= min_duration]


def assign_speakers(
    diarization: list[DiarizationSegment],
    transcription: list[TranscriptionSegment],
) -> list[MergedSegment]:
    results = []
    for tseg in transcription:
        best_speaker = "Unknown"
        best_overlap = 0.0
        for dseg in diarization:
            overlap = compute_overlap(tseg.start, tseg.end, dseg.start, dseg.end)
            if overlap > best_overlap:
                best_overlap = overlap
                best_speaker = dseg.speaker
        results.append(MergedSegment(
            start=tseg.start,
            end=tseg.end,
            speaker=best_speaker,
            text=tseg.text,
        ))
    return results


def fill_unknown_gaps(segments: list[MergedSegment]) -> list[MergedSegment]:
    """Replace 'Unknown' speaker labels with the nearest known speaker.

    For each Unknown segment, look at the previous and next segments
    that have a known speaker.  Pick whichever is closer in time;
    if equidistant, prefer the previous speaker (conversation usually
    continues with the same person).

    If every segment is Unknown (no diarization data at all), they are
    left unchanged.
    """
    if not segments:
        return []

    # Check if there are any known speakers at all
    known_speakers = [s for s in segments if s.speaker != "Unknown"]
    if not known_speakers:
        return segments  # nothing to fill from

    result = [MergedSegment(
        start=s.start, end=s.end, speaker=s.speaker, text=s.text,
    ) for s in segments]

    for i, seg in enumerate(result):
        if seg.speaker != "Unknown":
            continue

        # Find nearest known speaker before
        prev_speaker = None
        prev_dist = float("inf")
        for j in range(i - 1, -1, -1):
            if result[j].speaker != "Unknown":
                prev_speaker = result[j].speaker
                prev_dist = seg.start - result[j].end
                break

        # Find nearest known speaker after
        next_speaker = None
        next_dist = float("inf")
        for j in range(i + 1, len(result)):
            if result[j].speaker != "Unknown":
                next_speaker = result[j].speaker
                next_dist = result[j].start - seg.end
                break

        # Assign nearest; prefer previous if tied
        if prev_speaker is not None and next_speaker is not None:
            seg.speaker = prev_speaker if prev_dist <= next_dist else next_speaker
        elif prev_speaker is not None:
            seg.speaker = prev_speaker
        elif next_speaker is not None:
            seg.speaker = next_speaker

    return result


def smooth_speaker_flips(
    segments: list[MergedSegment],
    max_flip_duration: float = 2.0,
) -> list[MergedSegment]:
    """Reassign isolated short speaker flips to match their neighbours.

    Pattern detected:  [Speaker A] [Speaker B, < max_flip_duration] [Speaker A]
    The middle segment is almost always a diarization error, not a real
    sub-2-second interjection by a different person.  Reassigning it to
    Speaker A lets the subsequent merge_consecutive combine them all.
    """
    if len(segments) < 3:
        return segments

    result = [MergedSegment(
        start=s.start, end=s.end, speaker=s.speaker, text=s.text,
    ) for s in segments]

    for i in range(1, len(result) - 1):
        prev_speaker = result[i - 1].speaker
        next_speaker = result[i + 1].speaker
        curr_duration = result[i].end - result[i].start

        if (result[i].speaker != prev_speaker
                and prev_speaker == next_speaker
                and curr_duration < max_flip_duration):
            result[i].speaker = prev_speaker

    return result


def merge_consecutive(
    segments: list[MergedSegment],
    gap_threshold: float = 1.5,
) -> list[MergedSegment]:
    if not segments:
        return []
    merged = [MergedSegment(
        start=segments[0].start,
        end=segments[0].end,
        speaker=segments[0].speaker,
        text=segments[0].text,
    )]
    for seg in segments[1:]:
        prev = merged[-1]
        if seg.speaker == prev.speaker and (seg.start - prev.end) <= gap_threshold:
            prev.end = seg.end
            prev.text += " " + seg.text
        else:
            merged.append(MergedSegment(
                start=seg.start, end=seg.end,
                speaker=seg.speaker, text=seg.text,
            ))
    return merged


def merge_segments(
    diarization: list[DiarizationSegment],
    transcription: list[TranscriptionSegment],
    gap_threshold: float = 1.5,
    min_diar_duration: float = 0.5,
    max_flip_duration: float = 2.0,
) -> list[MergedSegment]:
    """Full post-processing pipeline: filter → assign → fill → merge → smooth → merge."""
    # Step 1: Filter noisy micro-segments from diarization
    filtered_diar = filter_short_segments(diarization, min_diar_duration)
    # Step 2: Assign speakers by temporal overlap
    assigned = assign_speakers(filtered_diar, transcription)
    # Step 3: Fill Unknown gaps with nearest known speaker
    filled = fill_unknown_gaps(assigned)
    # Step 4: Merge consecutive same-speaker segments
    merged = merge_consecutive(filled, gap_threshold)
    # Step 5: Smooth isolated short speaker flips
    smoothed = smooth_speaker_flips(merged, max_flip_duration)
    # Step 6: Re-merge after smoothing
    return merge_consecutive(smoothed, gap_threshold)
