# Architecture Review — Current Transcriber Mac Baseline

Last reviewed: 2026-07-28

This document describes the checked-out code in `src/native/Transcriber2/`. It is not a future architecture proposal.

## 1. Product shell

- `Transcriber2App` creates a SwiftData container for `Recording`, refreshes model status, and starts Mac launch readiness.
- `RootView` exposes Dashboard, Library, Model Lab, and Settings tabs.
- Recording and import open `RecordingView` as a sheet.
- `LibraryView` provides chronological recordings, playback, transcript review, speaker edits, retry, sharing, and deletion.
- `ModelLabView` compares supported Mac Whisper choices and exports diagnostic reports.
- The app uses a shared dark midnight-blue visual system.

This shell is useful and should be extended rather than replaced.

## 2. Data and files

### SwiftData

`Recording` stores:

- Title, date, duration, and audio filename.
- JSON-backed final transcript segments.
- JSON-backed raw timed transcription segments.
- JSON-backed speaker display-name mappings.
- Transcription and diarization retry flags.
- Final transcription model ID.

Computed accessors decode failures safely to empty values and avoid overwriting a prior blob when encoding a replacement fails.

### Audio

Application-owned audio lives under:

`Application Support/Transcriber2Beta/Recordings/`

The audio filename links a `Recording` row to the preserved file. Recorded CAF files may receive regenerable M4A playback derivatives; the original remains the source of truth.

### Current limitation

The model is adequate for the current single-result workflow but not for multiple raw model outputs, prepared-audio versions, transcript versions, identity evidence, calibration, or full provenance. Adding all future material as more opaque SwiftData blobs would create migration and inspection risk. PLAN VX-03/VX-05 therefore introduce a versioned artifact design while keeping existing fields readable.

## 3. Processing architecture

### `TranscriptionSession`

`TranscriptionSession` is a `@MainActor ObservableObject` and the UI-facing state machine. It currently coordinates:

- Recording and import.
- Live preview.
- Final-model preflight, load, transcription, and unload.
- Persist-before-process checkpoints.
- Diarization, fallback, stage watchdogs, and retry guards.
- Cancellation and stale-attempt protection.
- Progress, diagnostics, UI notices, and SwiftData persistence.

At roughly 1,900 lines, it is the largest concentration of risk. It also contains behavior that has substantial test coverage. The safe path is extraction behind characterization tests, not replacement.

### Transcription

`TranscriptionEngine` is an actor protocol. `WhisperKitTranscriptionEngine` implements Mac live and file transcription, rolling-window timestamp correction, word-timed results, and an inference semaphore.

FluidAudio Parakeet live/final engines exist, but platform conditionals keep important use paths iOS-specific. Enabling Parakeet on Mac is therefore a feasibility/integration objective, not a settings change.

### Diarization

`DiarizationEngine` is an actor protocol. `FluidDiarizationEngine` converts input to 16 kHz mono and runs Sortformer with stage reporting. `TranscriptionSession` adds:

- Stage-specific timeouts.
- Cancellation.
- Protection against overlapping unsafe retries.
- Balanced-to-fast fallback only when safe.
- Transcript preservation if labels fail.

### Merge

`TranscriptMerger` performs temporal speaker assignment, fills unknown gaps from neighbors, smooths very short flips, and joins consecutive segments. It does not reconcile two transcript engines, retain uncertainty evidence, represent overlap richly, or identify known people.

## 4. Model lifecycle

`ModelRegistry`, `TranscriptionModelReadiness`, `WhisperModelDownloader`, and `FinalModelDownloader` provide:

- File-backed readiness.
- Download/verify/ready/missing/failed lifecycle states.
- Repair and redownload.
- Launch and Settings refresh.
- Verify-before-process and safe fallback notice.

WhisperKit and FluidAudio are pinned by Git revision in the Xcode project. Those pins are part of the reproducible baseline.

## 5. State, failure, and diagnostics

The current session state is `idle`, `preparing`, `recording`, `processing(phase)`, `completed`, or `failed`.

Key strengths:

- Audio is persisted before final processing.
- Transcript is persisted before diarization.
- Cancellation keeps the last useful result.
- An older processing attempt is blocked from publishing over a newer attempt.
- Diarization failure remains retryable without retranscription.
- Storage failures are surfaced to the user.

Key limits for the accuracy roadmap:

- Jobs and detailed diagnostics are mostly in-memory.
- Relaunch does not resume a versioned multi-stage job graph.
- One session owns many concerns.
- Processing states do not yet distinguish draft, reconciled, verified, and needs-review transcript versions.

## 6. Review and export

The app already supports:

- Speaker cards and grouped turns.
- Speaker renaming.
- Individual and grouped-turn reassignment to existing speakers.
- Playback.
- TXT, SRT, and Codable JSON export with display names.
- Shared status presentation and accessibility cues.

Transcript text editing, candidate comparison, cluster split/merge, known-speaker confirmation, and historical verified transcript versions are not present.

## 7. Tests

The Mac unit bundle covers, among other areas:

- Recording persistence and corrupt blob behavior.
- Audio file writer ordering and errors.
- Model registry/readiness/repair.
- Launch readiness.
- Microphone selection and Test Mic logic.
- Transcript merging, grouping, reassignment, accessibility, playback caching, and export.
- Processing phases and diagnostics.
- Cancellation, failure injection, stale-attempt protection, diarization fallback, timeout, and retry guards.
- Dashboard and Model Lab presentation logic.

On 2026-07-28 the Mac build and `TranscriberTests` baseline both passed.

## 8. Stable core to retain

- SwiftUI app shell and Library-centered workflow.
- Original-audio file ownership.
- SwiftData compatibility for existing recordings.
- Actor protocols for engines.
- UI-facing state machine behavior.
- Persist-then-proceed.
- Attempt identity and stale-result protection.
- Cancellation, retry, fallback, and safe partial success.
- Playback, speaker edits, exports, model lifecycle, diagnostics, and Model Lab.

## 9. Primary expansion seams

1. Versioned result contracts.
2. Processing artifact store.
3. Persistent job/relaunch recovery.
4. Audio preparation and quality metadata.
5. Benchmark and ground-truth tooling.
6. Additional transcription candidates and deterministic consensus.
7. Rich diarization evidence and optional alternative engine.
8. Speaker profiles and open-set identity.
9. Uncertainty-focused review and transcript versioning.
10. Targeted reprocessing and optional constrained adjudication.

These seams align the VoxBot direction with the application that already exists.
