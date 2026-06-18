# OBJECTIVE-15 — Diagnostics on Normal Screens + Diagnostics Data Model

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
