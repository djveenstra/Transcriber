# OBJECTIVE-06 — Test Mic + Live Input Meter

_Phase 2. Depends on OBJ-05. Closes PRD §8 (B8)._

## Mission
Add a "Test Mic" action in Settings with a live input level meter, so the user can confirm the selected microphone works before recording.

## Scope
- A Test Mic screen/section in Settings that starts a temporary capture and shows a live level meter, reusing the existing RMS level computation in `AudioRecorder`.
- Uses the input selected in OBJ-05.
- Cleanly starts/stops capture (no leaked audio session; no file written).

## Out of Scope
- Fallback logic + active-mic-during-recording display (OBJ-07).
- Recording pipeline changes.

## Worker Instructions
1. Reuse `AudioRecorder` (or a lightweight metering-only path) to tap input and publish `level` without writing a file. Ensure the session is deactivated on exit (mirror existing `stop()` teardown).
2. Build a simple animated meter bound to `level`; show which input is being tested.
3. Guard against navigating away while testing (stop on disappear).
4. No persistence; this is ephemeral.

## Auditor Checklist
- [ ] Test capture writes no file and fully tears down the audio session on exit.
- [ ] Reuses existing RMS/level code (no duplicate metering logic).
- [ ] Does not interfere with a real recording session (separate lifecycle).
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Start Test Mic → meter responds to input (sim: responds to system input).
- [ ] Leaving the screen stops capture; starting a real recording afterward works.
- [ ] No audio-session "stuck active" symptoms.
- [ ] Regression: Settings + recording unaffected.

## Acceptance Criteria
- Test Mic shows a live meter for the selected input and cleans up reliably.
- Tests/builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Real-mic responsiveness is a **device gate** (OBJ-08).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if meter works and teardown is clean.
- **FIX FIRST** if the audio session can be left active or a file is written.

## Rollback Considerations
Self-contained UI + ephemeral capture. Revert removes the screen with no side effects.
