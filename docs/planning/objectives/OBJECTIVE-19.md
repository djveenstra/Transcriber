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

## Completion Report — 2026-06-25

### Manager
- Gate: **PROCEED**.
- The cancellation/failure matrix is green for agent-verifiable behavior. Audio and available transcripts are preserved, retry flags remain truthful, UI/activity state clears, copied imports cannot become orphaned, and stale attempts cannot overwrite newer work.
- Gaps found and fixed:
  - iOS cancellation did not unload the Whisper final engine; cancellation now unloads Whisper and any active Parakeet final engine.
  - Imported audio was copied before persistence and could become an orphan after cancellation; imports are now inserted immediately as retryable Library records before processing.
  - Shared cancellation state could be overwritten by rapid retries; processing attempts now have ownership IDs and stale callbacks/results are ignored.
  - Model download, persistence save, initial-transcription cancel, initial-label cancel, current-label retry cancel, and activity cleanup lacked deterministic seams/tests; focused injection coverage was added.
- Remaining Human/device-owned OBJ-20 checks are real AVAudioEngine write-error/interruption realism, provider-specific Core ML/FluidAudio resource release, rapid hardware interleavings, real microphone fallback, and large-Library/device performance.
- OBJ-20 remains pending and inactive. No OBJ-20 decomposition or acceptance work was started.

### Worker
- Files inspected: `TranscriptionSession`, transcription/Parakeet/Whisper engines, diarization engine and watchdog, model preflight/downloader/registry, microphone service/recorder/test session, persistence models, import flows, Dashboard/Library/Recording UI, playback cache, exporters, and their tests.
- Files touched:
  - `Transcriber/TranscriptionSession.swift`
  - `Transcriber/FinalTranscriptionModels.swift`
  - `Transcriber/RecordingView.swift`
  - `Transcriber/LibraryView.swift`
  - `TranscriberTests/TranscriptionSessionTests.swift`
  - `TranscriberTests/ModelRegistryTests.swift`
  - `TranscriberTests/DashboardTests.swift`
- Test seams added: injectable transcription engine, final-model verification, persistence save operation, model download operation, and model cache-removal operation. Production defaults remain unchanged.
- Covered cancellation cases: imported initial final transcription, retry transcription, initial speaker labeling, retry saved labels, retry current labels, import processing, rapid cancel/retry, and different-audio supersession.
- Covered failures: model verification/fallback, mic unavailable fallback, diarization error/timeout/ignored cancellation, download failure/repair/redownload, save failure/retry, write error, stale activity, many recordings, and back-to-back model states.
- Model unload: cancellation unloads the transcription engine and active Parakeet engine on iOS; tests observe injected-engine unload and state recovery.
- UI recovery: phases/activity clear and no stale “Transcribing” or “Identifying speakers” state remains.
- Data safety: original/copy audio remains; completed transcript/raw timing remains; imports persist before processing; retry flags reflect what is saved.
- Deferred features were not implemented.

### Auditor
- Final result: **ALIGNED** after one FIX FIRST cycle.
- Every cancellation/failure case has deterministic coverage, existing lower-level coverage, or an explicit OBJ-20 device check where genuine framework/hardware behavior cannot be manufactured safely.
- No discovered data-loss path remains unfixed.
- No prohibited paths, dependency/server/cloud/new-engine work, schema changes, OBJ-20 implementation, or playback/M4A derivative changes.
- `SWIFT_STRICT_CONCURRENCY = complete`, one-second model-release pacing, sequential model loading, and the transcription inference semaphore remain intact.
- The change is reversible and limited to test seams, tests, and small safety/state fixes.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS Simulator build: PASS.
- Full `TranscriberTests`: PASS, 163/163.
- Focused OBJ-19 matrix/regression suites: PASS, 112/112.
- Physical iPhone install: unavailable because CoreDevice reported the connected iPhone unavailable.
- Known limitation: real provider resource release and genuine recorder write errors remain device/framework checks.
- Recommended Human OBJ-20 checklist:
  - cancel recorded final transcription with each available final model;
  - cancel/retry speaker labels and verify transcript/playback/export;
  - rapidly record, stop, cancel, and retry;
  - switch downloaded models back-to-back;
  - make the selected microphone unavailable and verify fallback notice;
  - inspect a large Library;
  - verify audio preservation after interruption or reproducible write failure.

### Final Gate
**PROCEED.** Acceptance criteria are met for OBJ-19, with device realism explicitly deferred to OBJ-20. OBJ-20 was not started.
