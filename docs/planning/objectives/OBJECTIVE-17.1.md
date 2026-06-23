# OBJECTIVE-17.1 — FluidAudio Diarization Safety & Timeout Stabilization

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
