# Transcriber Mac

This repository contains the native Mac-focused Transcriber application.

## Active application

`src/native/Transcriber2/`

The app records or imports audio, preserves the original, transcribes locally with WhisperKit, applies FluidAudio speaker labels, and supports Library review, playback, speaker edits, Model Lab diagnostics, and TXT/SRT/JSON export.

The accuracy-expansion roadmap adds versioned processing artifacts, benchmarks, optional multiple transcription candidates, stronger diarization, conservative known-speaker identification, reconciliation, and uncertainty-focused review. It strengthens the current app rather than replacing it.

## Other workspaces and references

- `../iOS Transcriber/` owns the iOS product.
- `../Python Transcriber/` owns the independent legacy Python application.
- `src/legacy-ios/` is read-only historical reference pending an archive decision.
- `VoxBot Expanded PLN.md` and `Voiceprint PLN.md` are design references, not active authority.

## Governance

Start with [PRD.md](../PRD.md), [PLAN.md](../PLAN.md), [OBJECTIVE.md](../OBJECTIVE.md), and [AGENTS.md](../AGENTS.md).

## Xcode

Open `src/native/Transcriber2/Transcriber2.xcodeproj` and select the `Transcriber` scheme with a Mac destination.
