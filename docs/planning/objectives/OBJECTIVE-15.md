# OBJECTIVE-15 — Diagnostics on Normal Screens + Diagnostics Data Model
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 5. Depends on OBJ-14 (Details disclosure), OBJ-03 (registry). Closes PRD §13 Diagnostics (G3). RISK R8, R10._

## Mission
Capture real pipeline metrics (model used, load time, processing time, realtime factor, fallback used, speaker-label status) during normal recording/import — not just Model Lab — and present them calmly in the progress Details + completed-transcript detail.

## Scope
- A `Diagnostics` value captured during `processFile`/retry: model id+name, model load time, transcription time, audio duration → RTF, fallback-used flag (transcription and/or diarization), speaker-label status, failure message.
- Store the latest diagnostics on the session and (optionally, migration-safe) on `Recording` for later viewing.
- Show in the OBJ-14 Details disclosure and a collapsed diagnostics row on RecordingDetailView — calm, organized (PRD §13/§16).
- Reuse the same metric capture for Model Lab where it overlaps (DRY with OBJ-11).

## Out of Scope
- A separate diagnostics tab/screen.
- Persisting full historical diagnostics analytics.

## Worker Instructions
1. Thread timing capture through `TranscriptionSession` (measure load vs transcribe vs diarize; reuse the watchdog/fallback signals already present for "fallback used").
2. Compute RTF = audioDuration / processingTime; format like Model Lab's `speedDescription`.
3. Surface in Details (collapsed by default). If persisting on `Recording`, follow OBJ-01 migration policy + DECISIONS entry.
4. Keep it read-only and quiet; no new alerts.

## Auditor Checklist
- [ ] Metrics measured at the real pipeline boundaries (not estimated).
- [ ] Presentation is calm/collapsed (PRD §16) — not a lab bench on normal screens.
- [ ] Any `Recording` persistence is migration-safe + documented.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] After a real (sim) run, diagnostics show plausible load/transcribe/RTF + fallback flags.
- [ ] Fallback injection (diarization Balanced→Fast) marks "fallback used."
- [ ] Diagnostics visible in Details + detail screen; collapsed by default.
- [ ] Regression: processing/cancel/completion unaffected.

## Acceptance Criteria
- Real diagnostics (model, load time, processing time, RTF, fallback, speaker status) captured and shown calmly on normal screens.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + diagnostics-capture tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Absolute timing accuracy is a **device** measurement (Human, OBJ-20).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if metrics capture + calm display land green.
- **ASK USER** if persisting diagnostics on `Recording` (approve migration).

## Rollback Considerations
Additive measurement + read-only UI. Revert removes diagnostics display. Any migration additive per OBJ-01.

## Completion Report — 2026-06-20

**Worker summary:** Added a small `ProcessingDiagnostics` data model, shared diagnostics formatting, and an in-memory `ProcessingDiagnosticsStore` for latest/session diagnostics. `TranscriptionSession` now captures model preparation/load time, final transcription time, audio duration, realtime speed, diarization time, transcription fallback, diarization fallback, speaker-label status, and safe failure/cancellation messages at the existing processing boundaries. Model Lab now reuses the shared seconds/speed formatter.

**Display summary:** OBJ-14 Details disclosure shows diagnostics when available, still collapsed by default. Recording, Shared Audio, and Library detail transcript surfaces show a collapsed Diagnostics disclosure. Saved recordings without current-session diagnostics show only stable derived details (model, audio length, speaker status) and do not invent timing values.

**Persistence boundary:** No SwiftData schema change was made. Diagnostics are session/latest-only through the in-memory store; older saved recordings do not gain persisted timing history. A future persisted diagnostics history would require Human Reviewer approval and a DECISIONS.md migration entry.

**Measured vs deferred:** Measured: model preparation/load wall time, transcription wall time, audio duration from `AVAudioFile` with saved-recording fallback, realtime speed from audio duration/transcription time, diarization wall time, fallback flags, speaker-label status, and safe failure/cancellation text. Deferred: absolute performance/timing accuracy on real device and any durable persisted diagnostics history.

**Auditor report:** ALIGNED. Metrics are captured from real processing boundaries where claimed; UI remains collapsed/secondary and does not create a lab-bench normal screen; no SwiftData schema change, dependency bump, strict-concurrency weakening, transcription/diarization algorithm change, model-selection behavior change, export hardening, accessibility, Mac parity, OBJ-19 cancellation hardening, or prohibited-path edit was introduced.

**QA evidence:** Recorded in [QA.md](../../../QA.md#obj-15--diagnostics-on-normal-screens--diagnostics-data-model--2026-06-20). macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS (121/121); `git diff --check` PASS. Focused tests covered diagnostics formatting, collapsed presentation metadata, derived saved-recording summaries, diarization fallback flags/status, Model Lab formatting regression, and ProcessingPhase regression.

**Gate recommendation:** PROCEED. No Human/product decision is required for this implementation because diagnostics were not persisted into `Recording`.
