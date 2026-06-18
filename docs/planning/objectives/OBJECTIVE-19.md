# OBJECTIVE-19 — Cancellation & Failure-Injection Hardening

_Phase 7. Depends on all feature objectives. Closes PRD §7 Cancel + §17 Cancellation/Failure. RISK R6, R7, R8, R10._

## Mission
Prove the app stays safe and consistent under cancellation and forced failures across the whole matrix, and harden any path that doesn't.

## Scope
- Exercise and verify the full cancel matrix: cancel during final transcription, during speaker labeling, during retry-transcription, during retry-labels, during import processing.
- Failure injection: forced model load failure → fallback/notice; forced mic unavailable → fallback/notice; forced diarization timeout/error → approximate/retry; forced download failure → repair/redownload; forced save failure → storage alert; forced write error → retryable.
- Stress: rapid record/stop/cancel/retry interleavings; many recordings; back-to-back model switches.
- Verify model unload on cancel, UI recovery, and that audio/transcript always survive.

## Out of Scope
- New features.
- Algorithm changes (only safety/consistency fixes).

## Worker Instructions
1. Use the existing test seams (e.g. `FakeDiarizationEngine` behaviors `succeed/fail/hang`; injectable engines) to script failures deterministically.
2. Add/extend tests for each cancel and failure case asserting: state lands `completed`/`failed` correctly, transcript/audio preserved, retry flags correct, models unloaded.
3. Fix any path where cancel leaves a loaded model, a stuck UI, or an unsaved-but-claimed state — minimally and reversibly. Do **not** remove deliberate pauses/semaphore without measurement.
4. Document any case that can only be confirmed on device.

## Auditor Checklist
- [ ] Every cancel/failure case has a test or documented device check.
- [ ] No data-loss path discovered remains unfixed.
- [ ] Deliberate concurrency/pacing code preserved unless measured.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Cancel during transcription / labeling / retry paths → transcript+audio safe, correct retry state.
- [ ] Each failure injection produces the PRD-specified fallback/notice/retry.
- [ ] Stress interleavings don't crash or corrupt; UI recovers.
- [ ] Regression: happy path unaffected.

## Acceptance Criteria
- Full cancel + failure matrix verified safe; identified gaps fixed.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + the expanded cancel/failure tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Device-only failure realism flagged for OBJ-20.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if the matrix is green and fixes are reversible.
- **FIX FIRST** for any discovered data-loss/stuck-state path.
- **ASK USER** for device-only failure confirmations.

## Rollback Considerations
Primarily tests + small safety fixes. Each fix is isolated and revertible. No data/schema change expected.
