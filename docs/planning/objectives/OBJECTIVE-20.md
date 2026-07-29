# OBJECTIVE-20 — Beta Acceptance / Final QA
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 8. Final original objective. Depends on all prior objectives. Closes PRD §17 agent-verifiable acceptance, includes the Human-approved narrow Mac acceptance hardening pass, and hands the remaining device gates to the Human Reviewer._

## Mission
Verify Transcriber 2.0 Beta against the original objectives, document remaining limitations honestly, and provide a concise final iPhone acceptance checklist. Do not add features or begin the future fine-tuning phase.

## Scope
- Audit OBJ-01 through OBJ-20 and map expected behavior to existing evidence.
- Run the full agent baseline: macOS build, iOS Simulator build, and `TranscriberTests`.
- Run focused acceptance/failure, playback, export, diarization/session, model-readiness, microphone, recording-reliability, and data-preservation tests.
- Identify any final beta blocker: audio/transcript loss, permanent stuck state, core-workflow crash, inability to record/transcribe/review/export, unbounded processing without cancel/retry, or a misleading complete state with missing data.
- Record agent-verifiable acceptance and known limitations in [QA.md](../../../QA.md).
- Produce the final Human-owned iPhone checklist, including the remaining OBJ-19 hardware/framework checks.
- Update planning documents without advancing into a future feature phase.
- Before final iPhone QA, run and inspect the Mac companion app and fix only narrow issues that block basic launch, navigation, recording/live-preview dismissal, readiness, import, Library, playback, transcript review, export/share, or cancel/failure usability.

## Out of Scope
- Launch loading/readiness screen or new default-model preload UI.
- Rerun transcription with another model.
- Delete downloaded models.
- `TranscriptionSession` decomposition or other broad refactors.
- Language-picker work or speaker-color parsing changes.
- New diarization engines, sherpa-onnx, pyannote, dependencies, server/cloud/off-device processing.
- A full Mac redesign or polish beyond narrow blockers found during the Human-approved pre-iPhone acceptance pass.
- UI redesign, schema changes, or feature work beyond a narrow directly observed beta-blocker fix.
- Changes to accepted playback/M4A behavior unless required to fix a direct beta blocker.
- Any changes in `src/python/`, `src/legacy-ios/`, or `XCode App Build/`.

## Worker Instructions
1. Perform the acceptance audit before changing production code.
2. Build a 20-objective matrix with expected behavior, existing evidence, agent coverage, Human/device coverage, limitation/blocker, and acceptance status.
3. Re-run the complete baseline and focused acceptance suites.
4. Make no production-code change unless validation exposes a narrow, direct beta blocker within the allowed hardening scope.
5. If a blocker requires product choice, feature scope, a dependency, schema work, or broader architecture change, stop at `ASK USER`.
6. Report files inspected/touched, test evidence, the acceptance matrix, and confirmation that deferred work was not implemented.
7. For the Mac acceptance pass, launch and inspect the app where automation permits; preserve safe close/import persistence, ordered Live Preview readiness, and accepted playback/M4A behavior. Stop at `ASK USER` if a finding needs product choice, broad redesign, schema/dependency work, or an unrelated dirty-tree change.

## Auditor Checklist
- [ ] Human-approved acceptance-only scope is reflected consistently in planning documents.
- [ ] No deferred feature/fine-tuning work was implemented.
- [ ] No prohibited path, dependency, schema, new-engine, server/cloud, or off-device change.
- [ ] No data-preservation weakening.
- [ ] No accepted playback/M4A regression.
- [ ] Every original objective has evidence or an explicit Human-owned check.
- [ ] Strict concurrency and deliberate pipeline pacing remain unchanged.

## QA Checklist
- [ ] `git diff --check`.
- [ ] macOS build.
- [ ] iOS Simulator build.
- [ ] Full `TranscriberTests`.
- [ ] Focused acceptance/failure tests.
- [ ] Focused playback tests.
- [ ] Focused TXT/SRT/JSON export tests.
- [ ] Focused diarization/session tests.
- [ ] Focused model-readiness tests.
- [ ] Focused microphone/recording-reliability/data-preservation tests.
- [ ] Physical iPhone build/install if available.
- [ ] Final Human iPhone checklist recorded without claiming Human PASS.
- [ ] Mac app launch and observable navigation/window behavior.
- [ ] Focused Mac close, import/persistence, playback, export/share, and Live Preview readiness tests.

## Acceptance Criteria
- All agent-verifiable acceptance areas are green or have an honest `FIX FIRST`/`BLOCKED` result.
- Every original objective has current evidence or a documented Human-owned check.
- No known beta blocker is left undocumented.
- Deferred features and fine-tuning remain deferred.
- The final Human iPhone checklist is clear enough to run without developer interpretation.
- Planning documents and QA evidence accurately represent the final gate.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline, `git diff --check`, and focused suites listed in the QA Checklist. Physical-device behavior remains Human-owned.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Agent acceptance may be complete while the milestone remains `ASK USER` for final iPhone validation.

## Gate Decision
- **PROCEED** only after agent acceptance is green and the Human Reviewer accepts the required device matrix.
- **FIX FIRST** if agent or device validation finds a beta blocker.
- **ASK USER** when agent acceptance is green but Human-owned device validation remains.
- **BLOCKED** if an external dependency prevents meaningful acceptance validation.

## Rollback Considerations
The expected objective diff is planning and QA documentation only. Any narrow blocker fix must be independently reversible and re-audited before QA.

## Agent Acceptance Report — 2026-06-25

### Manager
- Gate recommendation: **ASK USER**.
- No known beta blocker was found in agent-verifiable evidence.
- The final iPhone checklist is required before original-beta closeout.
- OBJ-20 remains active; no future feature or fine-tuning phase has started.

### Worker
- Inspected the governing product/planning documents, all original objective reports, QA evidence, active native tests, and the final repository state.
- Produced the 20-objective acceptance matrix recorded in [QA.md](../../../QA.md#obj-20--beta-acceptance--final-qa--2026-06-25).
- Made no production-code changes and no hardening fix was required.
- Updated planning documents to reflect the Human-approved acceptance-only scope.
- Confirmed deferred features were not implemented.

### Auditor
- Final result: **ALIGNED** after one stale “tech debt” dependency-graph label was corrected.
- No deferred feature work, prohibited-path change, dependency, schema, new engine, server/cloud/off-device work, strict-concurrency weakening, data-preservation weakening, or accepted playback/M4A change.
- Every original objective has evidence or an explicit Human-owned check.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- iOS Simulator build: PASS.
- Full `TranscriberTests`: PASS, 163/163.
- Focused acceptance suites: PASS, 150 executions.
- Physical iPhone 17 Pro build/install: PASS. Command-line launch was blocked because the phone was locked.
- One Bluetooth reconnect test failed during an initial parallel run, then passed independently, in the serial full suite, and in a second full-suite run; treated as a timing flake, not a reproduced product defect.
- Final Human device checklist and known limitations are recorded in [QA.md](../../../QA.md#obj-20--beta-acceptance--final-qa--2026-06-25).

### Current Gate
**ASK USER.** Agent-verifiable beta acceptance is green. The Human Reviewer must run and accept the final iPhone checklist before OBJ-20 can move to `PROCEED`.

## Mac App Acceptance-Hardening Report — 2026-06-27

### Manager
- Gate recommendation: **ASK USER**.
- The Mac companion is usable enough for the limited beta baseline in agent-observed behavior after two narrow blocker fixes.
- A short Human Mac spot-check remains appropriate before final iPhone QA: audible playback, visual layout judgment, one real external import, and one real share destination.
- OBJ-20 remains final acceptance/hardening. No feature/fine-tuning phase has started.

### Worker
- Found and fixed a Library navigation freeze caused by synchronous shared-inbox enumeration on the main UI thread.
- Found and fixed a blank Mac export/share sheet caused by separate URL and presentation state racing.
- Added focused shared-inbox filtering/enumeration coverage.
- Observed clean launch; four-tab navigation; Live Preview preparation; safe active/idle close; retryable saved audio; import-picker cancellation; Library detail; playback; transcript/speaker/diagnostics presentation; export creation; and corrected share-sheet presentation.
- Production files touched: `RecordingView.swift` and `SharedAudioInbox.swift`. Test file touched: `SharedAudioInboxTests.swift`.
- No deferred feature, redesign, schema/dependency/engine/cloud/off-device work, prohibited-path edit, playback/M4A change, commit, merge, or push.

### Auditor
- Final result: **ALIGNED**.
- Confirmed no prohibited paths, dependency/project-setting change, new engine, server/cloud/off-device work, deferred feature, schema change, strict-concurrency weakening, data-preservation weakening, import-persistence change, or accepted playback/M4A change.
- Confirmed the canceled inbox task cannot publish stale results and the atomic share item is a narrow, reversible presentation fix.

### QA
- `git diff --check`: PASS.
- macOS build: PASS.
- Generic iOS Simulator build: PASS.
- Full `TranscriberTests`: PASS, 164/164.
- Focused suites: recording close/reliability 5/5; inbox/persistence 13/13; cancellation/failure preservation 10/10; playback/transcript 15/15; export 9/9; model readiness/preflight 9/9.
- Independent Mac run: PASS for launch, four-tab navigation, responsive Library, saved/completed item opening, progress/pause playback, transcript/speaker/diagnostics rendering, recording-sheet close/cancel recovery, import-picker cancel, and export controls. System share destination completion, audible playback, real external import, and visual layout judgment remain Human checks.
- Screenshot capture was unavailable; GUI evidence came from the macOS accessibility tree and observed live state changes.

### Current Gate After Mac Hardening
**ASK USER.** Agent-verifiable Mac acceptance is green. Complete the short Human Mac spot-check, then proceed to the already documented final iPhone checklist. Do not advance OBJ-20 or begin future feature/fine-tuning work yet.

## Final Beta 2.0 Acceptance Report — 2026-06-28

### Manager
- Final gate: **PROCEED**.
- The Human Reviewer accepted the iPhone app and limited Mac companion as sufficient to close Beta 2.0.
- OBJ-20 and the original 20-objective roadmap are complete.
- No future feature or Beta 2.1 implementation was started during closeout.

### Final evidence
- `git diff --check`: PASS.
- macOS build: PASS.
- Generic iOS Simulator build: PASS.
- Full `TranscriberTests`: PASS, 164/164.
- Focused Mac close/readiness/import/persistence/playback/export and failure-preservation suites: PASS.
- Final Human Reviewer result: **PASS**. Everything works mostly and is acceptable for closing the original Beta 2.0 build.

### Accepted product boundary and known limitations
- The mobile app remains the primary target.
- The Mac app is accepted as a useful limited companion baseline, not a deeply polished Mac product.
- Diarization may still require retry or manual cleanup, especially with more speakers.
- Further visual polish, performance/device exploration, deeper Mac GUI QA, and feature fine-tuning remain appropriate future work.
- No known remaining issue was accepted as a Beta 2.0 blocker. Audio/transcript preservation, retryable failure handling, and accepted playback/M4A behavior remain intact.

### Deferred Beta 2.1 planning backlog
- Launch readiness screen and default-model preload.
- Priority loading: Live Preview first, transcription model second, diarization resources third.
- Skip Loading with continued background loading.
- Rerun transcription with a different model.
- Delete downloaded models.
- Further speaker grouping polish.
- Further sticky/compact player and header polish.
- Broader diarization-engine evaluation if FluidAudio becomes limiting.
- Deeper Mac GUI QA and polish.
- Background processing/job architecture improvements.
- Broader UI polish and feature fine-tuning.

These items are preserved for discussion in [DECISIONS.md D-016](../../../DECISIONS.md#d-016--2026-06-28--accept-beta-20-and-preserve-beta-21-planning-backlog). None is a Beta 2.0 blocker, active objective, or implemented part of this closeout.

### Final status
**PROCEED.** Beta 2.0 acceptance is complete. Beta 2.1 remains planning-only until the Human Reviewer explicitly approves a new objective and implementation branch.
