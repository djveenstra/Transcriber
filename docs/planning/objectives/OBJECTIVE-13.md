# OBJECTIVE-13 — Consistent Speaker-Label States & Rename/Reassign Parity

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
