import json
from app.merger import MergedSegment
from app.exporter import to_text, to_srt, to_json, friendly_speaker_name

SAMPLE = [
    MergedSegment(0, 5.5, "SPEAKER_00", "Hello there"),
    MergedSegment(6, 12.3, "SPEAKER_01", "Hi how are you"),
]


def test_to_text():
    result = to_text(SAMPLE)
    assert "[00:00:00] Speaker 1: Hello there" in result
    assert "[00:00:06] Speaker 2: Hi how are you" in result


def test_to_srt():
    result = to_srt(SAMPLE)
    assert "1\n00:00:00,000 --> 00:00:05,500\nSpeaker 1: Hello there" in result
    assert "2\n" in result


def test_to_json():
    result = to_json(SAMPLE)
    data = json.loads(result)
    assert len(data) == 2
    assert data[0]["speaker"] == "Speaker 1"
    assert data[0]["start"] == 0
    assert data[1]["text"] == "Hi how are you"


def test_friendly_speaker_name():
    assert friendly_speaker_name("SPEAKER_00") == "Speaker 1"
    assert friendly_speaker_name("SPEAKER_01") == "Speaker 2"
    assert friendly_speaker_name("Unknown") == "Unknown"
