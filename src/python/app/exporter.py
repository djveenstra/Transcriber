from __future__ import annotations

import json as json_module
from app.merger import MergedSegment


def format_timestamp(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def format_srt_timestamp(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def friendly_speaker_name(raw: str) -> str:
    if raw.startswith("SPEAKER_"):
        try:
            num = int(raw.split("_")[1]) + 1
            return f"Speaker {num}"
        except (IndexError, ValueError):
            pass
    return raw


def display_name(raw: str, name_map: dict | None = None) -> str:
    """Resolve a raw speaker id to a display name.

    If the user has assigned a custom name (via name_map), use it;
    otherwise fall back to the friendly "Speaker N" label.
    """
    if name_map:
        custom = name_map.get(raw, "")
        if custom and custom.strip():
            return custom.strip()
    return friendly_speaker_name(raw)


def to_text(segments: list[MergedSegment], name_map: dict | None = None) -> str:
    lines = []
    for seg in segments:
        ts = format_timestamp(seg.start)
        speaker = display_name(seg.speaker, name_map)
        lines.append(f"[{ts}] {speaker}: {seg.text}")
    return "\n\n".join(lines)


def to_srt(segments: list[MergedSegment], name_map: dict | None = None) -> str:
    blocks = []
    for i, seg in enumerate(segments, 1):
        start = format_srt_timestamp(seg.start)
        end = format_srt_timestamp(seg.end)
        speaker = display_name(seg.speaker, name_map)
        blocks.append(f"{i}\n{start} --> {end}\n{speaker}: {seg.text}")
    return "\n\n".join(blocks)


def to_json(segments: list[MergedSegment], name_map: dict | None = None) -> str:
    data = [
        {
            "start": round(seg.start, 2),
            "end": round(seg.end, 2),
            "speaker": display_name(seg.speaker, name_map),
            "text": seg.text,
        }
        for seg in segments
    ]
    return json_module.dumps(data, indent=2, ensure_ascii=False)


EXPORTERS = {
    "txt": to_text,
    "srt": to_srt,
    "json": to_json,
}


def export(segments: list[MergedSegment], fmt: str, name_map: dict | None = None) -> str:
    return EXPORTERS[fmt](segments, name_map)
