# OBJECTIVE-17.1 — FluidAudio Diarization Safety & Timeout Stabilization
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 6 stabilization checkpoint. Depends on OBJ-17 closeout. Blocks OBJ-18 Mac companion parity until the Human Reviewer re-gates diarization safety._

## Mission
Stabilize the current FluidAudio/Sortformer diarization path so speaker-label hangs, failures, cancellation, and retry states are safe while transcripts and playback remain usable. Diagnose before replacing.

## Context
Human Reviewer device testing accepted OBJ-17 playback/accessibility but did not accept diarization/speaker-label reliability. Reported symptoms include "Identifying speakers" hanging, very slow speaker labeling on short recordings, crashes or crash contribution, frequent manual cancellation, and workflows where the transcript must remain usable even if speaker labeling fails.

The current audio-pipeline direction is to preserve a master/original audio file, use cache/regenerable derivatives for playback and ML preparation, avoid forcing one runtime file to serve every job, and treat diarization as a separate cancellable/failure-tolerant job that never blocks transcript availability.

## Scope
- Diagnose current FluidAudio/Sortformer diarization hangs and failure modes.
- Add narrow private diagnostics for diarization timing and state transitions.
- Fix timeout behavior so the app does not wait forever on stuck FluidAudio/Core ML work.
- Fix cancel behavior so "Identifying speakers" clears.
- Preserve transcript availability on diarization timeout, failure, and cancel.
- Preserve playback after diarization timeout, failure, and cancel.
- Keep retry speaker-label state clear and safe.
- Prevent unsafe overlapping diarization attempts.

## Out of Scope
- Do not replace FluidAudio.
- Do not integrate sherpa-onnx.
- Do not add pyannote, server/cloud/off-device processing, or new dependencies.
- Do not change playback or the accepted M4A playback derivative path except to verify playback survives diarization failure/cancel.
- Do not implement model-change/rerun-from-transcript backlog work.
- Do not implement delete-downloaded-models backlog work.
- Do not implement broad background processing, persistent job tables, or recording-format migration.
- Do not start OBJ-18.

## Investigation Questions
1. What exact diarization engine/library is currently used?
   - Confirm FluidAudio.
   - Identify exact API calls/classes.
   - Identify model/resource loading path.
2. What audio is being fed into FluidAudio?
   - File URL or buffer.
   - Source file format/container.
   - Sample rate, channel count, bit depth/sample format, duration.
   - Whether it is Float32, PCM16, compressed, CAF, WAV, etc.
   - Whether it is the original recording or a converted derivative.
3. What format does FluidAudio expect?
   - Check local code/docs/package docs if available.
   - Identify expected sample rate, channel count, and sample type.
   - Confirm whether FluidAudio expects 16 kHz mono Float32 samples.
   - Confirm whether the app converts to that format correctly.
4. Where does the hang occur?
   - Model/resource load.
   - Audio conversion.
   - VAD, embedding, clustering, segment mapping.
   - Persistence/save.
   - UI state update after completion/failure.
   - Cancellation cleanup.
5. Is it actually hanging, or is the UI stuck?
   - Determine whether FluidAudio returns/fails but the app remains in "Identifying speakers."
   - Determine whether cancellation completes but state is not cleared.
   - Determine whether the transcript is preserved after failure/cancel.
6. Does cancellation corrupt state?
   - Cancel during speaker labeling.
   - Confirm transcript remains readable.
   - Confirm recording status updates.
   - Confirm retry state is valid.
   - Confirm playback still works.
   - Confirm no orphan task keeps running forever.
7. Does recording length matter?
   - Test or simulate 10-30 second one-speaker audio.
   - Test or simulate 30-60 second two-speaker audio if fixtures exist.
   - Test existing app-recorded CAF when practical.
   - Determine whether issue is length, format, speaker count, or app state.
8. Does model/resource loading happen repeatedly?
   - Determine whether FluidAudio model/resources load every diarization attempt.
   - Determine whether preload/cache would help.
   - Do not implement preload yet; only report unless a minimal safe repeated-load fix is clearly in scope.
9. Does the app have timeout protection?
   - Identify whether diarization has a hard timeout.
   - Identify whether failure/cancel clears "Identifying speakers."
   - Identify whether retry uses stored raw transcription and avoids rerunning transcription.

## Required Diagnostics
- Log timing for audio inspection, conversion/prep, FluidAudio model/resource load, diarization call start/end, cancellation request/completion, and state transition to success/failure/canceled.
- Log audio format details before FluidAudio receives audio.
- Keep diagnostics private and narrow.
- Do not log private transcript text or audio content.

## Allowed Narrow Fixes
Only make a code fix if the issue is clearly one of these:
- Wrong audio format being passed to FluidAudio.
- Missing or incorrect conversion to expected format.
- Missing timeout causing permanent "Identifying speakers."
- Cancellation not clearing state.
- FluidAudio failure not surfacing as retryable state.
- UI stuck after engine failure.
- Obvious repeated model/resource load causing avoidable slowness, if the fix is minimal and safe.

If the fix would require a major audio pipeline change, new dependency, new engine, server processing, persistent job table, or recording-format migration, do not implement it. Return `ASK USER` with a proposed follow-up 17.x plan.

## Broader Audio-Pipeline Notes For Later 17.x Work
- Background/locked-screen recording is mandatory.
- Processing should not trap the user on one screen.
- Transcription and diarization should become per-recording jobs/statuses.
- Model/prep/caching should avoid repeated conversion where safe.
- Local/on-device diarization alternatives may be researched, but not implemented in OBJ-17.1 unless later approved.

## Safety Requirements
- Diarization failure must not crash the app.
- Diarization failure must not destroy or hide the transcript.
- Cancel must clear the active processing state.
- "Identifying speakers" must not remain forever after failure, cancel, or timeout.
- Retry speaker labels must remain available when appropriate.
- Playback must remain working.

## Worker Instructions
1. Inspect the existing FluidAudio/Sortformer diarization code path and document the engine, model/resource path, input format, expected format, and current timeout/cancel behavior.
2. Add narrow diagnostics only where they directly answer the investigation questions.
3. Implement only allowed narrow fixes needed for timeout, cancel, stuck UI state, retry safety, input conversion, or overlapping attempts.
4. Add or update focused tests for success/failure/timeout/cancel/retry/transcript-preservation behavior where practical.
5. Verify playback was not changed and still works after diarization failure/cancel paths.

## Auditor Checklist
- [ ] Confirm current engine/library and code path are documented.
- [ ] Confirm diagnostics do not log transcript/audio content.
- [ ] Confirm transcript preservation and original-audio preservation were not weakened.
- [ ] Confirm playback/M4A derivative path was not disturbed.
- [ ] Confirm no new dependency, engine, server/cloud/off-device implementation, pyannote, or sherpa-onnx work was added.
- [ ] Confirm no SwiftData schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, OBJ-18 work, or broad pipeline rewrite.

## QA Checklist
- [ ] Diarization success path with mock/stub if available.
- [ ] Diarization thrown failure.
- [ ] Diarization timeout/hang simulation.
- [ ] Cancel during speaker labeling.
- [ ] Failure preserves transcript.
- [ ] Cancel preserves transcript.
- [ ] Retry speaker labels does not rerun transcription.
- [ ] No permanent "Identifying speakers" after failure/cancel/timeout.
- [ ] Playback still works after canceled/failed diarization.
- [ ] No unsafe overlapping diarization attempts.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline plus focused diarization/session-state tests, focused playback regression tests, and `git diff --check`. If code changes are installed to the connected iPhone, record physical build/install evidence; real-world diarization timing/quality remains Human-owned device validation.

## Human Device Reproduction Checklist
- Install the OBJ-17.1 build on iPhone.
- Record a 10-30 second one-speaker sample, transcribe, and apply speaker labels.
- Record or import a 30-60 second two-speaker sample if available.
- Cancel while "Identifying speakers" is active.
- Confirm transcript remains readable after success, failure, timeout, and cancel.
- Confirm Retry Speaker Labels is available when appropriate and does not rerun transcription.
- Confirm playback still works after failure/cancel.
- Confirm "Identifying speakers" never remains forever after cancel/failure/timeout.

## Acceptance Criteria
- Current FluidAudio/Sortformer path and input/expected audio formats are documented.
- Per-stage private diagnostics exist for the current diarization path.
- Timeout/cancel/failure paths clear active processing state and leave transcript/playback usable.
- Retry speaker labels remains available and safe where appropriate.
- Unsafe overlapping diarization attempts are prevented.
- Tests/builds are green, and any remaining engine limitation is clearly reported for Human Reviewer decision.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md), plus the Safety Requirements above.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if safety/timeout/cancel/retry requirements are met with the current FluidAudio path and QA is green.
- **ASK USER** if the current engine appears inherently unsuitable, if a larger pipeline/job architecture is needed, or if replacement/off-device/new-dependency work is required.
- **FIX FIRST** if implementation drift, unsafe stuck state, transcript/playback regression, or missing tests are found.
- **BLOCKED** if FluidAudio/resources or platform behavior prevent even the narrow safety work without violating scope.

## Rollback Considerations
Expected changes are diagnostics and narrow state/timeout/cancel handling. Revert should restore prior diarization behavior without affecting preserved audio, transcripts, or the accepted playback derivative.

## Implementation Report — 2026-06-23

### Manager
- Gate recommendation: **ASK USER**. Agent-verifiable Phase 1 safety work is implemented, validated, installed, and ready for Human device testing. The remaining gate is real-device diarization behavior/timing/quality on Daniel's iPhone.
- OBJ-17.1 Phase 1 readiness: ready for Human device testing.
- Human product decision needed: none at this point. If device testing still shows unacceptable FluidAudio reliability, a later Human decision is needed before any replacement engine, off-device processing, broader job architecture, or OBJ-18 re-gating.

### Worker
- Files touched: `Transcriber/DiarizationEngine.swift`, `Transcriber/TranscriptionSession.swift`, `TranscriberTests/TranscriptionSessionTests.swift`, `QA.md`, and this objective report.
- Root cause fixed: the prior watchdog used structured task-group cancellation semantics, so a timeout winner could still be held hostage while the stuck FluidAudio/Core ML child ignored cancellation inside model load, prediction/process, or finalization.
- Timeout/cancel architecture: diarization now runs behind an unstructured task and a result-box actor. The session polls for result/progress/timeout/cancel and returns control without awaiting the stuck FluidAudio task after timeout or cancel.
- Stuck-attempt guard: timed-out or canceled attempts are marked abandoned so immediate overlapping retries are blocked instead of starting another unsafe FluidAudio/Core ML call while the old one may still be alive.
- Data preservation: timeout/cancel/failure paths clear `isIdentifyingSpeakers` and processing phase, preserve raw transcription and existing transcript segments, mark speaker labels retryable, and only replace speaker labels atomically on success.
- Playback: no playback implementation or cache-only M4A derivative code was changed.

### Auditor
- Alignment: **ALIGNED**.
- Transcript preservation was not weakened; tests cover failure, timeout, and cancel preservation.
- Playback and the accepted M4A derivative path were not disturbed.
- No new dependency, new diarization engine, server/cloud/off-device implementation, pyannote, sherpa-onnx, schema change, project-structure change, or OBJ-18 work was added.
- Timeout/cancel/failure paths should no longer leave the app permanently stuck on "Identifying speakers" because session-visible state is cleared independently of FluidAudio cooperation.

### QA
- macOS build: PASS.
- iOS simulator build: PASS.
- Physical iPhone build/install/launch: PASS on `iPhone 14 Pro` (`00008150-000909261440401C`), bundle `com.daniel.transcriber2.beta`.
- Full `TranscriberTests`: PASS.
- Focused diarization/session-state tests: PASS.
- Focused completed-recording playback regression tests: PASS.
- `git diff --check`: PASS.
- Human device checklist: short one-speaker recording; short two-speaker recording if available; cancel during speaker labeling; timeout/stuck path if reproducible; retry speaker labels; playback after cancel/timeout.

## FIX FIRST Follow-Up Report — 2026-06-23

### Manager
- Gate recommendation: **FIX FIRST** until the Human Reviewer verifies this updated installed build. The prior short-recording timeout was not precisely diagnosable from persisted diagnostics; this pass makes the next run stage-diagnosable and gives model/resource loading a longer first-run allowance.
- FluidAudio beta suitability: still unproven. If short real recordings continue to time out and the new diagnostics identify a recurring FluidAudio/Core ML stage, a Human architecture decision is needed before beta/OBJ-18.
- Human product decision needed: not yet. Run this build first; decide only if the new stage evidence still shows current FluidAudio is not viable.

### Worker
- Files touched: `DiarizationEngine.swift`, `TranscriptionSession.swift`, `ProcessingDiagnostics.swift`, `LibraryView.swift`, `RecordingView.swift`, `TranscriptionSessionTests.swift`, `ProcessingDiagnosticsTests.swift`, `QA.md`, and this objective report.
- Layout changes: completed recording detail uses a compact pinned transcript header containing playback progress/player, speaker-label status, and diagnostics; Record screen top spacing/status typography was tightened.
- Diarization changes: stage events now track audio inspection, conversion/prep, model/resource loading, Sortformer process, finalize, and finished. Timeout messages and Diagnostics identify the stage and elapsed/limit timing.
- Timeout/retry changes: production model/resource-load timeout is longer for first-run Core ML work; process/finalize have separate limits. Retry remains blocked for an unsafe abandoned attempt, but tests verify the guard clears when a timed-out attempt later exits cooperatively.
- Playback: playback implementation and the accepted cache-only M4A derivative path were not changed.

### Auditor
- Transcript preservation was not weakened.
- Playback/M4A derivative was not disturbed.
- No new dependency, new engine, server/cloud/off-device work, sherpa-onnx, pyannote, OBJ-17.2 implementation, or OBJ-18 work was added.
- UI top spacing is now compacted, with the compact sticky player/status reserving scroll space instead of covering transcript text or bottom actions.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- Full `TranscriberTests`: PASS.
- Focused diarization/session-state tests: PASS.
- Focused playback regression tests: PASS.
- Physical iPhone build/install/launch: PASS on `iPhone 14 Pro` (`00008150-000909261440401C`).
- Human device checklist: short one-speaker recording; short two-speaker recording; retry speaker labels after timeout; playback after timeout; scroll transcript and confirm compact sticky player/progress remains present; confirm compact top header/status spacing.

## FIX FIRST Tuning Report — 2026-06-23

### Manager
- Gate recommendation: **FIX FIRST** until the Human Reviewer verifies this installed tuning build.
- Speaker labeling now appears functionally viable enough for tuning: Human device testing confirmed completed speaker labels, 2 speaker labels detected, transcript preserved, and playback preserved.
- Future model-rerun feature was logged only. It was not implemented.

### Worker
- Files touched: `Models.swift`, `RecordingView.swift`, `LibraryView.swift`, `TranscriptSegmentReassignmentTests.swift`, `QA.md`, and this objective report, in addition to earlier OBJ-17.1 files already modified in this branch.
- Speaker grouping approach: display-layer `TranscriptTurnGrouping` creates `TranscriptDisplayTurn` values from saved transcript segments. Underlying `Recording.segments`, raw transcription, and export data are not rewritten.
- Grouping rules: same non-empty/non-unknown speaker only; adjacent gap must be <= 2 seconds; grouped turn duration must be <= 60 seconds; group must contain <= 12 segments; never group across speaker changes or large pauses.
- Edit semantics: a grouped card stores the underlying segment IDs. Reassigning a grouped turn updates only those underlying segments' speaker labels, preserving timing and text.
- Layout changes: the large status/Diagnostics block scrolls away with transcript content. The compact mini-player remains outside the scroll as a small persistent playback control. Bottom Rename/Share actions remain separate.
- Playback implementation and the accepted M4A playback derivative were not changed.
- Future model-rerun note: logged in `QA.md` as "Model Selection & Rerun Transcription" for a later 17.x objective; not implemented.

### Auditor
- Raw transcript data was not destructively rewritten.
- Transcript preservation was not weakened.
- Playback/M4A derivative was not disturbed.
- No new dependency, new engine, server/cloud/off-device work, sherpa-onnx, pyannote, OBJ-17.2 implementation, model-rerun implementation, or OBJ-18 work was added.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- Full `TranscriberTests`: PASS.
- Focused diarization/session-state tests: PASS.
- Focused speaker grouping tests: PASS.
- Focused playback regression tests: PASS.
- Physical iPhone build/install: PASS. Command-line launch was blocked because the device was locked.
- Human device checklist: verify same-speaker adjacent segments are visually grouped; verify speaker change starts a new card; verify playback works; verify scrolling causes the large header/status area to move away; verify compact playback behavior is acceptable; verify Rename/Share actions remain usable; verify Diagnostics still accessible.

## Final Closeout Report — 2026-06-23

### Manager
- Gate recommendation: **PROCEED**.
- OBJ-17.1 is complete. Human Reviewer device testing accepted diarization safety, completed speaker labels, usable speaker-turn grouping, compact header/player/status behavior, transcript preservation, playback preservation, and timeout/cancel recovery.
- New feature ideas are deferred backlog only. OBJ-17.2 and OBJ-17.3 were not created as active objectives, and OBJ-18 Mac companion parity is the next original objective.
- Human product decision needed: none for OBJ-17.1 closeout.

### Worker
- Files touched for closeout: `PLAN.md`, `OBJECTIVE.md`, `DECISIONS.md`, `QA.md`, and this objective report, plus removal of the inactive planning artifact `docs/planning/objectives/OBJECTIVE-17.2.md`.
- PLAN update: OBJ-17.1 is marked DONE 2026-06-23 with QA/completion-report evidence; OBJ-18 is restored as the next original objective; launch preload, model rerun, delete-downloaded-models, further speaker/player polish, diarization evaluation, background-job architecture, and diarization warmup are backlog only.
- OBJECTIVE update: active objective now points to `OBJECTIVE-18.md`.
- QA update: final Human Reviewer PASS was recorded for OBJ-17.1.
- Runtime code changed only as part of the already accepted OBJ-17.1 implementation. No OBJ-18 implementation started during closeout.
- No new dependencies, new engines, server/cloud/off-device processing, or feature implementations were added.

### Auditor
- Transcript preservation was not weakened.
- Playback and the accepted cache-only M4A derivative were not disturbed.
- FluidAudio remains the current diarization path.
- No sherpa-onnx, pyannote, server/cloud/off-device implementation, dependency change, active OBJ-17.2/OBJ-17.3 objective, or OBJ-18 implementation was added.

### QA
- Validation retained from the accepted OBJ-17.1 branch: `git diff --check` PASS; macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS; focused diarization/session-state tests PASS; focused speaker grouping tests PASS; focused playback regression tests PASS; physical iPhone build/install PASS.
- Closeout doc validation: `git diff --check` rerun after planning updates before commit.
- Working tree status checked before commit.
