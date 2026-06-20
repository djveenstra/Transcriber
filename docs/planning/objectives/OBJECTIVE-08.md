# OBJECTIVE-08 — Background/Lock & 30-Minute Reliability Hardening

_Phase 2. Depends on OBJ-07. Closes PRD §8 (B4, B5), §17 Recording. RISK R4, R5, R9, R17. **Human-owned device gate.**_

## Mission
Harden recording for real-world long sessions: handle audio-session interruptions and route changes, keep recording alive in background/lock where iOS allows, and validate 5/15/30-minute reliability and memory behavior on device.

## Scope
- Handle `AVAudioSession` interruption + route-change notifications during recording (pause/resume or graceful stop-with-save; never lose captured audio).
- Confirm/keep `UIBackgroundModes = audio` behavior; ensure the engine and file writer survive backgrounding.
- Add a documented device test script (5/15/30 min, lock, app-switch) to [QA.md](../../../QA.md).
- Memory observation hooks/notes for the 30-min run (no architectural change unless a leak is found).

## Out of Scope
- New features; UI restructuring.
- Changing the transcription/diarization algorithms.

## Worker Instructions
1. Subscribe to interruption/route-change notifications; on interruption, ensure buffered audio is flushed/closed safely (reuse the write-error path) and state reflects reality.
2. Verify the tap + `AudioFileWriter` continue across background transitions in the simulator as far as possible; document what only the device can prove.
3. Write the device test script (exact steps + pass criteria) into [QA.md](../../../QA.md) for the Human Reviewer.
4. If a memory issue is observed in sim profiling, fix conservatively (e.g. autorelease around heavy loads) — do **not** remove the deliberate sequenced-load pauses without measurement (see code comments / SELF_CRITIQUE §6).

## Auditor Checklist
- [ ] Interruption/route handling never discards captured audio (write-error/save path reused).
- [ ] Deliberate pipeline pauses/semaphore untouched unless measured + documented.
- [ ] Builds green; concurrency intact.
- [ ] Device test script added to QA.md.

## QA Checklist (agent-verifiable portion)
- [ ] Simulated interruption during recording → audio file closed safely, recording recoverable/saved.
- [ ] Regression: normal record→transcript→label unaffected.

## QA Checklist (Human device gate)
- [ ] 5/15/30-min record → stop → transcribe → label → share succeed on iPhone 17 Pro.
- [ ] Lock phone + switch apps during recording → audio preserved.
- [ ] Memory stays bounded across the 30-min run.

## Acceptance Criteria
- Interruptions/route changes handled without data loss (agent-verifiable).
- Device script documented; Human Reviewer confirms 5/15/30-min + background/lock.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + interruption-handling tests where feasible. Device runs per QA.md script.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). **Cannot be fully done without the device gate.**

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **ASK USER** — agent completes interruption handling + script, then the Human Reviewer runs the device tests and confirms.
- **FIX FIRST** if any interruption path loses audio.

## Rollback Considerations
Interruption handling is additive observers. Revert removes them, returning to current background behavior. No data/schema change.

## Completion Report — 2026-06-19

- **Gate:** PROCEED.
- **Evidence:** [QA.md — OBJ-08 final Human Reviewer PASS](../../../QA.md#obj-08--final-human-reviewer-pass-and-gate--2026-06-19).
- **Implemented:** interruption/media-services safe-stop handling; retryable saved-audio messaging; route-change active-microphone/fallback refresh; Human-owned device checklist for OBJ-04 through OBJ-08; Bluetooth/AirPods runtime input refresh; Test Mic route-change race protection; stale disconnected Bluetooth input cleanup; Bluetooth reconnect retry refresh; Automatic effective fallback when selected inputs are unavailable.
- **Validation:** macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (89/89); focused microphone/Test Mic tests PASS; `git diff --check` PASS.
- **Human Reviewer result:** PASS for AirPods/Bluetooth route-change reliability. AirPods appear when connected, disappear when disconnected, reappear after Bluetooth disconnect/reconnect without force quit, Test Mic works without freezing, normal recording still works, and Automatic fallback/default behavior is accepted.
- **Notes:** Longer 5/15/30-minute and background/lock beta reliability checks remain documented in QA.md for continued device acceptance, but no OBJ-08 blocker remains from the current Human Reviewer retest.
