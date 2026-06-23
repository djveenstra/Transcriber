# OBJECTIVE-17 — Accessibility Pass

_Phase 6. Depends on the UI being largely in place (OBJ-09–15). Closes PRD §15 (J1–J6). RISK R16._

## Mission
Bring the app to Apple's accessibility basics: Dynamic Type, VoiceOver labels/traits (including transcript cards and status dots), contrast in the midnight-blue theme, reachable controls, and status/speaker identity that never relies on color alone.

## Scope
- Dynamic Type: verify text scales; fix any fixed-size truncation on key screens.
- VoiceOver: add accessibility labels/traits to controls, status indicators (the recording dot, model status), and `TranscriptCard` (speaker + timestamp + text read sensibly).
- Contrast audit of `Theme`; fix the flagged `.foregroundStyle(.black)` on primary buttons (use `.white` or computed contrast).
- Non-color status/speaker cues: add text/shape/icon alongside color for speaker identity and recording/status dots.

## Out of Scope
- Full localization (English-first).
- Visual redesign beyond accessibility fixes.

## Worker Instructions
1. Audit each primary screen with Dynamic Type at large sizes (sim accessibility inspector); fix clipping/truncation conservatively.
2. Add `.accessibilityLabel`/`.accessibilityValue`/`.accessibilityAddTraits` where missing; make transcript cards a coherent VoiceOver element.
3. Replace `.foregroundStyle(.black)` per the code-review finding; verify contrast ratios on Theme colors.
4. Add a non-color cue for speaker identity (e.g. speaker initial/shape) and for the recording state (icon/text, not just red dot).

## Auditor Checklist
- [ ] No color-only status/speaker identity remains.
- [ ] Controls + transcript cards have VoiceOver labels/traits.
- [ ] Contrast fixes applied; forced dark mode still coherent.
- [ ] Builds green; concurrency intact; no layout regressions at default sizes.

## QA Checklist
- [ ] Dynamic Type at largest size: key screens readable, no critical truncation.
- [ ] VoiceOver: tab through Record/Library/detail; labels make sense; cards read well.
- [ ] Speaker identity + recording status distinguishable without color.
- [ ] Regression: visual layout intact at default size.

## Acceptance Criteria
- Dynamic Type, VoiceOver, contrast, reachability, and non-color cues meet PRD §15.
- Tests/builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline. Accessibility audited in simulator; final confirmation is a light **device/VoiceOver** check (Human).

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** for agent-verifiable fixes; **ASK USER** for a quick VoiceOver device sanity pass.

## Rollback Considerations
Additive accessibility metadata + small style fixes. Revert removes them with no functional impact.

## Agent Completion Report — 2026-06-21

### Worker Summary
- Implemented conservative accessibility metadata and Dynamic Type resilience across Dashboard, Recording, Library/detail, shared audio detail, transcript cards, speaker rename/reassignment, progress timeline, speaker-label status, Model Lab, Settings microphone/model rows, and share/export controls.
- Added testable transcript accessibility copy and non-color speaker cue helpers.
- Replaced the flagged primary-button `.foregroundStyle(.black)` with white foreground text.
- Replaced the recording color-only dot with an icon+text status cue and gave status/model/microphone/progress UI explicit VoiceOver values.
- Expanded the speaker reassignment ellipsis control to a 44-point target with a specific label/hint.
- Added wrapping fallback for key action/control rows and removed the Library metadata one-line limit.

### Tests Added
- `TranscriptSegmentReassignmentTests.transcriptAccessibilityLabelReadsSpeakerTimeTextAndEditState()`
- `TranscriptSegmentReassignmentTests.speakerCueAddsNonColorSpeakerIdentity()`
- `ProcessingPhaseTests.progressAccessibilityValueIncludesPhaseProgressElapsedAndDetail()`

### Validation Evidence
- Focused accessibility-copy tests: PASS.
- macOS build: PASS.
- iOS simulator build: PASS; existing AppIntents metadata warning only.
- `TranscriberTests`: PASS, 129/129.
- `git diff --check`: PASS.
- QA evidence: [QA.md](../../../QA.md#obj-17--accessibility-pass--2026-06-21).

### Auditor Alignment
- ALIGNED. Changes are presentation-only and stay inside `src/native/Transcriber2/` plus planning/QA docs.
- No transcription, diarization, model, export, persistence, SwiftData schema, dependency, project-setting, or strict-concurrency behavior changes were introduced.
- No `src/python/`, `src/legacy-ios/`, or `XCode App Build/` edits.
- OBJ-18 Mac parity, OBJ-19 cancellation/failure hardening, and OBJ-20 acceptance/refactor work were not started.

### Gate Recommendation
- ASK USER. Agent-verifiable OBJ-17 fixes are complete and green, but `OBJECTIVE-17.md` requires a light Human device/VoiceOver sanity pass before the objective should advance to OBJ-18.

## FIX FIRST Follow-Up Completion Report — 2026-06-21

### Human Reviewer Finding
- Mostly PASS, but transcript detail reading was still uncomfortable at larger text sizes because the speaker-label status card, Diagnostics row, and bottom action controls occupied too much fixed vertical space.

### Worker Follow-Up
- Moved speaker-label status, the speaker-label processing timeline, and Diagnostics into the scrollable transcript content for Recording, Shared Audio, and Library transcript detail surfaces.
- Reworked completed transcript bottom controls into a horizontal compact action bar with 44-point icon targets for Play/Pause, Edit/Rename Speakers, Share, and New Recording where available.
- Added `CompactTranscriptAction` so icon-only controls have shared labels, hints, and symbols.
- Preserved all existing actions and safe-area placement; did not add the future backlog model-change/rerun workflow.

### Tests Added
- `TranscriptSegmentReassignmentTests.compactTranscriptActionsHaveAccessibleLabelsHintsAndIcons()`

### Validation Evidence
- Focused compact-action accessibility test: PASS.
- macOS build: PASS.
- iOS simulator build: PASS on available `iPhone 17, iOS 26.5` simulator after `iPhone 16` was unavailable on this Mac.
- `TranscriberTests`: PASS, 130/130.
- `git diff --check`: PASS.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-transcript-detail-large-text-layout--2026-06-21).

### Auditor Alignment
- ALIGNED. Follow-up is layout/accessibility-only and stays inside `src/native/Transcriber2/` plus planning/QA docs.
- No transcription, diarization, model, export format, persistence, retry, SwiftData schema, dependency, project-setting, strict-concurrency, prohibited-path, OBJ-18, OBJ-19, or OBJ-20 changes were introduced.

### Gate Recommendation
- ASK USER. Agent-verifiable follow-up is complete and green; Human Reviewer should re-check the transcript detail screen at large Dynamic Type before OBJ-17 advances.

## Second FIX FIRST Follow-Up Completion Report — 2026-06-21

### Human Reviewer Finding
- Still not passing because the bottom action icons were too small and the bottom action bar disappeared during transcription/speaker-label processing.

### Worker Follow-Up
- Enlarged compact transcript actions from icon-only 44-point buttons to larger horizontal action buttons with SF Symbols plus short visual labels.
- Added `cancelProcessing` to `CompactTranscriptAction` so processing Cancel uses the same label/hint/icon source as the rest of the compact action bar.
- Added compact processing action bars for Recording, Shared Audio, and saved-recording retry processing so Cancel remains reachable while transcription or speaker-labeling is active.
- Preserved the completed transcript action bar after processing completes and did not add the future model-change/rerun workflow.

### Tests Added or Updated
- Updated `TranscriptSegmentReassignmentTests.compactTranscriptActionsHaveAccessibleLabelsHintsAndIcons()` to cover compact visual titles and Cancel.

### Validation Evidence
- Focused compact-action accessibility test: PASS.
- macOS build: PASS.
- iOS simulator build: PASS on available `iPhone 17, iOS 26.5` simulator.
- `TranscriberTests`: PASS, 130/130.
- `git diff --check`: PASS.
- Physical iPhone build/install/launch: PASS for `com.daniel.transcriber2.beta`.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-transcript-detail-action-bar-legibility--2026-06-21).

### Auditor Alignment
- ALIGNED. Follow-up is layout/accessibility-only and stays inside `src/native/Transcriber2/` plus planning/QA docs.
- No transcription, diarization, model, export format, persistence, retry, save, SwiftData schema, signing, bundle ID, team, entitlement, deployment-target, dependency, project-structure, OBJ-18, OBJ-19, or OBJ-20 changes were introduced.

### Gate Recommendation
- ASK USER. Agent-verifiable follow-up is complete, green, installed, and launched; Human Reviewer should re-check transcript detail at large Dynamic Type before OBJ-17 advances.

## Third FIX FIRST Follow-Up Completion Report — 2026-06-22

### Human Reviewer Finding
- Still not passing because the completed transcript detail Play button did nothing on the installed iPhone build.
- Human Reviewer also noted that Cancel-only processing controls may be acceptable if intentional/accessibile, speaker labeling can feel slow, swipe-down return to Dashboard is not obvious, and background recording lacks an obvious status-area confidence signal.

### Worker Follow-Up
- Restored saved-recording transcript detail Play/Pause by replacing the local `AVAudioPlayer` state with the existing `AudioPlaybackController` used by shared-audio playback.
- Kept the compact larger-icon action bar and its labels/hints intact.
- Confirmed the Cancel-only compact action bar during transcription/speaker-labeling is intentional: completed actions stay unavailable while processing is active, and Cancel remains the clear reachable action.
- Logged the diarization duration/hanging concern, swipe-down discoverability, and background-recording indicator confidence concern in `QA.md` as Human/device follow-ups; no unrelated backlog item was implemented.

### Tests Added or Updated
- No new test was practical for device audio playback because `AVAudioPlayer` output depends on real app/device audio state.
- Re-ran focused compact-action accessibility coverage: `TranscriptSegmentReassignmentTests.compactTranscriptActionsHaveAccessibleLabelsHintsAndIcons()`.

### Validation Evidence
- macOS build: PASS.
- iOS simulator build: PASS; existing AppIntents metadata warning only.
- Focused compact-action accessibility test: PASS.
- `TranscriberTests`: PASS, 130/130.
- `git diff --check`: PASS.
- Physical iPhone build/install/launch: PASS after unlocking/retry; installed and launched `com.daniel.transcriber2.beta`.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-transcript-detail-play-button-regression--2026-06-22).

### Auditor Alignment
- ALIGNED. Follow-up is limited to restoring playback behavior in the completed transcript detail action bar and preserving accessibility/layout work.
- No transcription, diarization, model, export, persistence, retry, save, signing, background-recording, Dynamic Island, navigation redesign, dependency, project-structure, OBJ-18, OBJ-19, or OBJ-20 changes were introduced.

### Gate Recommendation
- ASK USER. Agent-verifiable follow-up is complete, green, installed, and launched; Human Reviewer should re-check Play/Pause and the compact action bar before OBJ-17 advances.

## Fourth FIX FIRST Follow-Up Completion Report — 2026-06-22

### Human Reviewer Finding
- Still not passing because Play gives only about half a second of playback, live preview crashed again, speaker labels did not work or appeared stuck, and the transcript/detail header still wastes vertical space.
- Human Reviewer clarified that Play had not been tested before OBJ-17, so the current playback failure is known broken now but is not proven to be an OBJ-17 regression.
- Human Reviewer asked to stop layout polishing and classify functional behavior before OBJ-17 can pass.

### Worker Follow-Up
- Investigated the OBJ-17 diff against playback, live-preview, recording, speaker-labeling, retry, and session-state code paths.
- Treated playback as in-scope because OBJ-17 changed the completed transcript action bar and its saved-recording Play/Pause wiring.
- Reworked `AudioPlaybackController` to use a retained `AVPlayer`/`AVPlayerItem`, activate the iOS playback audio session before playback, observe playback completion, and reset the visible Play/Pause state without changing recording, transcription, diarization, export, persistence, retry, or save behavior.
- Classified live preview crash and speaker-label stuck/failure as Human/device functional findings that do not appear caused by OBJ-17 based on static diff review: OBJ-17 did not change `TranscriptionSession`, `AudioRecorder`, transcription engines, `DiarizationEngine`, model loading/selection, retry/session-state logic, persistence, or audio save paths.
- Deferred the large transcript/detail header layout issue until playback and device functional behavior are confirmed or separately scoped.
- Preserved the compact larger-icon action bar, labels/hints, status/Diagnostics scrolling, and Cancel visibility during processing. No unrelated backlog item was implemented.

### Tests Added or Updated
- No new tests were added for physical audio playback because the failing behavior depends on installed-device audio output.
- Re-ran focused compact-action accessibility coverage, focused diarization fallback/session coverage, focused processing phase coverage, and the full unit test bundle.

### Validation Evidence
- macOS build: PASS.
- iOS simulator build: PASS; existing AppIntents metadata warning only.
- Focused compact-action accessibility test: PASS.
- Focused `DiarizationFallbackTests`: PASS.
- Focused `ProcessingPhaseTests`: PASS.
- `TranscriberTests`: PASS, 130/130.
- `git diff --check`: PASS before docs and again after docs.
- Physical iPhone build/install/launch: PASS for `com.daniel.transcriber2.beta` after unlocking/retry.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-functional-playback-triage--2026-06-22).

### Auditor Alignment
- ALIGNED. Follow-up is limited to the OBJ-17-touched playback helper and documentation of Human/device findings.
- Accessibility labels/hints remain present on compact actions; Cancel remains reachable during processing.
- No broad transcription, diarization, model, export, retry, save, persistence, signing, background-recording, Dynamic Island, model-change/rerun, delete-downloaded-models, navigation redesign, dependency, project-structure, OBJ-18, OBJ-19, or OBJ-20 changes were introduced.

### Gate Recommendation
- ASK USER. Agent-verifiable playback fix attempt is green, installed, and launched, but Human Reviewer should re-check Play/Pause on device. If playback is acceptable but live preview or speaker-label issues persist, the Manager recommends pausing before OBJ-18 for a targeted stabilization objective rather than expanding OBJ-17.

## Fifth FIX FIRST Follow-Up Completion Report — 2026-06-22

### Human Reviewer Decision
- OBJ-17.5 — Diarization Reliability & Engine Decision is approved in principle as the next checkpoint after OBJ-17 is accepted, committed, and merged.
- Do not advance directly to OBJ-18. Mac parity waits until the diarization checkpoint is handled.
- Do not apply `PLAN.md`, `OBJECTIVE.md`, `DECISIONS.md`, or `OBJECTIVE-17.5.md` changes until OBJ-17 is ready to close.

### Worker Follow-Up
- Kept OBJ-17.5 as a ready proposal only; no planning files for OBJ-17.5 were applied.
- Reduced transcript/detail vertical waste by switching iOS navigation titles to compact inline display mode on the recording/transcript screen, saved recording detail, and shared recording detail.
- Preserved native navigation bar back/dismiss affordances, compact larger-icon action bar, accessibility labels/hints, status/Diagnostics scrolling, and Cancel visibility during processing.
- Left the prior scoped Play/Pause fix in place for Human device verification.
- Implemented no diarization architecture, pyannote, server, new dependency, off-device behavior, Mac parity, or OBJ-18 work.

### Validation Evidence
- macOS build: PASS.
- iOS simulator build: PASS; existing AppIntents metadata warning only.
- Focused compact-action accessibility test: PASS.
- `TranscriberTests`: PASS, 130/130.
- Physical iPhone build: PASS using existing project/scheme/signing settings.
- Install/run: updated app installed to the connected iPhone. Launch was attempted three times and blocked because the device was locked.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-transcript-detail-header-recheck-build--2026-06-22).

### Gate Recommendation
- ASK USER. OBJ-17 is ready for another Human recheck of Play/Pause, transcript/detail header spacing, compact action bar accessibility, and Cancel visibility during processing, but the agent could not launch the installed build while the phone was locked.

## Sixth FIX FIRST Follow-Up Completion Report — 2026-06-22

### Human Reviewer Finding
- Still not passing because Play/Pause gives the same short or failed playback behavior on the installed iPhone build.
- Human Reviewer marked the improved transcript/detail header layout PASS.
- Bottom action bar is visible after canceling processing; during active processing only Cancel is visible.
- Diarization/speaker labeling remains a blocking product concern because a short recording again became stuck or unusably slow after about 1.5-2 minutes.

### Product Direction Captured for OBJ-17.5
- Keep OBJ-17 open and do not advance directly to OBJ-18.
- OBJ-17.5 remains queued before OBJ-18, but no OBJ-17.5 files or planning changes were applied in this pass.
- The proposed OBJ-17.5 planning text should include default/Base English model preload on app launch, investigation of diarization resource warm/preload, background processing while users navigate elsewhere, visible per-recording processing states in Dashboard/Library/detail, timeout/failure handling so speaker identification cannot hang forever, and transcript availability even if speaker labeling fails.

### Worker Follow-Up
- Treated Play/Pause as in-scope OBJ-17 fallout because OBJ-17 changed the saved-recording transcript detail action area.
- Repaired `AudioPlaybackController` by returning to retained local-file `AVAudioPlayer` playback, activating the iOS playback audio session before playback, adding file type hints for common saved/imported audio formats, updating Play/Pause published state, and resetting state on finish or decode failure.
- Preserved the compact larger-icon action bar, accessibility labels/hints/traits, status/Diagnostics scrolling, and Cancel visibility during processing.
- Recorded the Human PASS for the compact inline transcript/detail header.
- Implemented no model preload, background processing, diarization architecture, transcription behavior, diarization algorithm, model behavior, export behavior, retry behavior, save behavior, persistence behavior, OBJ-18 work, or unrelated backlog item.

### Tests Added or Updated
- Added `TranscriptSegmentReassignmentTests.playbackFileTypeHintsCoverSavedAndImportedAudio()` for CAF, M4A, WAV, MP3, and unknown extension hint behavior.

### Validation Evidence
- macOS build: PASS.
- iOS simulator build: PASS; existing AppIntents metadata warning only.
- Focused playback hint test: PASS.
- Focused compact-action accessibility test: PASS.
- `TranscriberTests`: PASS, 131/131 after a serial rerun; the first parallel attempt hit an Xcode build database lock.
- `git diff --check`: PASS.
- Physical iPhone build/install/launch: PASS for `com.daniel.transcriber2.beta` using existing project/scheme/signing settings.
- QA evidence: [QA.md](../../../QA.md#obj-17--fix-first-follow-up-local-playback-repair--2026-06-22).

### Auditor Alignment
- ALIGNED. Follow-up remains scoped to accessibility/layout plus direct Play/Pause action-bar fallout.
- Compact action labels/hints remain present and Cancel remains reachable during processing.
- No broad transcription, diarization, model, preload, background-processing, export, persistence, signing, dependency, project-structure, prohibited-path, OBJ-18, OBJ-19, or OBJ-20 changes were introduced.

### Gate Recommendation
- ASK USER. The scoped Play/Pause code fix is green, installed, and launched, but Human Reviewer must re-check real iPhone playback before OBJ-17 can close.

## Final Closeout Report — 2026-06-23

### Human Reviewer Result
- PASS on the installed iPhone build.
- Playback works, continues past 1 second, pauses, and resumes after Pause.
- Back/Forward/player controls are acceptable.
- The dedicated mini-player/playback-safe M4A derivative approach is acceptable.
- Original recording preservation remains required; the M4A derivative is accepted as a cache/regenerable playback artifact, not the canonical source of truth.
- Header/title layout is much better and acceptable.
- Compact player/action controls and OBJ-17 accessibility/layout items are acceptable.

### Worker Closeout
- OBJ-17 scope is satisfied for accessibility, layout, compact transcript actions, and accepted playback repair.
- No OBJ-17.1 implementation, OBJ-18 implementation, model preload, background processing, diarization architecture, pyannote/server/off-device work, sherpa-onnx work, new dependency, model-change/rerun-from-transcript backlog, or delete-downloaded-models backlog was started.

### Auditor Alignment
- ALIGNED. Final closeout remains inside accepted OBJ-17 playback/action-bar/layout/accessibility work plus planning/QA updates.
- No transcription, diarization algorithm, model, export, retry, save, persistence, signing, background-recording, SwiftData schema, dependency, strict-concurrency, prohibited-path, app-redesign, OBJ-18, OBJ-19, or OBJ-20 work was introduced.

### QA Evidence
- QA evidence: [QA.md](../../../QA.md#obj-17--final-human-reviewer-pass-and-gate--2026-06-23).
- macOS build: PASS.
- iOS simulator build: PASS.
- Physical iPhone build/install/launch: PASS.
- Full `TranscriberTests`: PASS, 133/133.
- Focused playback/cache tests: PASS.
- Focused compact-action accessibility test: PASS.
- `git diff --check`: PASS.

### Gate Decision
- PROCEED for OBJ-17.
- Diarization/speaker-label reliability remains a blocking checkpoint before OBJ-18 and is moved to [OBJECTIVE-17.1.md](OBJECTIVE-17.1.md).
