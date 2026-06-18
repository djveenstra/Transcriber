# OBJECTIVE-07 — Mic Fallback, Active-Mic Display & Notice

_Phase 2. Depends on OBJ-05. Closes PRD §8 (B9, B10) and Record-flow steps 3–4. RISK R11._

## Mission
When the selected microphone is unavailable at record time, automatically fall back to the best available input, show which microphone is actually in use during recording, and notify the user of the fallback — without ever blocking recording.

## Scope
- At `startRecording`, resolve the effective input: selected-if-present else best-available; never block on a missing preferred mic.
- Surface the active microphone in the recording status header (replace/augment current model-only header).
- Show a non-intrusive notice when a fallback occurred.
- Tests for the resolution logic (selected present → use it; absent → fallback; none → default) using the OBJ-05 fake input list.

## Out of Scope
- Background/interruption handling (OBJ-08).
- Test Mic (OBJ-06).

## Worker Instructions
1. Add input-resolution to the microphone service; `AudioRecorder`/session consume the resolved input.
2. Publish the active input name on the session; bind it in `RecordingView`'s status header alongside model state.
3. When resolved ≠ selected, set a calm notice (reuse `livePreviewNote`/completion-note style) — "Recording with <X> because <selected> was unavailable."
4. Ensure recording proceeds even if enumeration fails entirely (hard fallback to system default).

## Auditor Checklist
- [ ] Recording never blocks on mic availability (record-first preserved).
- [ ] Active mic displayed during recording; fallback notice only when fallback occurs.
- [ ] Resolution logic unit-tested across present/absent/none.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Failure injection: select an input, make it unavailable → recording starts on fallback + notice + correct active-mic shown.
- [ ] With selected input present → no notice, correct active-mic shown.
- [ ] Regression: record→transcript→label unaffected.

## Acceptance Criteria
- Automatic fallback to best input; visible active mic; fallback notice; never blocks.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + resolution tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Real Bluetooth-drop fallback is a **device gate** (OBJ-08/20).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if fallback/notice/active-mic land green.
- **FIX FIRST** if any path can block recording when a mic is missing.

## Rollback Considerations
Additive resolution + header text. Revert returns to default-input recording. No data/schema change.
