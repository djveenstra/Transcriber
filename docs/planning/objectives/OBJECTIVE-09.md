# OBJECTIVE-09 — Library Status Badges + Canonical `RecordingStatus`
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 3 (first of three). Depends on OBJ-01 (migration policy). **Foundation for OBJ-10 (Dashboard) and OBJ-11 (Model Lab tab).** Closes PRD §6 Library (A4) and RISK R12._

> **Sequencing:** this objective establishes the canonical status model **before** the Dashboard (OBJ-10) consumes it. Do not start OBJ-10 until this is gated `PROCEED`.

## Mission
Replace the scattered boolean flags with one canonical, derivable `RecordingStatus`, and use it to give Library items the full PRD status set, duration, final model used, and speaker-label status — plus reconcile orphaned files.

## Scope
- A `RecordingStatus` enum: `recordingSaved / needsTranscription / transcribing / speakerLabeling / speakerLabelsFailed / complete` (map to PRD §6 badges).
- **Derive** status from existing fields first (`transcriptionNeedsRetry`, `diarizationNeedsRetry`, presence of segments) to avoid a schema change; if a stored status field is truly needed, follow the OBJ-01 migration policy and record it in [DECISIONS.md](../../../DECISIONS.md).
- Library rows show: title, duration, status badge, final model used (`finalTranscriptionModelID` → display name), speaker-label status.
- Launch-time reconciliation: detect recordings whose audio file is missing (mark/handle) — orphan handling (RISK R12), without deleting user data.

## Out of Scope
- Dashboard (OBJ-10) — it consumes this status model.
- Model Lab tab (OBJ-11).
- Progress timeline (OBJ-14).

## Worker Instructions
1. Implement `RecordingStatus` as a computed property over `Recording` where possible (no migration). Unit-test the derivation truth table.
2. Update Library row rendering to the full badge set + duration + model name + speaker status. Reuse Theme/badge styles.
3. Add a launch reconciliation that flags missing-audio recordings (e.g. status/needs-attention) without deleting rows or files.
4. If a stored status field is unavoidable, gate it behind a migration per OBJ-01 and document it in [DECISIONS.md](../../../DECISIONS.md).

## Auditor Checklist
- [ ] Status is derived (no `Recording` schema change) — or, if stored, a migration + DECISIONS entry exists.
- [ ] Badges map exactly to PRD §6 states.
- [ ] Reconciliation never deletes rows/files.
- [ ] Strict concurrency unchanged; both builds green.
- [ ] Checked against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md.

## QA Checklist
- [ ] Each status renders the correct badge (drive via fixtures: saved/needs/transcribing/labeling/failed/complete).
- [ ] Duration + final model + speaker status shown.
- [ ] Missing-audio recording is flagged, not lost.
- [ ] Regression: delete/rename/retry flows still work.

## Acceptance Criteria
- Canonical status drives Library badges + the listed metadata.
- Orphan reconciliation present (non-destructive).
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + status-derivation tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if status + badges + reconciliation land green via derivation.
- **FIX FIRST** if any badge mismaps PRD states or reconciliation can delete data.
- **ASK USER** if a stored status field (schema change/migration) is required.
- **BLOCKED** if OBJ-01's migration policy is missing/unclear and a schema change is needed.

## Rollback Considerations
Derived status + UI are additive/revertible. If a migration was added, rollback must follow the OBJ-01 policy (additive, default-valued) so reverting code leaves data readable.

## Completion Report — 2026-06-19

### Worker Summary
- Added canonical derived `RecordingStatus` with the required states: `recordingSaved`, `needsTranscription`, `transcribing`, `speakerLabeling`, `speakerLabelsFailed`, and `complete`.
- Avoided a SwiftData schema change. No stored status field was added; no migration or DECISIONS.md entry was required.
- Updated Library rows to show title/date, duration, status badge, final transcription model name, speaker-label status, and a missing-audio warning when applicable.
- Added app-start and Library-open reconciliation for recordings whose audio file is missing. Reconciliation reports/surfaces the condition through in-memory state only; it does not delete rows, delete files, or mutate transcript/model/retry data.
- Added detail-screen missing-audio messaging and disabled audio-dependent actions when the audio file is absent, while keeping any saved transcript visible.

### Status Derivation
- `transcribing`: derived from in-memory `TranscriptionSession` activity for the recording audio filename.
- `speakerLabeling`: derived from in-memory `TranscriptionSession` activity for speaker-label retry or post-transcription labeling.
- `needsTranscription`: derived from `recording.transcriptionNeedsRetry`.
- `speakerLabelsFailed`: derived from `recording.diarizationNeedsRetry`.
- `recordingSaved`: derived when no transcript segments exist and no retry/failure/active activity is present.
- `complete`: derived when transcript segments exist and no transcription or speaker-label retry is needed.

### Tests Added
- `RecordingStatusTests.derivesStatusTruthTableFromRecordingAndActivityState()`
- `RecordingStatusTests.eachStatusHasBadgeCopyAndSymbol()`
- `RecordingStatusTests.metadataHelpersFormatDurationModelAndSpeakerLabels()`
- `RecordingStatusTests.missingAudioReconciliationReportsRowsWithoutMutatingThem()`

### Validation
- Focused `RecordingStatusTests`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- `TranscriberTests`: PASS, 93/93.
- `git diff --check`: PASS.

### Auditor Alignment Report
- Result: ALIGNED.
- Touched paths stayed inside `src/native/Transcriber2/` plus planning/QA docs.
- No `Recording` schema change, stored status field, dependency bump, strict-concurrency weakening, destructive reconciliation, Dashboard/OBJ-10 implementation, Model Lab tab work, speaker reassignment, progress timeline, diagnostics, export hardening, accessibility, or Mac parity work was introduced.

### Gate Decision
- Manager recommendation: PROCEED.
- No OBJ-09-specific Human/device gate remains. Real-device visual review of the Library row can continue as part of normal beta acceptance.
