# OBJECTIVE-18 — Mac Companion Parity

_Phase 7. Depends on OBJ-09–16 (features exist to mirror). Closes PRD §4/§17 Mac (K1–K4). RISK R13._

## Mission
Verify and complete the Mac companion experience: open/import, playback, transcript review, and share/export all work; bring Model Lab and model workflows to Mac where feasible; and document any intentional iPhone-first gaps.

## Scope
- Audit each Mac flow (open/import, play, review, share/export) against the iOS feature set delivered so far.
- Make Model Lab available on macOS if feasible (it's currently `#if os(iOS)`); if not feasible, document why.
- Ensure new screens (Dashboard, status badges, diagnostics, progress timeline) render correctly on macOS.

## Out of Scope
- macOS-specific redesign.
- iOS-only hardware features (live Parakeet EOU is iOS).

## Worker Instructions
1. Build + run the macOS target; walk every flow; list gaps vs iOS.
2. For Model Lab on Mac: evaluate lifting the `#if os(iOS)` guard (WhisperKit models work on macOS). If the Parakeet path isn't available on macOS, scope Model Lab to the Whisper models there.
3. Fix layout/availability issues from the new iOS-era screens on macOS.
4. Document intentional gaps in [DECISIONS.md](../../../DECISIONS.md).

## Auditor Checklist
- [ ] No iOS regressions from macOS-enabling changes (`#if` branches correct).
- [ ] Mac flows function; gaps documented intentionally.
- [ ] Builds green on both platforms; concurrency intact.

## QA Checklist
- [ ] macOS: open/import a recording, play, review transcript, share/export.
- [ ] Model Lab on Mac (if enabled) compares Whisper models + report.
- [ ] New screens render correctly on macOS.
- [ ] Regression: iOS unaffected.

## Acceptance Criteria
- Mac supports open/import/play/review/share; Model Lab on Mac where feasible; gaps documented.
- Tests/builds green on both platforms.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline (both destinations). **Device/Mac gate:** Human Reviewer confirms on a real Mac.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Mac hardware confirmation is a Human gate.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** for agent-verifiable parity; **ASK USER** for Mac hardware confirmation and to ratify intentional gaps.

## Rollback Considerations
Mostly `#if` adjustments + layout fixes. Revert restores iOS-only Model Lab and prior macOS behavior. No data/schema change.

## Agent Implementation Report — 2026-06-23

### Worker
- Audited the shared Mac paths for launch, Dashboard/Library/Settings navigation, file import, Whisper transcription, completed-recording playback, transcript review, speaker/status presentation, diagnostics, progress timeline, and TXT/SRT/JSON sharing.
- Confirmed the untouched macOS target built and launched. The broad confirmed gap was that Model Lab and its Dashboard/Settings navigation were compiled only for iOS.
- Enabled the established Model Lab screen as the fourth Mac tab and restored the Dashboard and Settings entry points on Mac.
- Scoped Mac Model Lab to the existing curated Whisper choices. The iOS path still exposes Whisper and Parakeet, and Parakeet implementation remains compiled only for iOS.
- Added focused coverage for the four-tab Mac structure and Whisper-only Mac Model Lab scope.
- Documented intentional Mac gaps in `DECISIONS.md` D-011: Parakeet comparison and the Share to Transcriber extension remain iOS-only; Mac uses in-app import and system sharing.
- Preserved the accepted M4A playback derivative, iOS behavior, data model, dependencies, strict concurrency, and all deferred feature boundaries. No OBJ-17.2/OBJ-17.3, OBJ-19, or OBJ-20 work was implemented.

### Auditor
- Result: **ALIGNED**.
- Confirmed the changes stay within OBJ-18, preserve iOS Model Lab/Parakeet behavior, introduce no dependency/schema/concurrency/project-setting changes, touch no prohibited paths, and document intentional Mac gaps.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- Full `TranscriberTests`: PASS, 143/143.
- Focused `ModelLabTests`, `TranscriptSegmentReassignmentTests`, `TranscriptExportTests`, and `SharedAudioInboxTests`: PASS, 35/35.
- Updated Mac app launch: PASS; the application remained running. The existing AppIntents service warning was present, with no launch crash.
- Native Mac window inspection and interaction could not be automated because this Codex session lacks macOS Screen Recording and Accessibility permission.

### Remaining Human Mac Checklist
- [ ] Launch and confirm Dashboard, Library, Model Lab, and Settings are present and readable.
- [ ] Import a short audio file and confirm Whisper transcription completes.
- [ ] Open the saved Library item; confirm playback, transcript review, speaker labels/status, Diagnostics, and progress timeline layout.
- [ ] Export/share TXT, SRT, and JSON.
- [ ] In Model Lab, confirm only Whisper models appear; compare at least one downloaded Whisper model and share the report.
- [ ] Confirm the documented gaps are acceptable: no Parakeet comparison and no Mac Share to Transcriber extension.

### Manager Gate Recommendation
**ASK USER.** Agent-verifiable implementation, builds, tests, audit, and launch are green. Keep OBJ-18 active until the Human Reviewer completes the real Mac checklist and accepts the intentional gaps.

## Human Review FIX FIRST Follow-Up — 2026-06-23

### Worker
- Added an explicit Mac **Close** toolbar action to the recording/import sheet, including Escape-key support.
- Non-active sheets dismiss immediately. Recording, preparation, transcription, and speaker-label processing require confirmation.
- Confirmed active recording close stops capture, preserves the audio as a retryable Library recording, and unloads the Mac live model. Close during processing uses the existing cancellation/transcript-preservation path.
- Hardened dismissal against two races found by the Auditor: copied imported audio is persisted before dismissal even if cancellation changes the session to failed first; failed Library persistence keeps a durable retry-save condition and does not permit dismissal until a later save succeeds.
- Added narrow Mac launch readiness. Launch prepares the Whisper Live Preview path first without blocking navigation. The existing default/Base English preload starts only after Live Preview preparation succeeds. Failure is visible and retryable without racing lower-priority preload work.
- Did not add a launch screen, progress gate, or Skip Loading flow. Diarization resources remain on demand because current pipeline pacing intentionally unloads transcription before FluidAudio/Sortformer loading to avoid resource contention.
- Tuned display-only speaker grouping: adjacent certain segments with the same speaker group while the gap is 2 seconds or less. Speaker changes, unknown labels, and gaps over 2 seconds start a new turn. The old 60-second and 12-segment display caps were removed. Grouped turns show a start-end timestamp range and retain every underlying segment ID for reassignment.
- Export behavior, raw transcript segments, playback/M4A derivative behavior, SwiftData schema, dependencies, and iOS model selection remain unchanged.

### Auditor
- Final result: **ALIGNED** after two repair rounds.
- Initial review caught import-cancellation orphan risk, non-durable save retry, and readiness overlap. Worker corrected all three.
- Final review confirmed no dependency, engine, server/cloud/off-device, schema, strict-concurrency, project-setting, prohibited-path, OBJ-19, or OBJ-20 drift. Speaker grouping is explicitly authorized by the Human FIX FIRST scope and remains presentation-only.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- Full `TranscriberTests`: PASS, 147/147.
- Focused readiness, close policy, transcript grouping, playback derivative, transcript export, transcript persistence, and shared-audio import tests: PASS, 43/43.
- Updated Mac app launch: PASS; process remained running.
- Launch logs showed model-file network checks followed by Core ML/Apple Neural Engine model loading activity, with no launch crash.
- Native Mac window clicking remains unavailable to this Codex session because macOS Screen Recording/Accessibility permission is not granted.

### Remaining Human Mac Checklist
- [ ] Open Record and confirm the visible Close button dismisses the idle sheet.
- [ ] Start recording, choose Close, confirm the warning appears, and choose Keep Open.
- [ ] Choose Close again, confirm Stop, Save, and Close; verify the sheet closes and the retryable recording appears in Library.
- [ ] Start Live Preview while launch preparation is still active; confirm Preparing/Loading appears instead of failure.
- [ ] If preparation fails, confirm Retry Preparation / Retry Live Preview is available and works.
- [ ] Record/transcribe speech and confirm adjacent same-speaker chunks now appear as one turn unless separated by more than 2 seconds or a speaker change.
- [ ] Confirm playback still works on the completed recording.

### Manager Gate Recommendation
**ASK USER.** Agent-verifiable fixes, Auditor alignment, builds, tests, and launch are green. Real Mac interaction for Close/confirmation, Live Preview readiness, and visual grouping remains the Human-owned acceptance gate. OBJ-18 remains active; OBJ-19 and OBJ-20 were not started.

## Final Human Reviewer Acceptance — 2026-06-25

### Human Decision
- **PROCEED.** OBJ-18 is accepted as a limited Mac companion baseline.
- Further Mac GUI validation/polish is deferred.
- The mobile app remains the primary beta target, so the original objective sequence advances to OBJ-19.

### Acceptance Boundary
- This closeout does not claim exhaustive Human verification of Mac parity.
- The agent-validated implementation, builds, tests, launch result, safe recording-sheet dismissal, narrow readiness ordering, display-only speaker grouping, and preserved playback path are accepted as the current companion baseline.
- Existing intentional Mac gaps remain documented in `DECISIONS.md`; deeper Mac polish returns only after the original 20 objectives or in a separately approved fine-tuning phase.
- No OBJ-19 implementation, new Mac feature work, OBJ-17.2/OBJ-17.3 work, dependency, engine, server/cloud/off-device processing, or prohibited-path change was added during closeout.

### Final Manager Gate
**PROCEED.** OBJ-18 is complete under the Human-approved limited-baseline boundary.
