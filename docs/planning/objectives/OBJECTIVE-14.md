# OBJECTIVE-14 — Phase-Timeline Progress UI

_Phase 5. Depends on OBJ-13 (shared state patterns). Closes PRD §13 Progress UI (G1, G2). RISK R17._

## Mission
Replace the single progress bar with a structured, calm phase timeline showing the current phase, rough %/activity, elapsed time, and Cancel/Retry/Details affordances — without gold-plating (per SELF_CRITIQUE §2).

## Scope
- A `ProcessingPhase` model: `savingRecording / preparingModel / transcribing / savingTranscript / identifyingSpeakers / savingSpeakerLabels / exporting` (PRD §13 core phases).
- Drive the model from `TranscriptionSession` state transitions (replace the ad-hoc `processing(String)` payload with structured phases; keep a string for display).
- Progress UI shows: current phase, %/activity, elapsed timer, Cancel, Retry (where relevant), and a Details disclosure.
- Reuse across RecordingView, RecordingDetailView (retry), SharedAudioDetailView.

## Out of Scope
- Diagnostics content inside Details (OBJ-15 fills it).
- Animations/scrubbing/timeline-graphics (explicitly excluded).

## Worker Instructions
1. Introduce `ProcessingPhase` and map current `state = .processing("…")` call sites to it; keep human-readable text derived from the phase.
2. Build a compact phase view bound to the session; add an elapsed-time `TimelineView`.
3. Keep Cancel wired to the existing `cancelProcessing`; surface Retry where the session already supports it.
4. Details disclosure can start minimal (phase + elapsed); OBJ-15 enriches it.

## Auditor Checklist
- [ ] Phase model maps 1:1 to PRD core phases; no state semantics lost.
- [ ] Cancel/Retry behavior unchanged functionally.
- [ ] No new heavy animation; calm per PRD §16.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] During processing, the correct phase + elapsed time show and advance.
- [ ] Cancel still cancels safely (transcript/audio preserved).
- [ ] Retry where relevant still works.
- [ ] Regression: completion + failure states unaffected.

## Acceptance Criteria
- Structured phase timeline with elapsed/%/cancel/retry/details replaces the bare bar.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + phase-mapping tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if phases + elapsed + controls land without behavior regression.
- **FIX FIRST** if any state transition is lost or Cancel/Retry semantics change.

## Rollback Considerations
Refactor of the processing presentation + a phase enum. Revert restores the single bar. No data/schema change; session state semantics preserved either way.
