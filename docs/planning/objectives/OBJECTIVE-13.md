# OBJECTIVE-13 — Consistent Speaker-Label States & Rename/Reassign Parity
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 4. Depends on OBJ-09 (`RecordingStatus`), OBJ-12 (reassignment). Closes PRD §10 (D7) + §11 editing parity. RISK R8, R15._

## Mission
Surface speaker-label states (approximate / failed / canceled / retryable) consistently across every screen that shows transcripts, and ensure rename + reassign are available wherever a completed transcript appears.

## Scope
- A single, reusable presentation for speaker-label status (note + retry affordance) used in: RecordingView completed state, RecordingDetailView, SharedAudioDetailView, and Dashboard recent items.
- Ensure rename (existing) and reassign (OBJ-12) are reachable from each transcript surface (where editing applies).
- Consistent copy for approximate vs failed vs canceled vs retryable.

## Out of Scope
- Diarization algorithm changes (roadmap).
- New progress timeline (OBJ-14).

## Worker Instructions
1. Extract the label-status note/retry into a shared view component fed by the canonical state (derive from `diarizationNeedsRetry` + completion note + status).
2. Audit each transcript surface; add the component + editing entry points where missing (e.g. shared-audio detail currently lacks rename/reassign).
3. Keep copy aligned with PRD §13 failure philosophy (what's safe / failed / retryable / fallback).

## Auditor Checklist
- [ ] One shared status component (no per-screen copies drifting).
- [ ] Rename + reassign reachable on all completed-transcript surfaces.
- [ ] Retry-labels path still avoids re-transcription.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Approximate, failed, canceled, retryable each render consistently across screens.
- [ ] Retry speaker labels works from each surface and does not re-run transcription.
- [ ] Rename + reassign reachable everywhere a transcript shows.
- [ ] Regression: completion notes / storage alerts unaffected.

## Acceptance Criteria
- Uniform label-state surfacing + editing parity across all transcript screens.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if states + parity are consistent and retry semantics preserved.
- **FIX FIRST** if retry re-runs transcription anywhere or a surface is missing editing.

## Rollback Considerations
Refactor to a shared component + added entry points. Revert restores per-screen handling. No data/schema change.

## Completion Report — 2026-06-20

**Worker report:** Implemented `SpeakerLabelStatusPresentation` and `SpeakerLabelStatusView` as the shared speaker-label status source for approximate, failed, canceled, retryable, active/identifying, complete, and not-yet-available states. `RecordingView`, `RecordingDetailView`, `SharedAudioDetailView`, Library row metadata, and Dashboard speaker-label summaries now consume that shared presentation. Completed Recording and Shared Audio surfaces route to the saved Library detail record for speaker rename and OBJ-12 segment reassignment, so edits use the existing persisted SwiftData path instead of a duplicate temporary-session editor.

**Retry behavior:** Speaker-label retry remains label-only. `retrySpeakerLabels(for:in:)` continues to use `recording.rawTranscription` and rerun diarization/merge without invoking final transcription, while preserving transcript text. Failed saved-recording retries now explicitly keep `diarizationNeedsRetry` set if the retry also fails.

**Auditor report:** ALIGNED. Shared status logic is centralized rather than copied per screen; OBJ-12 reassignment/export behavior remains green; no diarization algorithm change, transcript text editing, speaker merge/split workflow, SwiftData schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, OBJ-14 progress-timeline work, OBJ-15 diagnostics work, export hardening, accessibility, Mac parity, or cancellation hardening was introduced.

**QA evidence:** Recorded in [QA.md](../../../QA.md#obj-13--consistent-speaker-label-states--renamereassign-parity--2026-06-20). macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS (111/111); `git diff --check` PASS. Focused tests covered the shared status states, edit availability, retry-from-raw-transcription behavior, OBJ-12 reassignment regression, and export regression.

**Manager gate recommendation:** PROCEED. No Human/product decision is required for OBJ-13. PLAN.md and OBJECTIVE.md advancement are deferred until Human Reviewer review so OBJ-14 is not started in this pass.
