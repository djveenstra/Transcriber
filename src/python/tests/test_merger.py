import pytest
from app.transcriber import TranscriptionSegment
from app.diarizer import DiarizationSegment
from app.merger import (
    compute_overlap, assign_speakers, merge_consecutive,
    merge_segments, MergedSegment, filter_short_segments,
    fill_unknown_gaps, smooth_speaker_flips,
)


class TestComputeOverlap:
    def test_full_overlap(self):
        assert compute_overlap(1.0, 3.0, 1.0, 3.0) == 2.0

    def test_partial_overlap(self):
        assert compute_overlap(1.0, 3.0, 2.0, 4.0) == 1.0

    def test_no_overlap(self):
        assert compute_overlap(1.0, 2.0, 3.0, 4.0) == 0.0

    def test_contained(self):
        assert compute_overlap(1.0, 5.0, 2.0, 3.0) == 1.0


class TestFilterShortSegments:
    def test_removes_short_segments(self):
        diar = [
            DiarizationSegment(0, 5, "A"),       # 5s — keep
            DiarizationSegment(5, 5.3, "B"),      # 0.3s — remove
            DiarizationSegment(5.3, 10, "A"),     # 4.7s — keep
        ]
        result = filter_short_segments(diar, min_duration=0.5)
        assert len(result) == 2
        assert result[0].speaker == "A"
        assert result[1].speaker == "A"

    def test_keeps_segments_at_threshold(self):
        diar = [DiarizationSegment(0, 0.5, "A")]  # exactly 0.5s
        result = filter_short_segments(diar, min_duration=0.5)
        assert len(result) == 1

    def test_removes_all_if_all_short(self):
        diar = [
            DiarizationSegment(0, 0.2, "A"),
            DiarizationSegment(0.3, 0.4, "B"),
        ]
        result = filter_short_segments(diar, min_duration=0.5)
        assert len(result) == 0

    def test_empty_input(self):
        assert filter_short_segments([]) == []

    def test_custom_threshold(self):
        diar = [
            DiarizationSegment(0, 0.8, "A"),   # 0.8s — keep at 0.3, remove at 1.0
            DiarizationSegment(1, 1.2, "B"),    # 0.2s — remove at 0.3
        ]
        result_low = filter_short_segments(diar, min_duration=0.3)
        assert len(result_low) == 1
        result_high = filter_short_segments(diar, min_duration=1.0)
        assert len(result_high) == 0


class TestAssignSpeakers:
    def test_simple_assignment(self):
        diar = [DiarizationSegment(0, 5, "SPEAKER_00"),
                DiarizationSegment(5, 10, "SPEAKER_01")]
        trans = [TranscriptionSegment(0.5, 4.5, "Hello"),
                 TranscriptionSegment(5.5, 9.5, "World")]
        result = assign_speakers(diar, trans)
        assert result[0].speaker == "SPEAKER_00"
        assert result[1].speaker == "SPEAKER_01"

    def test_majority_overlap(self):
        diar = [DiarizationSegment(0, 3, "SPEAKER_00"),
                DiarizationSegment(3, 10, "SPEAKER_01")]
        trans = [TranscriptionSegment(2, 6, "Overlapping")]
        result = assign_speakers(diar, trans)
        assert result[0].speaker == "SPEAKER_01"  # 3s overlap vs 1s

    def test_no_overlap_gives_unknown(self):
        diar = [DiarizationSegment(10, 20, "SPEAKER_00")]
        trans = [TranscriptionSegment(0, 5, "Before")]
        result = assign_speakers(diar, trans)
        assert result[0].speaker == "Unknown"

    def test_empty_inputs(self):
        assert assign_speakers([], []) == []
        assert assign_speakers([DiarizationSegment(0, 5, "A")], []) == []


class TestFillUnknownGaps:
    def test_fills_middle_unknown_with_nearest(self):
        segs = [
            MergedSegment(0, 2, "A", "Hello"),
            MergedSegment(2.5, 3, "Unknown", "Yes"),
            MergedSegment(5, 7, "B", "World"),
        ]
        result = fill_unknown_gaps(segs)
        # "Yes" at 2.5-3.0 is closer to A (ends at 2.0, dist=0.5)
        # than to B (starts at 5.0, dist=2.0)
        assert result[1].speaker == "A"

    def test_fills_unknown_at_start(self):
        segs = [
            MergedSegment(0, 1, "Unknown", "Um"),
            MergedSegment(2, 5, "A", "Hello"),
        ]
        result = fill_unknown_gaps(segs)
        assert result[0].speaker == "A"  # only option

    def test_fills_unknown_at_end(self):
        segs = [
            MergedSegment(0, 5, "A", "Hello"),
            MergedSegment(6, 7, "Unknown", "Bye"),
        ]
        result = fill_unknown_gaps(segs)
        assert result[1].speaker == "A"  # only option

    def test_prefers_previous_when_tied(self):
        segs = [
            MergedSegment(0, 2, "A", "Hello"),
            MergedSegment(3, 4, "Unknown", "Um"),
            MergedSegment(5, 7, "B", "World"),
        ]
        result = fill_unknown_gaps(segs)
        # Distance to A: 3.0 - 2.0 = 1.0
        # Distance to B: 5.0 - 4.0 = 1.0
        # Tied → prefer previous (A)
        assert result[1].speaker == "A"

    def test_all_unknown_stays_unknown(self):
        segs = [
            MergedSegment(0, 2, "Unknown", "Hello"),
            MergedSegment(3, 5, "Unknown", "World"),
        ]
        result = fill_unknown_gaps(segs)
        assert result[0].speaker == "Unknown"
        assert result[1].speaker == "Unknown"

    def test_multiple_unknowns_filled(self):
        segs = [
            MergedSegment(0, 2, "A", "Start"),
            MergedSegment(3, 4, "Unknown", "Um"),
            MergedSegment(5, 6, "Unknown", "Uh"),
            MergedSegment(8, 10, "B", "End"),
        ]
        result = fill_unknown_gaps(segs)
        # First Unknown [3,4]: closer to A (end=2, dist=1.0) than B (start=8, dist=4.0)
        assert result[1].speaker == "A"
        # Second Unknown [5,6]: A (via filled result[1] end=4, dist=1.0) vs B (start=8, dist=2.0)
        # Closer to A → fills to A. But let's also test a clear B case:

    def test_unknown_closer_to_next(self):
        segs = [
            MergedSegment(0, 2, "A", "Start"),
            MergedSegment(9, 9.5, "Unknown", "Uh"),
            MergedSegment(10, 15, "B", "End"),
        ]
        result = fill_unknown_gaps(segs)
        # Unknown [9, 9.5]: dist to A = 9.0 - 2.0 = 7.0, dist to B = 10.0 - 9.5 = 0.5
        assert result[1].speaker == "B"

    def test_empty_input(self):
        assert fill_unknown_gaps([]) == []


class TestSmoothSpeakerFlips:
    def test_smooths_short_flip(self):
        segs = [
            MergedSegment(0, 5, "A", "Hello"),
            MergedSegment(5, 5.8, "B", "um"),     # 0.8s flip
            MergedSegment(6, 10, "A", "world"),
        ]
        result = smooth_speaker_flips(segs, max_flip_duration=2.0)
        assert result[1].speaker == "A"  # reassigned

    def test_preserves_long_turn(self):
        segs = [
            MergedSegment(0, 5, "A", "Hello"),
            MergedSegment(5, 8, "B", "I disagree"),  # 3s — real turn
            MergedSegment(8, 12, "A", "But"),
        ]
        result = smooth_speaker_flips(segs, max_flip_duration=2.0)
        assert result[1].speaker == "B"  # preserved

    def test_preserves_real_speaker_change(self):
        segs = [
            MergedSegment(0, 5, "A", "Hello"),
            MergedSegment(5, 6, "B", "Hi"),          # short but...
            MergedSegment(6, 10, "B", "How are you"),  # ...continues as B
        ]
        result = smooth_speaker_flips(segs, max_flip_duration=2.0)
        # B→B transition means the middle is NOT isolated
        assert result[1].speaker == "B"  # preserved (neighbors differ)

    def test_fewer_than_three_segments(self):
        segs = [MergedSegment(0, 5, "A", "Hello")]
        assert smooth_speaker_flips(segs) == segs

        segs2 = [
            MergedSegment(0, 5, "A", "Hello"),
            MergedSegment(5, 6, "B", "Hi"),
        ]
        result = smooth_speaker_flips(segs2)
        assert len(result) == 2
        assert result[1].speaker == "B"  # can't smooth with only 2

    def test_empty_input(self):
        assert smooth_speaker_flips([]) == []


class TestMergeConsecutive:
    def test_merges_same_speaker(self):
        segs = [MergedSegment(0, 2, "A", "Hello"),
                MergedSegment(2.5, 4, "A", "world")]
        result = merge_consecutive(segs, gap_threshold=1.5)
        assert len(result) == 1
        assert result[0].text == "Hello world"
        assert result[0].end == 4

    def test_splits_different_speakers(self):
        segs = [MergedSegment(0, 2, "A", "Hello"),
                MergedSegment(2.5, 4, "B", "world")]
        result = merge_consecutive(segs, gap_threshold=1.5)
        assert len(result) == 2

    def test_splits_large_gap(self):
        segs = [MergedSegment(0, 2, "A", "Hello"),
                MergedSegment(5, 7, "A", "world")]
        result = merge_consecutive(segs, gap_threshold=1.5)
        assert len(result) == 2

    def test_empty(self):
        assert merge_consecutive([]) == []


class TestMergeSegmentsIntegration:
    """End-to-end tests for the full pipeline."""

    def test_noisy_diarization_cleaned_up(self):
        """Simulate pyannote output with a noisy micro-segment."""
        diar = [
            DiarizationSegment(0, 5, "SPEAKER_00"),
            DiarizationSegment(5, 5.2, "SPEAKER_02"),   # 0.2s noise
            DiarizationSegment(5.2, 10, "SPEAKER_00"),
        ]
        trans = [
            TranscriptionSegment(0, 4, "Hello there"),
            TranscriptionSegment(4.5, 6, "How are you"),
            TranscriptionSegment(6.5, 9, "I am fine"),
        ]
        result = merge_segments(diar, trans)
        # All should be SPEAKER_00 — the noise was filtered
        speakers = {seg.speaker for seg in result}
        assert speakers == {"SPEAKER_00"}

    def test_unknown_gaps_filled(self):
        """Transcription segment outside any diarization range gets filled."""
        diar = [
            DiarizationSegment(2, 8, "SPEAKER_00"),
        ]
        trans = [
            TranscriptionSegment(0, 1, "Before"),   # no overlap → Unknown → filled
            TranscriptionSegment(3, 7, "During"),
            TranscriptionSegment(9, 10, "After"),    # no overlap → Unknown → filled
        ]
        result = merge_segments(diar, trans)
        assert all(seg.speaker != "Unknown" for seg in result)

    def test_isolated_flip_smoothed(self):
        """A short interjection assigned to wrong speaker gets smoothed."""
        diar = [
            DiarizationSegment(0, 5, "SPEAKER_00"),
            DiarizationSegment(5, 5.8, "SPEAKER_01"),   # short flip
            DiarizationSegment(5.8, 12, "SPEAKER_00"),
        ]
        trans = [
            TranscriptionSegment(0, 4, "I was saying"),
            TranscriptionSegment(4.5, 6, "um"),
            TranscriptionSegment(6.5, 11, "that I agree"),
        ]
        result = merge_segments(diar, trans)
        # After smoothing, the short flip should be absorbed
        # We may end up with 1 or 2 segments, but all SPEAKER_00
        speakers = {seg.speaker for seg in result}
        assert speakers == {"SPEAKER_00"}
