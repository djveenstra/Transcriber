# QA.md — Transcriber Mac QA Evidence Log

Last updated: 2026-07-29

This file is append-only evidence. New VX roadmap evidence is recorded at the top of the active section below. The original Beta 2.0 evidence remains in place under “Historical Beta 2.0 evidence” so existing objective links and audit history continue to work.

## VX evidence entry format

```
## VX-NN — <title> — <date>
- Risk tier:
- Commit / working tree:
- Allowed paths checked:
- Mac build:
- Unit/integration tests:
- Objective-specific benchmark:
- Migration/legacy-data evidence:
- Failure and cancellation evidence:
- Manual Mac UI:
- Privacy/licensing/package evidence:
- Human-owned checks:
- Auditor: ALIGNED / DRIFT FOUND / not required
- Verdict: PASS / FAIL / PARTIAL
```

## Active Mac baseline commands

```sh
xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild test -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TranscriberTests
```

## VX-01 — Mac baseline and benchmark charter — 2026-07-29

- Risk tier: docs-only with read-only build, test, and resource inspection.
- Commit / working tree: starting commit `ae01ecedfe3be891471d9f79a08f097d70fd1dd7`; pre-existing dirty governance rewrite and Python-extraction deletions preserved; no staging or commit.
- Allowed paths checked: only VX-01 objective/evidence plus active governance and QA documents changed; production/test source, Xcode project, packages, sibling workspaces, legacy tree, assets, private audio, and `Voiceprint-downloads/` unchanged.
- Mac build: **PASS** — `** BUILD SUCCEEDED **`; 9.28 seconds; command-process peak memory footprint 78,578,600 bytes.
- Unit/integration tests: **PASS** — 164 passed, 0 failed, 0 skipped; `** TEST SUCCEEDED **`; 16.71 seconds; command-process peak memory footprint 153,076,816 bytes.
- Objective-specific benchmark: **PASS for charter** — manifest, approval, split, ground-truth, metric, category, and comparison rules documented; no model-quality run and no threshold invented.
- Migration/legacy-data evidence: not applicable; application data and schema were not accessed or changed. Current storage/read behavior was documented from code and passing persistence tests.
- Failure and cancellation evidence: existing unit bundle passed applicable persistence, corrupt-data, cancellation, timeout, fallback, retry, and stale-attempt tests; VX-01 introduced no behavior.
- Manual Mac UI: not run; no UI changed.
- Privacy/licensing/package evidence: private audio was not accessed; tracked evidence omits private paths/content and sensitive machine identifiers; exact package pins recorded and unchanged.
- Human-owned checks: future approval of exact private recordings or a bounded collection; supported performance target; post-baseline metric priorities.
- Auditor: not required by docs-only tier.
- Verdict: **PASS**.

## VX-02 — Mac-only boundary and removal inventory — 2026-07-29

- Risk tier: docs-only with read-only cross-workspace ownership inspection.
- Commit / working tree: pre-existing Mac dirty state preserved; iOS sibling inspected read-only and found not to be a Git repository at its root; no staging, commit, or push.
- Allowed paths checked: only VX-02 objective/evidence plus active governance and QA documents changed. No application, Xcode, sibling, legacy, stale-tree, asset, audio, model, dependency, or user-data content changed.
- Mac build: not rerun because VX-02 changed no code/project files; green VX-01 build remains applicable.
- Unit/integration tests: not rerun because VX-02 changed no code/test files; VX-01 passed 164/164.
- Objective-specific benchmark: not applicable.
- Migration/legacy-data evidence: no data or migration changes. `src/legacy-ios/` unique reference value and sibling copy were inventoried without modification.
- Failure and cancellation evidence: not applicable to the read-only inventory.
- Manual Mac UI: not run; no UI changed.
- Privacy/licensing/package evidence: root audio was identified only by already-known filename and tracked/ignored state; no content or extended metadata inspected. `Voiceprint-downloads/` remained ignored research material.
- Ownership evidence: Mac and iOS `src/native/Transcriber2/` trees each contained 71 non-`.DS_Store` files and `diff -qr` returned exit 0. The iOS sibling lacks root Git recovery history, so equality did not become deletion permission.
- Human-owned checks: nine explicit ownership, archive, removal, shared-inbox, artifact, audio, and visual-reference decisions are listed in the inventory.
- Auditor: not required by docs-only/read-only tier.
- Verdict: **PARTIAL** — inventory PASS; Human removal/ownership decisions remain.

## VX-03 — Versioned processing contracts and migration design — 2026-07-29

- Risk tier: docs-only design for future Critical storage and migration work; independent Auditor required before QA.
- Commit / working tree: pre-existing dirty worktree preserved; no staging, commit, or push.
- Allowed paths checked: VX-03 objective/evidence and active governance/QA only. `git diff --name-status -- src/native/Transcriber2` was empty.
- Mac build: not rerun because VX-03 changed no code/project files; VX-01 canonical build passed.
- Unit/integration tests: not rerun because VX-03 changed no code/test files; VX-01 passed 164/164.
- Objective-specific benchmark: not applicable; no accuracy claim.
- Migration/legacy-data evidence: design specifies durable random recording/source IDs, lazy per-recording adoption, exact legacy transcript/speaker/display preservation, dual-write, old-build compatibility, and an implementation test matrix. No live store or user data accessed.
- Failure and cancellation evidence: design covers interrupted writes, corrupt/unknown versions, stale generations, late/canceled attempts, correction races, SwiftData failure after manifest commit, pointer failure, low disk, missing audio, cleanup, deletion partial failure, and rollback.
- Manual Mac UI: not run; no UI changed.
- Privacy/licensing/package evidence: no private audio/application data/models accessed; envelopes/logs omit private paths/content; package revisions unchanged.
- Auditor: initial **DRIFT FOUND** for identity durability, commit/recovery contradiction, legacy Human-work replacement risk, and missing source-audio identity recovery. Corrections applied; residual compatibility label corrected; final **ALIGNED**.
- QA: independent **PASS** for all agent-verifiable criteria. `git diff --check` PASS; selected relative links PASS; eight contract families, transcript history, stable IDs/timebase, provenance/uncertainty, placement, migration, atomicity, corruption, cleanup, rollback, privacy, and future tests present.
- Strict concurrency/dependencies: `SWIFT_STRICT_CONCURRENCY = complete` unchanged; FluidAudio `17081252411e0cf69574ee85ec1cd4675765c458`, WhisperKit `94cf6b120cf9dde32d9dea01acc326e77371302c`, and Swift Argument Parser 1.8.2 / `6a52f3251125d74daf04fcbd5e6f08a75d074382` unchanged.
- Human-owned checks: approve the nine placement/migration/history/cleanup/corruption principles in VX-03 migration design §12.
- Verdict: **PARTIAL at roadmap gate** — agent QA PASS; Human approval pending.

## Current governance baseline — 2026-07-28

- Scope: read-only inspection and pre-rewrite validation.
- Mac build: **PASS** — `** BUILD SUCCEEDED **`.
- Unit tests: **PASS** — `** TEST SUCCEEDED **`.
- Packages resolved: pinned WhisperKit, FluidAudio, and Swift Argument Parser dependencies.
- Production code changed: none.
- Important limitation: this proves the checked-out Mac target and unit suite are green; it does not prove real microphone, downloaded-model, private benchmark, long-run, packaging, or UI behavior.

## Standing VX regression checklist

Apply the rows relevant to the objective and say when a row is not applicable:

1. Existing recordings and transcript blobs still decode.
2. Original audio remains untouched on success, failure, retry, cancellation, and migration.
3. Record and import persist audio before processing.
4. Draft transcript remains usable if diarization, identity, reconciliation, or adjudication fails.
5. Retry does not overwrite a newer attempt or Human correction.
6. Cancel clears activity and preserves the last useful persisted result.
7. Model readiness comes from actual files/loadability, not a stale flag.
8. Export and playback still work for existing recordings.
9. Strict concurrency and dependency pins are unchanged unless explicitly scoped.
10. Private paths, audio, transcript text, embeddings, and profiles do not leak into logs or Git.
11. The selected production pipeline is no more complex than benchmark evidence justifies.

---

## Historical Beta 2.0 evidence

The content below is retained verbatim as pre-split evidence. Its iOS commands and device scripts are historical in this Mac workspace.

## Historical standing regression checklist (scope to touched screens)

1. App launches; all tabs reachable; default model state correct.
2. Record → stop → transcript appears → labels apply (or fail gracefully with retry).
3. Import a file → transcribe → share TXT.
4. Library lists recordings; open detail; play; rename; share; delete (audio + row handled).
5. Cancel during processing leaves transcript/audio safe.
6. No new strict-concurrency warnings; both builds + unit tests green.
7. Forced dark mode intact; no invisible text; no broken share sheet.

## Device test scripts (Human Reviewer — iPhone 17 Pro / Mac)

### OBJ-08 iPhone device validation checklist — OBJ-04 through OBJ-08 gates

Use an iPhone 17 Pro or equivalent beta test device. Install the current OBJ-08 build, keep the device plugged in for long runs when practical, and record any app alert text exactly. Pass criteria for every recording item: original audio remains available in the app, the app does not crash, Stop works, final transcription can be started or retried from the Library, speaker labels complete or fail safely with retry, and sharing/export remains available after completion.

#### OBJ-04 model preload, persistence, and offline checks

- [ ] Launch fresh install with network available. Confirm the default transcription model begins preload/download without blocking Record startup.
- [ ] When download finishes, confirm Settings shows the default model as downloaded/ready.
- [ ] Force-quit the app, relaunch, and confirm the same model remains downloaded/ready without redownloading.
- [ ] Reboot the iPhone, relaunch, and confirm the same model remains downloaded/ready without redownloading.
- [ ] Enable Airplane Mode after the model is ready. Record a short sample, stop, and confirm transcription starts and completes offline.
- [ ] Realistic corrupt/remove-model recovery where feasible: with a development build or debugger-supported method, remove or corrupt the downloaded model cache, relaunch/open Settings, and confirm the app shows missing/corrupt or failed state plus Repair/Redownload instead of silently claiming ready.

#### OBJ-05 microphone enumeration and routing checks

- [ ] Open Settings with no accessory attached. Confirm Automatic/default and built-in iPhone microphone options are available where the platform exposes them.
- [ ] Attach a Bluetooth/headset microphone. Reopen or refresh Settings and confirm the Bluetooth/headset input appears with a recognizable name.
- [ ] Select the built-in iPhone microphone, start a recording, speak near the phone, stop, and confirm captured audio matches the selected route.
- [ ] Select the Bluetooth/headset microphone, start a recording, speak into that microphone away from the phone, stop, and confirm captured audio matches the selected route.

#### OBJ-06 Test Mic checks

- [ ] In Settings, select Automatic/default and tap Test Mic. Confirm any permission prompt appears if needed and the test starts.
- [ ] While Test Mic is running, speak near the active microphone and confirm the meter responds.
- [ ] Tap Stop and confirm the meter stops and the microphone is released.
- [ ] Start Test Mic again, leave Settings, return to Settings, and confirm test capture stopped cleanly.
- [ ] After leaving Settings, start a normal recording and confirm it starts normally.

#### OBJ-07 fallback and active-mic display checks

- [ ] Select a Bluetooth/headset microphone, disconnect or power off that device, then start recording. Confirm recording starts instead of blocking.
- [ ] Confirm the active-mic label during recording names the actual microphone being used.
- [ ] Confirm the fallback notice appears when the selected microphone is unavailable.
- [ ] Stop the recording and confirm the audio is saved and retryable/transcribable.

#### OBJ-08 background, lock-screen, interruption, route-change, and duration checks

- [ ] Start recording, wait 30 seconds, lock the phone for at least 2 minutes, unlock, stop, and confirm audio was preserved.
- [ ] Start recording, switch to another app for at least 2 minutes, return, stop, and confirm audio was preserved.
- [ ] Start recording with a Bluetooth/headset microphone, disconnect it during recording, and confirm the app either keeps recording on a fallback route with an updated active-mic label/notice or stops gracefully with saved retryable audio.
- [ ] Start recording, trigger an audio interruption where feasible (for example, begin another app's audio capture or receive a phone/FaceTime interruption), and confirm Transcriber either recovers recording state correctly or stops gracefully with saved retryable audio.
- [ ] Record 5 minutes, stop, transcribe, speaker-label, and share TXT.
- [ ] Record 15 minutes, stop, transcribe, speaker-label, and share TXT.
- [ ] Record 30 minutes, stop, transcribe, speaker-label, and share TXT.
- [ ] During the 30-minute run, note start battery %, end battery %, whether the device became hot, whether the app became sluggish, and whether memory warnings/crashes occurred.
- [ ] For any graceful-stop case, confirm the Library contains the interrupted recording, original audio plays back, and retry transcription is available.

---

## Evidence

## OBJ-01 — Governance, Green Baseline & Data-Safety Guardrails — 2026-06-18
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS
- Unit/integration tests: 49 passed / 49 total using `-only-testing:TranscriberTests`; existing `RecordingPersistenceTests` cover `segments`, `rawTranscription`, and `speakerNames` round-trip plus corrupted blob decode-to-empty behavior.
- Manual UI: not run; OBJ-01 changed planning docs only and did not touch app UI or production behavior.
- Failure injection: temporarily broke the `Recording.segments` setter; `RecordingPersistenceTests.segmentsRoundTripThroughSetterAndGetter()` failed as expected, then the production file was restored and the unit-test bundle passed again.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. Full generated-scheme `xcodebuild test` attempted to launch `TranscriberUITests` and failed before UI-test runner bootstrap; baseline command corrected to target `TranscriberTests` per DECISIONS.md D-006.
- Device gates outstanding: none for OBJ-01. Human approval is still required before archiving or moving `XCode App Build/`; recommendation is to archive it later because it is a stale starter Xcode tree with its own nested `.git`, while treating it as read-only until Daniel approves.
- Verdict: PASS (defects: generated macOS UI-test runner is not usable as part of the baseline; documented and excluded from agent baseline without modifying the Xcode project).

## OBJ-02 — File-Based Model Readiness — 2026-06-18
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS
- Unit/integration tests: 53 passed / 53 total using `-only-testing:TranscriberTests`; new tests: `TranscriptionModelReadinessTests.whisperModelIsPresentWhenRequiredCompiledModelsExist()`, `whisperModelIsMissingWhenAnyRequiredModelIsAbsent()`, `whisperModelAcceptsPackagedCoreMLFiles()`, and `whisperDownloadedHintIsReconciledAgainstFiles()`.
- Manual UI: not run; OBJ-02 changed readiness logic only and did not change navigation, Settings layout, Model Lab layout, microphone behavior, or recording flow. Model Lab and Settings continue reading `FinalTranscriptionModelChoice.isDownloaded`, now backed by file checks.
- Failure injection: temp-directory fixtures simulated present, partial/missing, packaged Core ML, and stale remembered Whisper downloaded-flag states; missing/partial fixtures returned not-ready and reconciled stale hints away.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio, transcript, navigation, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: real device force-quit/relaunch/reboot persistence and offline behavior remain Human-owned gates for later OBJ-04/OBJ-20 validation.
- Verdict: PASS (defects: none found in agent-verifiable scope).

## OBJ-03 — Model Lifecycle States + Repair/Redownload — 2026-06-18
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS
- Unit/integration tests: 57 passed / 57 total using `-only-testing:TranscriberTests`; new tests: `ModelRegistryTests.lifecycleStatusCoversRequiredStateSet()`, `downloadStateForOtherModelDoesNotOverrideThisModel()`, `removingWhisperCacheLeavesSiblingUserDataUntouched()`, and `registryRemembersDownloadedModelsWithoutClaimingReadiness()`.
- Manual UI: not run in simulator; code review verifies Settings now renders per-model storage rows with status, measured on-disk size when present, selected-model marker, and Download/Repair/Redownload actions. No navigation, Dashboard, microphone, Library, or recording-flow changes were made.
- Failure injection: unit fixtures cover all seven lifecycle states, stale/missing downloaded-model hints, partial cache footprints, active download/failed snapshots, and cache-only repair deletion. The repair safety test creates sibling `Recordings` and transcript files beside the model cache and verifies they remain untouched when the Whisper model cache is removed.
- Auditor: ALIGNED. Auditor verified OBJ-03 scope, registry mapping to existing model choices, no OBJ-04 preload/launch-refresh/verify-before-process work, no dependency/config/schema drift, and cache-only Repair/Redownload paths.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio, transcript, Dashboard, microphone, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: real model download, force-quit/relaunch/reboot persistence, offline transcription after download, and realistic corrupt/remove-model recovery remain Human-owned or later-objective gates for OBJ-04/OBJ-20. OBJ-03 uses a no-op verification hook that marks present files ready; fuller verify-before-process behavior is intentionally deferred to OBJ-04.
- Verdict: PASS (defects: none found in agent-verifiable scope).

## OBJ-04 — Default Preload, Status Refresh & Verify-Before-Process — 2026-06-18
- Tier: agent-verifiable validation accepted complete; Human-owned device gates deferred.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: 60 passed / 60 total using `-only-testing:TranscriberTests`; new tests: `FinalModelPreflightTests.verifySuccessUsesSelectedModel()`, `verifyFailureFallsBackToDefaultWithNotice()`, `verifyFailureThrowsWhenFallbackIsUnavailable()`, `ModelRegistryTests.refreshedStatusesUseLatestFileSnapshots()`, and `defaultPreloadOnlyStartsWhenDefaultIsMissingAndIdle()`.
- Manual UI: not run on a simulator/device. Code review verifies launch and Settings `.onAppear` now refresh file-based status hints and schedule non-blocking default preload through the existing downloader; Settings navigation/layout was not changed.
- Failure injection: unit fixtures simulate selected-model verification success, selected-model missing/corrupt with default fallback ready, selected-model missing/corrupt with fallback unavailable, refreshed present-to-missing file snapshots, and preload suppression when files are present or another download is active.
- Auditor: ALIGNED. Auditor verified OBJ-04 scope, no Dashboard/microphone/navigation work, no `Recording` schema change, no dependency bump, no strict-concurrency weakening, touched paths limited to the active native app/tests plus this evidence, and data-safety/fallback notices preserved on partial-work paths.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio deletion, transcript deletion, Dashboard, microphone, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates deferred: real-device default preload/download behavior, force-quit/relaunch persistence, reboot persistence, offline transcription after download, and realistic corrupt/remove-model recovery remain Human-owned gates deferred to OBJ-04/OBJ-20 per PRD §17 and the Human Reviewer decision on 2026-06-18.
- Verdict: PASS for agent-verifiable OBJ-04 scope (defects: none found in agent-verifiable scope). Human Reviewer accepted this objective as complete with the listed device checks deferred to the documented Human-owned gates.

## OBJ-05 — Microphone Abstraction & Selection Backend — 2026-06-18
- Tier: agent-verifiable backend validation accepted complete; real-device microphone routing/enumeration deferred to Human-owned gates.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: 65 passed / 65 total using `-only-testing:TranscriberTests`; new tests: `MicrophoneSelectionTests.defaultSelectionIsAutomatic()`, `selectedMicrophonePersistsInDefaults()`, `choicesPutAutomaticFirstAndRepresentInputKinds()`, `selectionResolutionReturnsKnownInputAndFallsBackForAutomaticOrUnknown()`, and `routeResolutionKeepsAutomaticAndUnknownIDsOnDefaultPath()`.
- Manual UI: not run on a simulator/device. Code review verifies Settings now includes a basic Microphone picker with Automatic first and platform-discovered inputs after refresh; no Test Mic UI, live meter, active-mic display, Dashboard, or navigation work was added.
- Failure injection: unit fixtures simulate missing selection, Automatic selection, known selected input, and unknown saved input. Unknown ids resolve to fallback/default, and recorder startup does not throw if preferred-input routing fails.
- Auditor: ALIGNED. Auditor verified OBJ-05 scope, no OBJ-06/OBJ-07/OBJ-08 work, no navigation/Dashboard work, no `Recording` schema change, no dependency bump, no strict-concurrency weakening, touched paths limited to the active native app/tests plus this evidence, and no audio capture/format/file-writing changes beyond the guarded microphone preference hook.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio deletion, transcript deletion, Dashboard, navigation, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates deferred: real iPhone microphone enumeration, Bluetooth/headset enumeration, selected-microphone hardware routing, recording with Automatic on device, and recording with an explicit selected device remain Human-owned gates deferred to OBJ-05/OBJ-08/OBJ-20 validation per PRD §17 and the Human Reviewer decision on 2026-06-18. Agent validation proves the backend resolution/persistence/fallback behavior but does not prove physical microphone routing.
- Verdict: PASS for agent-verifiable OBJ-05 backend scope (defects: none found in agent-verifiable scope). Human Reviewer accepted this objective as complete with the listed device checks deferred to the documented Human-owned gates.

## OBJ-06 — Test Mic + Live Input Meter — 2026-06-18
- Tier: agent-verifiable validation accepted complete; real-device mic-level responsiveness remains a Human-owned gate.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: 72 passed / 72 total using `-only-testing:TranscriberTests`; new tests: `MicrophoneTestSessionTests.normalizedRMSClampsToMeterRange()`, `startAndStopDriveMeteringStateWithoutRecordingURL()`, `deniedPermissionFailsWithoutStartingCapture()`, `stopDuringPendingStartPreventsLateCapture()`, and `startFailureStopsPartialCaptureAndReturnsToFailedState()`.
- Manual UI: not run on a simulator/device. Code review verifies Settings now has an inline Test Mic control, selected-input label, live level meter, Start/Stop state, failure text, stop-on-Settings-disappear, and stop-on-input-change behavior.
- Failure injection: unit fakes simulate denied microphone permission, stop while permission/start is pending, and capture-start failure. These cases avoid recording persistence; pending-start stop prevents late capture, and start failure calls stop to tear down partial capture.
- Auditor: ALIGNED. Auditor verified OBJ-06 scope, no OBJ-07 fallback notice or active-mic display, no OBJ-08 reliability work, no Dashboard/navigation work, no `Recording` schema change, no dependency bump, no strict-concurrency weakening, and touched paths limited to the active native app/tests plus this evidence.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio deletion, transcript deletion, Dashboard, navigation, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates deferred: real iPhone validation remains Human-owned: Start Test Mic prompts/opens the selected microphone, the live meter responds to real input, Stop releases capture cleanly, leaving Settings releases capture cleanly, and a normal recording still starts afterward. This does not include OBJ-07 fallback notice/active-mic display or OBJ-08 background/lock/30-minute reliability, and remains deferred to OBJ-06/OBJ-08/OBJ-20 device gates per the Human Reviewer decision on 2026-06-18.
- Verdict: PASS for agent-verifiable OBJ-06 scope (defects: none found in agent-verifiable scope). Human Reviewer accepted this objective as complete with the listed real iPhone checks deferred to the documented Human-owned gates.

## OBJ-07 — Mic Fallback, Active-Mic Display & Notice — 2026-06-18
- Tier: agent-verifiable validation passed and accepted complete; real-device microphone fallback remains a Human-owned gate.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: 75 passed / 75 total using `-only-testing:TranscriberTests`; new tests: `MicrophoneSelectionTests.recordingRouteUsesSelectedInputWhenPresent()`, `recordingRouteFallsBackToBestAvailableInputWhenSelectedIsMissing()`, and `recordingRouteUsesSystemDefaultWhenAutomaticOrNoInputsAvailable()`.
- Follow-up validation after clarifying selected-input vs active-input route state: macOS build PASS / iOS-sim build PASS / `TranscriberTests` PASS (75/75).
- Manual UI: not run on a simulator/device. Code review verifies `RecordingView` now shows the active microphone in the recording status header and displays a non-intrusive fallback notice only when the recording route reports fallback.
- Failure injection: unit fixtures simulate a selected input present, a selected input missing with a best-available fallback input, and a selected input missing with no available inputs. The missing-selection paths still resolve to a recording route instead of throwing or blocking startup.
- Auditor: ALIGNED. Auditor verified OBJ-07 scope, no OBJ-08 background/lock/30-minute reliability work, no Dashboard/navigation work, no unrelated Settings UI, no model lifecycle/preflight changes, no `Recording` schema change, no dependency bump, no strict-concurrency weakening, and touched paths limited to the active native app/tests plus this evidence.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio deletion, transcript deletion, Dashboard, navigation, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates deferred: real iPhone validation remains Human-owned: selected physical mic becoming unavailable still starts recording, the fallback input is actually used, the active-mic label is accurate, and the fallback notice appears. Real Bluetooth/headset drop behavior remains deferred to OBJ-08/OBJ-20 per `OBJECTIVE-07.md`.
- Verdict: PASS for agent-verifiable OBJ-07 scope (defects: none found in agent-verifiable scope). Human Reviewer accepted OBJ-07 as complete with the listed real iPhone checks deferred to the documented Human-owned device gates for OBJ-07/OBJ-08/OBJ-20.

## OBJ-08 — Background/Lock & 30-Minute Reliability Hardening — 2026-06-18
- Tier: agent-verifiable hardening passed; background/lock/long-duration proof remains a Human-owned iPhone device gate.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: 79 passed / 79 total using `-only-testing:TranscriberTests`; new tests: `RecordingReliabilityTests.interruptedRecordingCreatesRetryableLibraryRecordWithoutTranscriptData()`, `interruptionFailureMessageExplainsSavedRetryableAudio()`, `interruptionFailureMessageIncludesIncompleteFileWarningOnWriteError()`, and `unavailableSaveContextMessageDoesNotClaimLibraryPersistence()`.
- Manual UI: not run on a simulator/device. Code review verifies `UIBackgroundModes = audio` remains configured, Record startup now gives the session a save context for interruption recovery, route-change events refresh active microphone/fallback notice state, and interruption/media-service-reset events close capture through the recorder stop path.
- Failure injection: unit tests exercise the retryable interrupted-recording policy, saved-audio messaging, write-error/incomplete-file messaging, and the no-save-context fallback message. Real AVAudioSession interruptions, Bluetooth route drops, lock-screen capture, app switching, and 5/15/30-minute runs require the Human-owned iPhone checklist now recorded above.
- Auditor: ALIGNED. Auditor verified OBJ-08 scope against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, and `docs/planning/objectives/OBJECTIVE-08.md`; no Dashboard/navigation/Library-status work, no unrelated Settings polish, no `Recording` schema change, no dependency bump, no strict-concurrency weakening, no edits to `src/python/`, `src/legacy-ios/`, or `XCode App Build/`, and no removal of deliberate pipeline pauses.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, and unit-test bundle are green. No schema, dependency, audio deletion, transcript deletion, Dashboard, navigation, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates deferred: Human Reviewer must run the OBJ-08 iPhone checklist above before this objective can be called complete: OBJ-04 model preload/persistence/offline/corrupt-model checks; OBJ-05 real microphone enumeration/routing checks; OBJ-06 Test Mic behavior; OBJ-07 unavailable selected-mic fallback/active-label/notice checks; OBJ-08 background, lock-screen, app-switch, interruption, Bluetooth route-change, and 5/15/30-minute reliability checks.
- Verdict: PASS for agent-verifiable OBJ-08 hardening scope (defects: none found in agent-verifiable scope). Final gate remains ASK USER because real-device recording reliability is Human-owned per AGENTS.md and OBJECTIVE-08.md.

## OBJ-08 — Human Reviewer Findings / Backlog From Device Testing — 2026-06-19
- Source: Human Reviewer notes from OBJ-08 iPhone device/model testing. No exported Model Lab evidence file was found in the repo during triage; the performance figures below are recorded from the Human Reviewer summary.
- Gate recommendation from triage: FIX FIRST. The AirPods/microphone enumeration issue requires force quit after a real route change and directly affects OBJ-08 route-change reliability plus OBJ-05/OBJ-07 microphone acceptance. Do not advance OBJ-08 until that behavior is fixed or explicitly reclassified by the Human Reviewer.
- Scope boundary: no code fixes, PLAN.md changes, OBJECTIVE.md changes, DECISIONS.md changes, or OBJ-09 advancement were made in this triage pass.

| Finding | Classification | Triage notes |
| --- | --- | --- |
| Need a cancel button for all model downloads in case a large model is clicked accidentally. | new backlog item | Not an OBJ-08 recording-reliability blocker. Best handled as model-management follow-up tied to download UX/cancel behavior. |
| Need known model sizes before download; "size not reported yet" is not acceptable. | product decision needed | PRD requires clear size/progress when known, and OBJ-03 allowed static size tables if framework metadata is unavailable. Human Reviewer should decide whether static curated sizes are required. |
| AirPods are not shown as a microphone option after connecting unless the app is force quit. | OBJ-08 blocker | Real device route/input enumeration is not refreshing after a Bluetooth route change. This conflicts with OBJ-08 route-change reliability and OBJ-05/OBJ-07 real microphone behavior. |
| Model Lab should be on the bottom bar with Record, Library, and Settings. | already planned in a later objective | Covered by the Model Lab top-level tab work in the roadmap; also related to the existing tab/dashboard ordering decision. |
| Switching the final transcriber model does not update on the Record screen until Record is pressed. | new backlog item | Status synchronization issue for the Record screen. Not a recording-reliability blocker unless it causes the wrong model to be used. |
| Tap the model on the Record screen to switch models. | product decision needed | This is a new interaction request and should be accepted or rejected deliberately before implementation. |
| Hard to identify speakers on a 5-second clip. | model-quality limitation / needs benchmark evidence | Short clips may be weak diarization inputs. Needs benchmark evidence before treating as a code defect. |
| Need a progress bar to load the final transcript model. | already planned in a later objective | Fits the roadmap's progress/status work for processing/model phases. |
| Need a button to load the final transcript model before recording starts. | new backlog item | Model-preload control request; useful, but outside OBJ-08 unless model loading blocks normal recording startup. |
| Final transcript model loading should be independent of recording start; user should be able to hit Record while loading continues. | new backlog item | Important model-preload behavior to preserve normal recording startup, but no evidence here that startup is currently blocked. |
| Speaker labels do not appear to work. | should be fixed before advancing | Not strictly an OBJ-08 recording-capture bug, but it affects the real-device record-to-transcript-to-label acceptance flow. Needs reproduction and a scoped fix or explicit defer before advancing. |
| When speaker labels fail, the UI remains stuck on "Identifying speakers" instead of clearing/resetting progress. | should be fixed before advancing | Clear UI state bug in failure handling. Likely belongs to speaker-label/progress objectives, but should not be left as an ambiguous in-progress state in acceptance testing. |
| Need a cancel button in Model Lab. | already planned in a later objective | Fits Model Lab diagnostics/cancellation hardening rather than OBJ-08 recording reliability. |
| Speaker labels are currently very poor quality. | model-quality limitation / needs benchmark evidence | Record as diarization quality evidence; do not assume it is fixed by changing transcription models alone. |
| Transcription takes a long time, even with basic models. | model-quality limitation / needs benchmark evidence | Performance needs benchmark comparison by model/device/audio length before picking a fix. |
| Model Lab comparison: Parakeet 110M Lightweight 10.3s / 8.9x realtime; Parakeet v2 English Accuracy 1.0s / 95.8x realtime; Base English Default 5.3s / 17.3x realtime; Small English Balanced 25.0s / 3.7x realtime. | model-quality limitation / needs benchmark evidence | Logged as Human Reviewer performance evidence. No matching exported artifact was found in the repo during triage. |

- Minimal roadmap proposal, not applied: keep OBJ-08 active with a FIX FIRST subtask for Bluetooth/AirPods route/input refresh; add a model-management follow-up for download cancellation and known-size display before broader Model Lab polish; leave Model Lab bottom-tab placement with the already planned Model Lab tab objective unless the Human Reviewer wants to pull it forward.

## OBJ-08 — FIX FIRST Follow-Up: Bluetooth Route/Input Refresh — 2026-06-19
- Scope: fixed only the AirPods/Bluetooth microphone enumeration blocker accepted by the Human Reviewer. No OBJ-09 work, roadmap advancement, Model Lab bottom-tab work, model-download cancel/size work, final-model preload work, speaker-label quality work, dependency changes, SwiftData schema changes, or prohibited-path edits.
- Root cause: `MicrophoneService` refreshed the microphone list on Settings appear and recording start, while `AudioRecorder` handled route changes only during active capture. If AirPods connected while the app was already open, the shared microphone picker list could stay stale until force quit/relaunch.
- Fix summary: `MicrophoneService` now listens for iOS audio route-change notifications and refreshes the published input list immediately, then refreshes once more after a short delay so late-settling Bluetooth inputs can appear. `AudioRecorder` also reapplies the active/fallback recording route immediately and after the same short delay while recording.
- Tests added: `MicrophoneSelectionTests.routeChangeRefreshAddsNewBluetoothInputs()` and `routeChangeRefreshPreservesFallbackWhenSelectedInputDisappears()`.
- Validation: focused `MicrophoneSelectionTests` PASS; macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (81/81); `git diff --check` PASS.
- Device gate: real iPhone re-test is still required to prove AirPods/Bluetooth hardware enumeration refreshes without force quit and that active-mic/fallback labels remain accurate after actual route changes.
- Gate recommendation for this FIX FIRST follow-up: PROCEED for agent-verifiable code and tests; do not mark OBJ-08 complete or advance until the Human-owned iPhone retest confirms the Bluetooth/AirPods behavior.

## OBJ-08 — FIX FIRST Follow-Up: Test Mic Freeze After Bluetooth Refresh — 2026-06-19
- Human Reviewer retest: partial success. AirPods appeared in the microphone picker after connecting while the app was already open, confirming the runtime route/input refresh partially worked. New blocker: tapping Test Mic after AirPods appeared froze the app.
- Scope: fixed only the Test Mic freeze/hang risk after Bluetooth route refresh. No OBJ-09 work, roadmap advancement, Model Lab bottom-tab work, model-download cancel/size work, final-model preload work, speaker-label work, dependency changes, SwiftData schema changes, or prohibited-path edits.
- Root cause hypothesis from agent inspection: the prior delayed route refresh could overlap with Test Mic startup. Route-change refresh was also allowed to reconfigure the audio session while Test Mic/recording was opening the selected microphone, creating a real-device AVAudioSession/AVAudioEngine race after Bluetooth route changes.
- Fix summary: route-change refreshes are now read-only against the current audio session, recording/Test Mic startup cancels pending delayed route refresh work before opening capture, and the route observer no longer passes full `Notification` objects across the main-actor boundary.
- Tests added/updated: `MicrophoneSelectionTests.recordingRouteRefreshDoesNotReconfigureAudioSession()` and `MicrophoneTestSessionTests.startCancelsPendingRouteRefreshBeforeOpeningMicrophone()`; earlier Bluetooth add/remove refresh tests remain.
- Validation: focused `MicrophoneSelectionTests` + `MicrophoneTestSessionTests` PASS; macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (83/83); `git diff --check` PASS.
- Device gate: another real iPhone re-test is required to prove Test Mic no longer freezes after AirPods appear via runtime route refresh.
- Gate recommendation for this FIX FIRST follow-up: PROCEED for agent-verifiable code and tests; do not mark OBJ-08 complete or advance until the Human-owned iPhone retest confirms the AirPods Test Mic freeze is resolved.

## OBJ-08 — FIX FIRST Follow-Up: Bluetooth Availability and Test Mic Fallback — 2026-06-19
- Human Reviewer retest: partial success. AirPods appeared in the microphone picker after connecting while the app was already open, the app automatically switched to AirPods, switching away/back worked, and Test Mic no longer froze. Remaining blockers: Test Mic with AirPods selected showed "Cannot test mic", and AirPods still appeared in the microphone picker after AirPods were disconnected, the app was force quit, and the app was reopened without AirPods connected.
- Scope: fixed only the Bluetooth/AirPods microphone state issues inside OBJ-08. No OBJ-09 work, roadmap advancement, Model Lab work, model download work, final-model preload work, speaker-label work, dependency changes, SwiftData schema changes, or prohibited-path edits.
- Root cause from agent inspection: the available microphone list was not being persisted, but the Settings picker was bound directly to the persisted selected microphone ID. That allowed a saved AirPods ID to look selected even when the live platform input list no longer contained AirPods. Test Mic also treated selected-route open failure as a hard failure instead of retrying the same safe Automatic/system fallback path used by recording.
- Fix summary: microphone picker display now resolves the saved selection through the current live input list and shows Automatic when the saved input is unavailable; route refresh replaces the full input list instead of preserving stale entries; Test Mic now receives the route used by metering, retries with the system default input if the selected input cannot be opened, shows a fallback notice when that succeeds, and uses clearer non-blocking failure text if both selected and fallback startup fail.
- Tests added/updated: `MicrophoneSelectionTests.visibleSelectionUsesAutomaticWhenPersistedInputIsUnavailable()`, `routeRefreshReplacesDisconnectedBluetoothInputs()`, and `MicrophoneTestSessionTests.startShowsFallbackNoticeWhenSelectedInputFallsBack()`; existing Test Mic failure expectations were updated for the clearer fallback/unavailable message.
- Validation: focused `MicrophoneSelectionTests` + `MicrophoneTestSessionTests` PASS; macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (86/86); `git diff --check` PASS.
- Device gate: another real iPhone re-test is required to prove disconnected AirPods disappear after force quit/reopen, connected AirPods still appear during runtime route refresh, Test Mic either starts with AirPods or falls back cleanly without freezing, and normal recording still starts.
- Gate recommendation for this FIX FIRST follow-up: PROCEED for agent-verifiable code and tests; do not mark OBJ-08 complete or advance until the Human-owned iPhone retest confirms the Bluetooth/AirPods behavior.

## OBJ-08 — FIX FIRST Follow-Up: Bluetooth Reconnect Retry and Automatic Default — 2026-06-19
- Human Reviewer retest: progress. AirPods can be selected when connected, Test Mic runs without freezing, and Bluetooth disconnect removes AirPods from the available microphone list. Remaining blocker: after full Bluetooth disconnect, reconnect, and putting AirPods back in ears, the app does not register AirPods as available/viable until force quit/reopen. Product decision: Automatic is the default/effective selection unless the user explicitly chooses an available mic; unavailable selected mics must fall back to Automatic/system input instead of appearing active.
- Scope: fixed only runtime Bluetooth reconnect detection and Automatic/effective-selection behavior inside OBJ-08. No OBJ-09 work, roadmap advancement, Model Lab work, model download work, final-model preload work, speaker-label work, dependency changes, SwiftData schema changes, or prohibited-path edits.
- Root cause from agent inspection: the route-change observer handled all route changes, but it performed only one delayed refresh after 500 ms. A full AirPods Bluetooth reconnect can repopulate `AVAudioSession.availableInputs` later than that. Settings also only refreshed on appear, so foreground reactivation did not force a new platform input read. The persisted selected mic ID was already resolved through live inputs for display, so unavailable selections behaved as Automatic effectively; the missing part was robust late reconnect discovery.
- Fix summary: route changes now schedule a short retry sequence after the immediate read-only refresh; delayed retries can reconfigure/reactivate the audio session only when capture is not active, so Test Mic/recording startup remains protected from the previous AVAudioSession race. Settings refreshes microphone inputs again when the scene becomes active. AudioRecorder marks capture active/inactive so microphone refresh retries stay read-only during Test Mic and recording. Available inputs remain live platform state only; only the selected mic ID/preference is persisted.
- Tests added/updated: `MicrophoneSelectionTests.routeRefreshCanRemoveAndReAddBluetoothInputsWithoutRelaunch()`, `delayedRouteRefreshCanDiscoverLateBluetoothReconnect()`, and `delayedRouteRefreshDoesNotReconfigureAudioSessionDuringCapture()`; existing Automatic/default, unavailable selection, disconnected Bluetooth removal, Test Mic fallback, and capture-start race tests remain.
- Validation: focused `MicrophoneSelectionTests` + `MicrophoneTestSessionTests` PASS; macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (89/89); `git diff --check` PASS.
- Device gate: another real iPhone re-test is required to prove AirPods reappear after a full Bluetooth disconnect/reconnect cycle without force quit, Automatic remains the default/effective fallback when the selected mic is unavailable, Test Mic does not freeze, and normal recording still starts immediately.
- Gate recommendation for this FIX FIRST follow-up: PROCEED for agent-verifiable code and tests; do not mark OBJ-08 complete or advance until the Human-owned iPhone retest confirms the Bluetooth reconnect behavior.

## OBJ-08 — Final Human Reviewer PASS and Gate — 2026-06-19
- Human Reviewer iPhone retest result: PASS.
- Confirmed on iPhone: AirPods/Bluetooth microphone runtime refresh now works; AirPods appear when connected, disappear when disconnected, and reappear after Bluetooth disconnect/reconnect without force-quitting the app.
- Confirmed on iPhone: Test Mic works without freezing, normal recording still works, and the app defaults/effectively falls back to Automatic as intended.
- Agent-verifiable validation already green for the final follow-up: focused `MicrophoneSelectionTests` + `MicrophoneTestSessionTests` PASS; macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (89/89); `git diff --check` PASS.
- Manager gate decision: PROCEED. OBJ-08 Human-owned Bluetooth/AirPods route-change reliability gate is accepted by the Human Reviewer. Longer background/lock and 5/15/30-minute reliability checks remain documented in the device checklist for continued beta acceptance, but no OBJ-08 blocker remains from the current Human Reviewer retest.

## OBJ-09 — Library Status Badges + Canonical RecordingStatus — 2026-06-19
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. Both builds emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 93 passed / 93 total using `-only-testing:TranscriberTests`; focused `RecordingStatusTests` PASS. New tests: `derivesStatusTruthTableFromRecordingAndActivityState()`, `eachStatusHasBadgeCopyAndSymbol()`, `metadataHelpersFormatDurationModelAndSpeakerLabels()`, and `missingAudioReconciliationReportsRowsWithoutMutatingThem()`.
- Manual UI: not run on a simulator/device. Code review verifies Library rows now show title/date, duration, canonical status badge, final transcription model name, speaker-label status, and a missing-audio warning. Recording detail surfaces missing audio and disables audio-dependent actions while keeping the row/transcript visible.
- Failure injection: unit fixture simulates one present audio file and one missing audio file. Reconciliation reports the missing row by audio filename and does not mutate transcript segments, retry flags, or final-model metadata.
- Auditor: ALIGNED. Auditor verified OBJ-09 scope against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, and `docs/planning/objectives/OBJECTIVE-09.md`; status is derived with no `Recording` schema change, no stored status field, no dependency bump, no strict-concurrency weakening, no Dashboard/OBJ-10 implementation, and no edits to `src/python/`, `src/legacy-ios/`, or `XCode App Build/`.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, `TranscriberTests`, and `git diff --check` are green. Existing delete flow remains non-destructive on audio-delete failure; existing rename/retry tests remain green. No schema, dependency, audio deletion, transcript deletion, Dashboard, Model Lab tab, speaker reassignment, progress timeline, diagnostics, export hardening, accessibility, or Mac parity work was added.
- Device gates outstanding: none specific to OBJ-09. Real device visual review of the Library row is useful during ongoing beta acceptance, but this objective has no Human-owned hardware gate.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-10 — Dashboard Tab — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. Both builds emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 97 passed / 97 total using `-only-testing:TranscriberTests`; focused `DashboardTests` PASS. New tests: `recentAttentionFiltersAndSortsByRecordingStatus()`, `recentAttentionLimitIsAppliedAfterFilteringAndSorting()`, `modelWarningsCoverMissingDownloadingRepairingAndFailedStates()`, and `microphoneSummaryReportsUnavailableSavedInputWithoutInventingActiveHardware()`.
- Manual UI: not run on a simulator/device. Code review verifies the Dashboard is the first tab; Record, Library, and Settings remain top-level tabs; iOS Dashboard opens the existing nested Model Lab screen; macOS shows a disabled Model Lab action because the current Model Lab view is iOS-only. Dashboard Record/Import actions route into the existing `RecordingView` record/import flows.
- Failure injection: unit fixtures exercise complete vs non-complete `RecordingStatus` filtering, newest-first limiting, model warnings for missing/downloading/repairing/failed states, and unavailable saved microphone copy without inventing active hardware.
- Auditor: ALIGNED. Auditor verified OBJ-10 scope against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, and `docs/planning/objectives/OBJECTIVE-10.md`; Dashboard consumes OBJ-09 `RecordingStatus`, model status through `ModelRegistry`/`FinalModelDownloader`, and microphone selection through `MicrophoneService`; no Model Lab tab promotion, speaker reassignment, progress timeline, diagnostics, export, accessibility, Mac parity, cancellation hardening, `Recording` schema change, dependency bump, strict-concurrency weakening, or prohibited-path edits were added.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused `DashboardTests`, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: none specific to OBJ-10. Real iPhone visual/interaction review of the Dashboard is useful during beta acceptance, especially the direct Record/Import buttons and the existing Model Lab navigation, but no Human-owned hardware gate blocks OBJ-10.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-11 — Model Lab as Top-Level Tab + Diagnostics Columns — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. Both builds emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 101 passed / 101 total using `-only-testing:TranscriberTests`; focused `ModelLabTests` PASS. New tests: `iOSTabStructureMatchesPRDPrimaryTabs()`, `reportIncludesLoadAndTranscriptionTimeSeparately()`, `reportIncludesFailureStatusAndTranscriptPlaceholder()`, and `diagnosticsSnapshotUsesModelRegistryStatusAndSizeFormatting()`.
- Manual UI: not run on a simulator/device. Code review verifies iOS root tabs now align with PRD §6 as Dashboard, Library, Model Lab, Settings; Dashboard Record/Import opens the existing `RecordingView` flow; Dashboard's Model Lab action switches to the new tab; Settings still contains the secondary Model Lab link. macOS keeps Model Lab unavailable as before because Mac feasibility is OBJ-18.
- Failure injection: unit fixtures verify failed Model Lab report rows include failure status and error text, zero processing-time speed shows truthful placeholder copy, and registry-backed diagnostics use `ModelRegistry.status` plus `ModelRegistry.formattedSize`.
- Auditor: ALIGNED. Auditor verified OBJ-11 scope against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, and `docs/planning/objectives/OBJECTIVE-11.md`; Model Lab reads model size/status from OBJ-03 `ModelRegistry`, measures model load time separately from transcription/processing time, preserves sequential one-at-a-time execution and per-model unloads, keeps Settings access, and does not start OBJ-12 speaker reassignment, OBJ-13 state parity, OBJ-14 progress timeline, OBJ-15 diagnostics on normal screens, export hardening, accessibility, Mac parity, or cancellation hardening.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused `ModelLabTests`, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: none specific to OBJ-11. Real comparative model timings and memory behavior remain useful Human-owned beta measurements for Model Lab/OBJ-20, but no Human-owned hardware gate blocks OBJ-11.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-12 — Segment-Level Speaker Reassignment — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. Both builds completed successfully; the iOS simulator build emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`).
- Unit/integration tests: 107 passed / 107 total using `-only-testing:TranscriberTests`; focused reassignment/export tests PASS. New tests: `TranscriptSegmentReassignmentTests.reassigningSegmentUpdatesOnlySpeakerAttribution()`, `reassignmentPersistsThroughRecordingSegmentsBlob()`, `reassignmentSurvivesEncodeDecodeRoundTrip()`, `availableSpeakersPreservesFirstAppearanceOrder()`, `TranscriptExportTests.exportsReflectReassignedSpeakers()`, and `renamedSpeakerAndReassignedSegmentExportTogether()`.
- Manual UI: not run on a simulator/device. Code review verifies Library detail transcript cards now expose a calm per-segment ellipsis menu for changing the segment to an existing speaker; renamed speakers appear in the menu as custom name plus default speaker identity; other transcript surfaces keep display-only cards.
- Failure injection: unit fixtures verify reassignment changes only speaker attribution, not text/timing, and exports TXT/SRT/JSON reflect reassigned speakers. Save-failure handling is code-reviewed: reassignment saves through `modelContext.save()` and shows a `Storage Issue` alert if saving fails. No pre-existing failing `ModelContext` seam was available for automated save-failure injection.
- Auditor: ALIGNED. Auditor verified OBJ-12 scope against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, and `docs/planning/objectives/OBJECTIVE-12.md`; no transcript text editing, speaker merge/split workflow, SwiftData schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, or OBJ-13/OBJ-14/OBJ-15 work was added.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused reassignment/export tests, full `TranscriberTests`, and `git diff --check` are green. Existing rename and export display-name helpers remain the source of truth for renamed speaker output.
- Device gates outstanding: none specific to OBJ-12. A real-device visual tap-through of the new menu is useful during beta review, but no Human-owned hardware gate blocks this objective.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-13 — Consistent Speaker-Label States & Rename/Reassign Parity — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. The iOS simulator build emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`).
- Unit/integration tests: 111 passed / 111 total using `-only-testing:TranscriberTests`; focused OBJ-13 tests PASS. New tests: `SpeakerLabelStatusPresentationTests.sharedPresentationCoversRequiredSpeakerLabelStates()`, `recordingMetadataUsesSharedSpeakerLabelCompactText()`, `editAvailabilityRequiresPersistedEditableTranscriptSegments()`, and `DiarizationFallbackTests.retrySpeakerLabelsUsesStoredRawTranscriptionWithoutReplacingTranscriptText()`.
- Manual UI: not run on a simulator/device. Code review verifies `RecordingView`, `RecordingDetailView`, `SharedAudioDetailView`, Library row metadata, and Dashboard speaker-label summaries now consume the shared `SpeakerLabelStatusPresentation` / `SpeakerLabelStatusView` instead of per-screen speaker-label copy. Completed Recording and Shared Audio surfaces link to the saved Library detail record for speaker rename and segment reassignment, reusing the OBJ-12 persistence path.
- Failure injection: unit fixtures cover approximate, failed, canceled, retryable, active/identifying, and complete speaker-label presentation states. Retry-label regression uses stored `rawTranscription` with a fake diarization engine and verifies transcript text is preserved while only speaker attribution changes.
- Auditor: ALIGNED. Auditor verified shared status logic is centralized, OBJ-12 reassignment/export behavior remains green, retry speaker labels does not rerun transcription, no diarization algorithm change was made, no transcript text editing or speaker merge/split workflow was added, no SwiftData schema/dependency/project-setting/prohibited-path changes were made, and OBJ-14/OBJ-15+ work was not started.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused OBJ-13 tests, focused reassignment/export/status/Dashboard tests, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: none specific to OBJ-13. A real-device visual tap-through of the shared status cards, retry button, and Edit Speakers navigation is useful during beta review, but no Human-owned hardware gate blocks this objective.
- Verdict: PASS. Manager gate recommendation: PROCEED. PLAN.md and OBJECTIVE.md advancement are intentionally deferred until Human Reviewer review so OBJ-14 is not started in this pass.

## OBJ-14 — Phase-Timeline Progress UI — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. The iOS simulator build emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`).
- Unit/integration tests: 118 passed / 118 total using `-only-testing:TranscriberTests`; focused `ProcessingPhaseTests` PASS. New tests: `processingPhaseCoversPRDCorePhases()`, `legacyProcessingMessagesMapToStructuredPhases()`, `phaseDisplayCopyStaysHumanReadable()`, `elapsedTimeFormattingCoversMinutesAndHours()`, `progressPresentationClampsPercentAndFallsBackToActivity()`, `cancelAndRetryAffordanceVisibilityIsExplicit()`, and `transcriptionSessionProcessingStateCarriesPhase()`.
- Manual UI: not run on a simulator/device. Code review verifies `RecordingView`, `RecordingDetailView`, and `SharedAudioDetailView` now use the shared phase-timeline progress presentation with current phase, rough percent/activity, elapsed time, Cancel where the existing session supports cancellation, and a minimal Details disclosure.
- Failure injection: existing retry/cancel/data-safety regression tests remain green, including `DiarizationFallbackTests.retrySpeakerLabelsUsesStoredRawTranscriptionWithoutReplacingTranscriptText()`, which verifies speaker-label retry preserves transcript text and does not rerun transcription.
- Auditor: ALIGNED. Auditor verified the phase model maps to PRD §13 core phases, the shared progress UI is reused across required surfaces, Cancel/Retry wiring uses existing session paths, no OBJ-15 diagnostics capture was added, and no algorithm, schema, dependency, project-setting, strict-concurrency, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes were made.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused phase tests, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, diagnostics capture, export hardening, accessibility, Mac parity, cancellation hardening, or OBJ-15+ work was added.
- Device gates outstanding: none specific to OBJ-14. A real-device visual tap-through of the progress timeline and Cancel control during live processing is useful during beta review, but no Human-owned hardware gate blocks this objective.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-15 — Diagnostics on Normal Screens + Diagnostics Data Model — 2026-06-20
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. Both builds emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 121 passed / 121 total using `-only-testing:TranscriberTests`; focused diagnostics/fallback/Model Lab/phase tests PASS. New tests: `ProcessingDiagnosticsTests.formattingCoversLoadTranscriptionAndRealtimeSpeed()`, `presentationIncludesRequiredDiagnosticRowsAndStaysCollapsedByDefault()`, and `RecordingDiagnosticsTests.recordingSummaryUsesDerivedFieldsWithoutInventingTimings()`. Updated diarization fallback tests verify diagnostics fallback/status flags, and Model Lab tests verify shared "Not measured" speed copy.
- Manual UI: not run on a simulator/device. Code review verifies OBJ-14 Details disclosure now receives the latest diagnostics when available; Recording, Shared Audio, and Library detail transcript surfaces show a collapsed Diagnostics disclosure. Normal detail screens keep stable derived diagnostics for saved recordings and current-session measured timings when available; no separate diagnostics tab/screen was added.
- Failure injection: existing fake diarization engines verify primary success, fallback-to-fast success, and both-attempts-fail paths update diagnostics. Failure diagnostics reuse existing safe user-facing failure/cancellation text. No real model timing benchmark was run; absolute timing accuracy remains a Human/OBJ-20 device measurement.
- Auditor: ALIGNED. Auditor verified model preparation time, transcription time, audio duration, realtime speed, diarization time, fallback flags, speaker-label status, and failure message are captured only from real processing boundaries where claimed; UI remains collapsed/secondary; diagnostics are session/latest-only with derived saved-recording summaries; no SwiftData schema change, DECISIONS.md migration entry, dependency bump, algorithm/model-selection behavior change, export hardening, accessibility, Mac parity, cancellation-hardening objective work, strict-concurrency weakening, or prohibited-path edit was introduced.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused diagnostics/fallback/Model Lab/phase tests, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: none blocking OBJ-15. Real-device visual review of the collapsed diagnostics disclosure and real pipeline timing plausibility is useful during beta/OBJ-20 acceptance; absolute performance/timing accuracy remains Human-owned.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-16 — Export Hardening — 2026-06-21
- Tier: agent-verifiable
- Build: macOS PASS / iOS-sim PASS. The iOS simulator build emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 126 passed / 126 total using `-only-testing:TranscriberTests`; focused `TranscriptExportTests` + `SharedAudioInboxTests` PASS. New/updated tests: `TranscriptExportTests.jsonExportProducesCodableSegmentArrayWithCompatibleShape()`, `renamedSpeakersExportInEveryFormat()`, `subtitlesExportFormatsMillisecondsAndHours()`, `subtitlesExportKeepsSequentialNumbersAndTimestampSyntax()`, `SharedAudioInboxTests.isAudioFileFiltersSupportedExtensionsAndRejectsOddFormats()`, and `isAudioFileHandlesLargePlaceholderWithoutInspectingContents()`.
- Manual UI: not run on a simulator/device. Code review verifies the existing share/export call sites still use `TranscriptExporter.exportFile(...)` with the selected TXT/SRT/JSON format and existing share UI; no share-sheet redesign or new export format was added.
- Failure/import sanity: unit fixtures verify supported audio extensions are accepted case-insensitively, odd/non-audio paths are rejected by the extension filter, and a 12 MB placeholder `.m4a` can be classified without reading or parsing contents. This is an import filter sanity check, not broad codec validation.
- Auditor: ALIGNED. Auditor verified `TranscriptExporter` JSON segment construction now uses `TranscriptExporter.ExportedSegment: Codable` plus `JSONEncoder`, no `JSONSerialization`/`[String: Any]` remains in the exporter, JSON remains an array of objects with `start`, `end`, `speaker`, and `text`, speaker display names flow through the existing helper in TXT/SRT/JSON, OBJ-12 reassigned and renamed speakers are covered, and no new formats, share UI redesign, schema change, dependency bump, strict-concurrency weakening, prohibited-path edit, or OBJ-17+ work was introduced.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, strict-concurrency build, focused export/import tests, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: none specific to OBJ-16. A real-device share-sheet tap-through for TXT/SRT/JSON is useful during beta acceptance, but no Human-owned hardware gate blocks this objective.
- Verdict: PASS. Manager gate recommendation: PROCEED.

## OBJ-17 — Accessibility Pass — 2026-06-21
- Tier: agent-verifiable fixes complete; Human light VoiceOver/device sanity pass still requested by `OBJECTIVE-17.md`.
- Build: macOS PASS / iOS-sim PASS. The iOS simulator build emitted the existing AppIntents metadata extraction warning (`No AppIntents.framework dependency found`) and completed successfully.
- Unit/integration tests: 129 passed / 129 total using `-only-testing:TranscriberTests`; focused `TranscriptSegmentReassignmentTests` + `ProcessingPhaseTests` PASS before the full bundle. New tests: `TranscriptSegmentReassignmentTests.transcriptAccessibilityLabelReadsSpeakerTimeTextAndEditState()`, `speakerCueAddsNonColorSpeakerIdentity()`, and `ProcessingPhaseTests.progressAccessibilityValueIncludesPhaseProgressElapsedAndDetail()`.
- Manual UI: agent code review verifies Dynamic Type-friendly wrapping via `ViewThatFits` on primary action/control rows, removal of the Library metadata single-line limit, coherent VoiceOver labels/values on Dashboard cards, recording status, transcript cards, progress timeline, speaker-label cards, Model Lab controls/results, Settings microphone/model rows, and share/export controls. Simulator Accessibility Inspector / real VoiceOver audio pass was not performed by the agent.
- Accessibility fixes: primary button foreground changed from black to white; recording status now uses icon plus text instead of a color-only dot; transcript speaker cards include a speaker cue pill plus name and a coherent VoiceOver label; status/model/microphone/progress cards expose plain-language accessibility values; small ellipsis speaker reassignment control now has a 44-point hit area and explicit label/hint.
- Auditor: ALIGNED. Auditor verified changes are presentation-only, no transcription/diarization/model/export/persistence behavior changes, no app redesign, no `Recording` schema change, no dependency bump, `SWIFT_STRICT_CONCURRENCY = complete` unchanged, no prohibited-path edits, no OBJ-18/OBJ-19/OBJ-20 work, and non-color speaker/status cues were added where addressed.
- Regression checklist: PASS for scoped regression: macOS build, iOS-simulator build, focused accessibility-copy tests, full `TranscriberTests`, and `git diff --check` are green. No schema, dependency, audio deletion, transcript deletion, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.
- Device gates outstanding: Human Reviewer should do a light real-device VoiceOver/Dynamic Type sanity pass on Dashboard, Record/Stop/Cancel, Library detail transcript cards, speaker rename/reassign, Model Lab, Settings microphone/model rows, and Share/export menus.
- Verdict: PASS for agent-verifiable OBJ-17 scope. Manager gate recommendation: ASK USER until the Human VoiceOver/device sanity pass is accepted; do not advance `OBJECTIVE.md` to OBJ-18 yet.

## OBJ-17 — Human Reviewer FIX FIRST: Transcript Detail Large Text Layout — 2026-06-21
- Source: Human Reviewer accessibility/device visual pass after the first OBJ-17 agent build.
- Result: Mostly PASS, but transcript detail reading remains uncomfortable at larger text sizes.
- Finding 1: speaker-label status card and Diagnostics row need to scroll with transcript content instead of staying fixed above it.
- Finding 2: bottom action area takes too much vertical space when Play, Rename Speakers, Share, and New/new-recording actions stack vertically.
- Finding 3: at large text sizes, transcript content should get priority; status/actions must remain available but should not dominate the screen.
- Required follow-up: move status/Diagnostics into scrollable transcript content, make the bottom action area compact, preserve safe-area behavior and all existing actions, keep icon-only controls accessible if used, and avoid unrelated backlog/model/transcription behavior.
- Gate recommendation: FIX FIRST. Do not advance OBJ-17 until this targeted layout/accessibility follow-up is fixed and validated.

## OBJ-17 — FIX FIRST Follow-Up: Transcript Detail Large Text Layout — 2026-06-21
- Tier: agent-verifiable fix complete; Human should re-check the one transcript detail screen at large Dynamic Type.
- Fix summary: Recording, Shared Audio, and Library transcript detail surfaces now put the speaker-label status card, speaker-label processing timeline, and Diagnostics disclosure inside the same scrollable transcript content as the transcript cards, so those rows scroll away instead of staying fixed above the transcript.
- Compact action area: completed transcript actions now use a horizontal compact action bar with 44-point icon targets for Edit/Rename Speakers, Share, Play/Pause, and New Recording where those actions exist. The bar remains visible but no longer falls back into a tall vertical stack that squeezes transcript reading.
- Accessibility: icon-only compact actions use `CompactTranscriptAction` labels, hints, and SF Symbols; the share menu uses the same compact labels/hints when icon-only. Added focused test `TranscriptSegmentReassignmentTests.compactTranscriptActionsHaveAccessibleLabelsHintsAndIcons()`.
- Scope check: no transcription, diarization, model, export format, persistence, retry, schema, dependency, strict-concurrency, OBJ-18, OBJ-19, or OBJ-20 behavior was changed. The future backlog item for changing transcription model and rerunning transcription from the transcript page was not implemented.
- Validation: focused compact-action accessibility test PASS; macOS build PASS; iOS simulator build PASS on available `iPhone 17, iOS 26.5` simulator after the documented `iPhone 16` simulator was unavailable; full `TranscriberTests` PASS (130/130); `git diff --check` PASS.
- Auditor: ALIGNED. Auditor verified the follow-up is layout/accessibility-only, compact/icon actions have labels and hints, status/Diagnostics scroll with transcript content, all existing actions remain available, and prohibited paths/dependencies/project settings were not touched.
- Device gates outstanding: Human Reviewer should re-check Library/Recording transcript detail at large text sizes to confirm the transcript now gets priority and the compact action bar feels comfortable above the tab bar.
- Verdict: PASS for agent-verifiable follow-up. Manager gate recommendation: ASK USER for the one-screen Human visual re-check before advancing OBJ-17.

## OBJ-17 — Human Reviewer FIX FIRST: Transcript Detail Action Bar Legibility — 2026-06-21
- Source: Human Reviewer transcript detail visual recheck after the first layout follow-up.
- Result: Still not passing.
- Finding 1: bottom action icons are too small and need to be larger/easier to visually understand and tap.
- Finding 2: bottom action bar disappears while transcription is running and while speaker labels are being applied.
- Required follow-up: make the compact bottom actions more legible without returning to a tall stacked layout; preserve at least 44-point tap targets; keep controls usable at large Dynamic Type; provide a compact processing action bar with Cancel when Play/Rename/Share/New are not appropriate; restore the completed transcript action bar after processing finishes.
- Gate recommendation: FIX FIRST. Do not advance OBJ-17 until this targeted action-bar follow-up is fixed, validated, installed, launched, and rechecked by the Human Reviewer.

## OBJ-17 — FIX FIRST Follow-Up: Transcript Detail Action Bar Legibility — 2026-06-21
- Tier: agent-verifiable fix complete; Human should re-check the one transcript detail/action-bar screen on iPhone.
- Fix summary: compact transcript actions now use larger visible SF Symbols plus short visual labels (`Edit`, `Rename`, `Share`, `New`, `Play`, `Pause`, `Cancel`) in a still-horizontal action bar. Tap targets remain at least 44 points, with the visual target increased beyond the prior 44x44 icon-only buttons.
- Processing controls: Recording, Shared Audio, and Library retry processing now show a compact processing action bar with a red Cancel control when transcription/speaker-label processing is active. Completed transcript actions return after processing completes. Existing processing timelines still keep their own Cancel affordance.
- Accessibility: compact actions still use explicit labels/hints/traits through `CompactTranscriptAction`; the focused test now covers visible compact titles and the new `cancelProcessing` action.
- Scope check: no transcription, diarization, model, export format, persistence, retry, save, schema, dependency, signing, bundle ID, team, entitlements, deployment target, project structure, OBJ-18, OBJ-19, or OBJ-20 behavior was changed. The future model-change/rerun backlog item was not implemented.
- Validation: focused compact-action accessibility test PASS; macOS build PASS; iOS simulator build PASS on available `iPhone 17, iOS 26.5` simulator; full `TranscriberTests` PASS (130/130); `git diff --check` PASS.
- Device detection: `xcrun xctrace list devices` listed `iPhone 14 Pro (26.5.1)` with device id `00008150-000909261440401C` under offline devices, while `xcodebuild -showdestinations` listed the same phone as an available iOS destination. `xcrun devicectl list devices` showed `iPhone 14 Pro` connected with identifier `F8EA1DB6-2D3A-53EE-A3D9-80A6FE2CB204`.
- Install/run: physical-device build PASS using existing project/scheme/signing settings. Installed `com.daniel.transcriber2.beta` to the connected iPhone with `devicectl`; launched `com.daniel.transcriber2.beta` successfully.
- Auditor: ALIGNED. Auditor verified the follow-up is layout/accessibility-only, compact/icon actions retain labels and hints, Cancel remains reachable during processing, completed actions remain available after processing, and prohibited settings/paths/dependencies were not changed.
- Device gates outstanding: Human Reviewer should re-check transcript detail at large text sizes, including completed state and speaker-labeling/transcribing state, to confirm the larger action bar is readable and Cancel remains obvious.
- Verdict: PASS for agent-verifiable follow-up. Manager gate recommendation: ASK USER for the one-screen Human visual re-check before advancing OBJ-17.

## OBJ-17 — Human Reviewer FIX FIRST: Transcript Detail Play Button Regression — 2026-06-22
- Source: Human Reviewer transcript detail/action-bar recheck on the installed iPhone build.
- Result: Still not passing.
- Finding 1: Play in the completed transcript action bar does nothing. Because OBJ-17 changed the completed transcript action bar, this is a blocking regression for OBJ-17.
- Finding 2: during transcription/speaker-labeling only Cancel shows. This may be acceptable if processing is active and completed actions are intentionally unavailable; verify Cancel is clear, reachable, and accessible.
- Finding 3: speaker labeling/diarization can appear to hang or take longer than expected even on a short recording. A second short single-speaker recording eventually completed but still felt slow. This is device-observed and outside OBJ-17 unless caused by the accessibility/layout change; do not change the diarization algorithm here.
- Finding 4: it is not obvious that the user can swipe down from the transcription screen to get back to Dashboard. Log as a UX follow-up unless a small OBJ-17-safe accessibility fix is identified.
- Finding 5: Human Reviewer is not confident background/closed recording is still active because iOS does not show an obvious Dynamic Island or status-area recording indicator. Log as a background-recording/device-acceptance concern for later OBJ-20 or follow-up to OBJ-08; do not change background recording behavior in OBJ-17.
- Required follow-up: restore Play/Pause behavior in the completed transcript action bar, preserve the compact larger-icon bar, preserve accessibility labels/hints, preserve status/diagnostics scrolling, preserve Cancel during processing, and avoid unrelated backlog work.
- Gate recommendation: FIX FIRST until Play/Pause is fixed, validated, installed, launched, and rechecked by the Human Reviewer.

## OBJ-17 — FIX FIRST Follow-Up: Transcript Detail Play Button Regression — 2026-06-22
- Tier: agent-verifiable fix complete; Human should re-check Play/Pause on the installed iPhone build.
- Fix summary: saved-recording transcript detail now uses the existing `AudioPlaybackController` for the compact Play/Pause action, matching the shared-audio playback path that activates the iOS playback audio session and publishes play state for the visible Play/Pause label.
- Processing controls: the Cancel-only compact action bar during transcription/speaker-labeling is intentional for OBJ-17. Completed actions remain hidden while processing is active because Play/Rename/Share/New are not safe or meaningful until the current processing step finishes; Cancel remains visible, reachable, and labeled through `CompactTranscriptAction.cancelProcessing`.
- Device-observed backlog notes: speaker-labeling/diarization duration or apparent hanging remains logged for later investigation because OBJ-17 did not alter the diarization algorithm; swipe-down return-to-Dashboard discoverability is logged as a UX follow-up; background/closed recording indicator confidence remains a Human/device acceptance concern for OBJ-20 or an OBJ-08 follow-up. None of these backlog items were implemented in this pass.
- Accessibility/layout preservation: compact larger-icon action bar, labels/hints/traits, status/Diagnostics scrolling with transcript content, and Cancel visibility during processing were preserved.
- Validation: macOS build PASS; iOS simulator build PASS with the existing AppIntents metadata warning; focused compact-action accessibility test PASS; full `TranscriberTests` PASS (130/130); `git diff --check` PASS.
- Device detection: `xcrun devicectl list devices` showed the connected iPhone available with identifier `F8EA1DB6-2D3A-53EE-A3D9-80A6FE2CB204`; `xcodebuild -showdestinations` listed physical destination `00008150-000909261440401C`.
- Install/run: physical-device build PASS using existing project/scheme/signing settings. Installed `com.daniel.transcriber2.beta` to the connected iPhone with `devicectl`; first launch attempt was denied because the device was locked; after retry, launch succeeded.
- Auditor: ALIGNED. Auditor verified the Play/Pause restoration is limited to the transcript detail playback regression, compact action accessibility remains present, and no transcription, diarization, model, export, persistence, retry, save, signing, background-recording, Dynamic Island, navigation redesign, dependency, project-structure, or OBJ-18+ behavior was changed.
- Device gates outstanding: Human Reviewer should re-check this one screen on iPhone: completed transcript Play/Pause, compact action bar legibility, and Cancel visibility during processing.
- Verdict: PASS for agent-verifiable follow-up. Manager gate recommendation: ASK USER for the targeted Human playback/action-bar recheck before advancing OBJ-17.

## OBJ-17 — Human Reviewer FIX FIRST: Functional Playback/Live Preview/Speaker Labels Recheck — 2026-06-22
- Source: Human Reviewer recheck on the installed iPhone build after the first Play/Pause follow-up.
- Result: Still not passing. Human Reviewer asked to stop layout polishing and classify functional behavior before OBJ-17 can pass.
- Finding 1: Play gives only about half a second of playback, then stops or does not do anything useful.
- Clarification: Play was not previously tested by the Human Reviewer before OBJ-17, so this is known broken now but is not proven to be a regression from OBJ-17.
- Finding 2: live preview crashed again.
- Finding 3: speaker labels did not work or appeared stuck.
- Finding 4: the transcript/detail screen still wastes vertical space with the large `Transcriber 2.0` header. This is secondary until functional issues are resolved or safely classified.
- Required follow-up: determine whether OBJ-17 action-bar/layout/accessibility changes caused or worsened Play/Pause, live preview crashes, or speaker-label stuck behavior; fix any OBJ-17-caused regression; otherwise document the device findings and defer broader stabilization outside OBJ-17.
- Gate recommendation: FIX FIRST until the functional behavior is fixed or clearly classified for a Human Reviewer decision.

## OBJ-17 — FIX FIRST Follow-Up: Functional Playback Triage — 2026-06-22
- Tier: agent-verifiable playback fix attempt complete; Human should re-check playback and the noted device behaviors on iPhone.
- Playback investigation: OBJ-17 did touch the saved-recording playback UI path by moving completed transcript actions into the compact action bar and routing the button through `AudioPlaybackController`. Because this was the only OBJ-17-touched functional path related to the Human finding, playback was treated as an in-scope follow-up.
- Playback fix attempt: `AudioPlaybackController` now uses a retained `AVPlayer`/`AVPlayerItem`, activates the iOS playback audio session before playback, observes end-of-file to reset the visible Play/Pause state, and keeps the compact action bar wiring intact. This preserves the existing Play/Pause action while avoiding a short-lived local player path.
- Live preview investigation: OBJ-17 did not change `TranscriptionSession`, `AudioRecorder`, transcription engines, live-preview engine behavior, retry/session-state logic, persistence, or audio save paths. The live preview crash is logged as a Human/device functional finding outside the accessibility/layout scope unless later evidence connects it to OBJ-17.
- Speaker-label investigation: OBJ-17 did not change `DiarizationEngine`, model loading/selection, session retry behavior, or transcript persistence. Focused diarization fallback tests passed, including watchdog/fallback coverage and retrying speaker labels from stored raw transcription. Speaker-label stuck/failure is logged as a Human/device functional finding outside OBJ-17 unless later evidence connects it to OBJ-17.
- Header layout: deferred. The large transcript/detail header remains a known layout issue, but it was not changed in this pass because functional playback and device stability need Human confirmation first.
- Processing controls: Cancel-only controls during active transcription/speaker-labeling remain intentional and accessible. Completed actions remain unavailable while processing is active; Cancel remains the clear reachable action.
- Scope check: no transcription, diarization, model, export, retry, save, persistence, signing, background-recording, Dynamic Island, model-change/rerun, delete-downloaded-models, navigation redesign, dependency, project-structure, OBJ-18, OBJ-19, or OBJ-20 behavior was implemented.
- Validation: macOS build PASS; iOS simulator build PASS with the existing AppIntents metadata warning only; focused compact-action accessibility test PASS; focused `DiarizationFallbackTests` PASS; focused `ProcessingPhaseTests` PASS; full `TranscriberTests` PASS (130/130); `git diff --check` PASS before docs and again after docs.
- Device detection: `xcrun devicectl list devices` showed the connected iPhone available with identifier `F8EA1DB6-2D3A-53EE-A3D9-80A6FE2CB204`; `xcodebuild -showdestinations` listed physical destination `00008150-000909261440401C`.
- Install/run: physical-device build PASS using existing project/scheme/signing settings. Installed `com.daniel.transcriber2.beta` to the connected iPhone with `devicectl`; first launch attempt was denied because the device was locked; after unlock/retry, launch succeeded.
- Auditor: ALIGNED. Auditor verified the only functional code change is limited to the OBJ-17-touched playback helper, accessibility labels/hints remain present, compact action layout remains intact, and no broad transcription/diarization/model/export/persistence/background-recording behavior or OBJ-18+ work was introduced.
- Device gates outstanding: Human Reviewer should re-check completed transcript Play/Pause first, then re-check live preview, speaker labels, Cancel during processing, and the remaining header layout issue.
- Verdict: ASK USER. Recommendation: re-check this installed build for Play/Pause. If playback is now acceptable but live preview or speaker-label behavior still fails, pause before OBJ-18 and create a targeted stabilization objective rather than expanding OBJ-17.

## OBJ-17 — Human Reviewer Product Decision: Diarization Reliability Blocks Beta — 2026-06-22
- Source: Human Reviewer product decision after repeated iPhone testing during OBJ-17 closeout.
- Result: OBJ-17 closeout is paused. Do not commit OBJ-17, merge, advance to OBJ-18, start Mac parity, add server/cloud processing, add pyannote, or add new dependencies until the Manager receives Human approval for the next plan step.
- Product finding: speaker labeling/diarization has been unreliable across repeated testing, including crashes or crash contribution, stuck speaker labeling, frequent need to cancel out, and long duration even on short recordings.
- Product impact: speaker labeling is a key beta feature, so the app cannot be considered beta-ready while diarization can crash, hang, or leave the workflow stuck.
- OBJ-17 classification: this is not treated as an OBJ-17 accessibility failure unless later evidence shows OBJ-17 caused it. OBJ-17 remains open for Play/Pause and visual accessibility follow-up, but the diarization concern is now logged as a blocking product concern requiring a proposed stabilization/engine-decision objective before OBJ-18.
- Proposed next objective: OBJ-17.5 — Diarization Reliability & Engine Decision, to decide whether the current on-device diarization implementation is acceptable for beta, and if not, what hardened replacement/fallback architecture should be used.
- Gate implication: do not silently advance from OBJ-17 to OBJ-18 while diarization reliability remains unresolved. Human approval is required before inserting OBJ-17.5 into `PLAN.md`/`OBJECTIVE.md` or creating `docs/planning/objectives/OBJECTIVE-17.5.md`.

## OBJ-17 — FIX FIRST Follow-Up: Transcript Detail Header Recheck Build — 2026-06-22
- Tier: agent-verifiable layout fix complete; Human should re-check the transcript/detail header on iPhone.
- Human decision: OBJ-17.5 is approved in principle as the next checkpoint after OBJ-17 is accepted, committed, and merged, but its planning files must not be applied until OBJ-17 is ready to close. Mac parity remains blocked behind the diarization checkpoint.
- Header/layout fix: iOS transcript-related screens now use compact inline navigation titles for the recording/transcript screen, saved recording detail, and shared recording detail. This reduces the large `Transcriber 2.0`/detail header space while preserving the native navigation bar back/dismiss affordance.
- Playback status: the prior scoped playback fix remains in place through `AudioPlaybackController` using a retained `AVPlayer`/`AVPlayerItem`; Human device verification is still required to confirm Play/Pause no longer stops after about half a second.
- Action bar/accessibility status: compact larger-icon action bar, accessibility labels/hints/traits, status/Diagnostics scrolling, and Cancel visibility during processing remain preserved.
- Diarization status: no diarization architecture work was implemented. The reliability concern remains logged as a blocking product concern for OBJ-17.5 before OBJ-18.
- Validation: macOS build PASS; iOS simulator build PASS with the existing AppIntents metadata warning only; focused compact-action accessibility test PASS; full `TranscriberTests` PASS (130/130); physical iPhone build PASS using existing project/scheme/signing settings.
- Install/run: installed updated `com.daniel.transcriber2.beta` on the connected iPhone. Launch was attempted three times but iOS refused because the device was locked, so this specific build is installed but not launched by the agent.
- Gate implication: ASK USER / Human recheck needed for Play/Pause, transcript/detail header spacing, compact action bar accessibility, and Cancel visibility during processing before OBJ-17 can close.

## OBJ-17 — Human Reviewer FAIL: Play/Pause Still Broken, Header PASS — 2026-06-22
- Source: Human Reviewer recheck on the installed iPhone build after the transcript/detail header follow-up.
- Result: FAIL. Keep OBJ-17 open; do not commit, merge, advance `OBJECTIVE.md`, create OBJ-17.5 files, or start OBJ-18.
- Finding 1: Play/Pause still does not work. Play gives the same short or failed playback behavior as before.
- Finding 2: header/title layout is much better. Human Reviewer marked this part PASS.
- Finding 3: bottom action bar is visible after canceling processing.
- Finding 4: during active processing only Cancel is visible. This may be acceptable for OBJ-17 when processing is intentionally modal, but the product direction is shifting toward background processing where the user is not trapped on the processing screen.
- Finding 5: diarization/speaker labeling again became stuck or unusably slow. A short recording was still not handled after about 1.5-2 minutes.
- Product direction for OBJ-17.5 planning: preload the default/Base English model on app launch; investigate warming or preloading diarization resources; allow transcription and speaker-label processing to continue while the user navigates elsewhere; show visible per-recording processing states in Dashboard, Library, and detail; add timeout/failure handling so `Identifying speakers` never hangs forever; keep the transcript available even if speaker labeling fails.
- Required OBJ-17 action: fix Play/Pause or return BLOCKED with a precise explanation. Preserve the compact action bar, accessibility labels/hints, status/Diagnostics scrolling, and Cancel visibility during processing. Do not implement model preload, background processing, diarization reliability architecture, OBJ-18, or unrelated backlog items inside OBJ-17.
- Gate recommendation: FIX FIRST until Play/Pause is fixed or safely blocked/classified.

## OBJ-17 — FIX FIRST Follow-Up: Local Playback Repair — 2026-06-22
- Tier: agent-verifiable fix attempt complete; Human should re-check Play/Pause on the installed iPhone build.
- Playback investigation: OBJ-17 changed the saved-recording transcript detail action area, so the completed transcript Play/Pause wiring remains in scope for OBJ-17 fallout. The earlier retained `AVPlayer` attempt did not satisfy Human device testing, so the playback helper was returned to explicit local-file playback behavior using a retained `AVAudioPlayer`.
- Playback fix attempt: `AudioPlaybackController` now creates and retains an `AVAudioPlayer` for the current recording URL, activates the iOS playback audio session before playback, supplies file type hints for common saved/imported audio formats, keeps Play/Pause state published for the compact action bar, resets at end of file, and clears state on decode errors.
- Tests added: `TranscriptSegmentReassignmentTests.playbackFileTypeHintsCoverSavedAndImportedAudio()` covers CAF, M4A, WAV, MP3, and unknown extension hint behavior.
- Header/layout: Human Reviewer PASS for the compact inline transcript/detail header is recorded and the improvement remains in place.
- Action bar/accessibility: compact larger-icon action bar, accessible labels/hints/traits, status/Diagnostics scrolling with transcript content, and Cancel-only processing controls remain preserved. During active transcription/speaker-labeling, Cancel is intentionally the only compact bottom action because completed actions are not safe or meaningful until processing finishes.
- Scope check: no model preload, background processing, diarization architecture, transcription, diarization algorithm, model, export, retry, save, persistence, signing, background-recording, Dynamic Island, model-change/rerun, delete-downloaded-models, dependency, project-structure, OBJ-18, OBJ-19, or OBJ-20 work was implemented.
- OBJ-17.5 planning note: diarization reliability remains logged as a blocking product concern before OBJ-18. The queued OBJ-17.5 proposal should include default/Base English model preload on app launch, diarization resource warm/preload investigation, background processing while navigating, per-recording processing status, timeout/failure handling for stuck speaker identification, and transcript availability when speaker labeling fails. No OBJ-17.5 planning files were created or applied in this pass.
- Validation: macOS build PASS; iOS simulator build PASS with the existing AppIntents metadata warning only; focused playback hint test PASS; focused compact-action accessibility test PASS; full `TranscriberTests` PASS (131/131) after rerunning serially when an initial parallel run hit an Xcode build database lock; `git diff --check` PASS.
- Device install/run: physical iPhone build PASS using existing project/scheme/signing settings. Installed `com.daniel.transcriber2.beta` to the connected iPhone with `devicectl`; launched `com.daniel.transcriber2.beta` successfully.
- Auditor: ALIGNED. Auditor verified the only functional code change is limited to the OBJ-17-touched playback helper, compact action accessibility remains present, Cancel remains reachable during processing, and no broad transcription/diarization/model/preload/background-processing/export/persistence behavior or OBJ-18+ work was introduced.
- Device gates outstanding: Human Reviewer should re-check completed transcript Play/Pause first, then verify the compact action bar remains usable and Cancel remains clear during processing.
- Verdict: ASK USER. The code-level Play/Pause fix attempt is green and installed/launched, but real iPhone audio behavior needs Human confirmation before OBJ-17 can close.

## OBJ-17 — Final Human Reviewer PASS and Gate — 2026-06-23
- Source: Human Reviewer final closeout approval on the installed iPhone build after the dedicated playback repair path.
- Human Reviewer result: PASS for OBJ-17.
- Confirmed on iPhone: playback works, playback continues past 1 second, Pause works, Play works again after Pause, Back/Forward/player controls are acceptable, and the dedicated mini-player/playback-safe M4A derivative approach is acceptable.
- Confirmed on iPhone: original recording preservation remains a requirement; the M4A derivative is accepted only as a cache/regenerable playback artifact.
- Confirmed on iPhone: header/title layout is much better and acceptable; compact player/action controls are acceptable; accessibility/layout items are acceptable for OBJ-17.
- Current closeout validation: macOS build PASS; iOS simulator build PASS; physical iPhone build/install/launch PASS from the installed OBJ-17 build; full `TranscriberTests` PASS (133/133); focused playback/cache tests PASS; focused compact-action accessibility test PASS; `git diff --check` PASS.
- Auditor closeout: ALIGNED. OBJ-17 remains limited to accepted playback/action-bar/layout/accessibility work plus planning/QA docs. No transcription, diarization algorithm, model, export, retry, save, persistence, signing, background-recording, dependency, SwiftData schema, prohibited-path, OBJ-18, OBJ-19, or OBJ-20 implementation work was introduced.
- Diarization blocker: speaker-label reliability is not accepted as fixed. FluidAudio/Sortformer diarization safety, timeout, cancellation, transcript preservation, playback preservation, retry state, and overlapping-attempt protection are queued as **OBJ-17.1 — FluidAudio Diarization Safety & Timeout Stabilization** before OBJ-18.
- Verdict: PASS. Manager gate decision: PROCEED for OBJ-17. Do not start OBJ-18 until OBJ-17.1 is completed or explicitly re-gated by the Human Reviewer.

## OBJ-17.1 — FluidAudio Diarization Safety & Timeout Stabilization — 2026-06-23
- Tier: agent-verifiable safety hardening completed; real-world diarization timing/quality remains Human-owned iPhone validation.
- Build: macOS PASS / iOS-sim PASS / physical iPhone build PASS.
- Unit/integration tests: `TranscriberTests` PASS using `-only-testing:TranscriberTests`; focused `DiarizationFallbackTests` PASS; focused completed-recording playback regression tests PASS.
- Device install/launch: PASS on `iPhone 14 Pro` (`00008150-000909261440401C`) using the existing Transcriber scheme/signing settings; installed and launched bundle `com.daniel.transcriber2.beta` with `devicectl`.
- Failure injection: tests simulate thrown diarization failure, primary/fallback timeout, a diarization task that ignores cancellation, cancel during speaker labeling, retry from stored raw transcription, transcript preservation after timeout/cancel/failure, playback-duration availability after timeout/cancel paths, and blocking a retry while an abandoned/stuck attempt is guarded.
- Auditor: ALIGNED. Auditor verified FluidAudio remains the current engine, diagnostics avoid transcript/audio content, transcripts/original audio/playback derivative paths were not weakened, no dependency/new engine/server/off-device work was added, no OBJ-18 work started, strict concurrency was not weakened, and timeout/cancel/failure paths clear the active "Identifying speakers" state.
- Regression checklist: PASS for scoped regression. The accepted M4A playback derivative code was not changed; focused playback tests stayed green. `git diff --check` PASS.
- Device gates outstanding: Human Reviewer should run the OBJ-17.1 iPhone checklist: short one-speaker recording, short two-speaker recording if available, cancel during speaker labeling, timeout/stuck path if reproducible, retry speaker labels, and playback after cancel/timeout.
- Verdict: PASS for agent-verifiable OBJ-17.1 Phase 1 safety scope. Manager gate recommendation: ASK USER until the Human Reviewer completes the installed-build device checklist and accepts real-device behavior.

## Deferred Backlog — Launch Readiness & Default Model Preload — 2026-06-23
- Tier: planning-only. No implementation, runtime behavior, model-loading behavior, diarization behavior, dependency, signing, project-structure, or OBJ-18 work was started.
- Scope queued: skippable launch/readiness screen for the default/Base English transcription model; background model loading after skip; model readiness on Dashboard/Home and Record surfaces; recording, Library, playback, and navigation remain available while the model loads; retryable model-load failure.
- Boundaries queued: no diarization/FluidAudio preload unless later approved; no server/off-device processing; no sherpa-onnx; no pyannote; no new dependencies; no model-change/rerun backlog; no delete-downloaded-models backlog.
- Superseded closeout note: on 2026-06-23 the Human Reviewer accepted OBJ-17.1 and chose to finish the original 20 stated objectives before creating new 17.x feature objectives. This launch-readiness idea is retained as deferred backlog only, not an active objective, and `docs/planning/objectives/OBJECTIVE-17.2.md` should not exist in the closeout branch.

## OBJ-17.1 — Human Reviewer FIX FIRST: Stage Diagnostics, Retry Guard, Compact Header/Player — 2026-06-23
- Source: Human Reviewer iPhone test after the first OBJ-17.1 install. Result: FIX FIRST. Safety improved: transcript preserved, playback/action bar usable, and the app did not remain permanently trapped in "Identifying speakers." Product blocker remains: speaker labels timed out on a short real recording.
- Diagnosis from prior build: the persisted diagnostics did not contain enough stage detail to prove whether the timeout happened in model/resource loading, process, or finalize. Also, the first private log marker said `audio_inspection.start` before the app actually loaded FluidAudio resources, so that marker could mislead diagnosis. This pass corrects the stage order and persists stage/timing details in the in-app Diagnostics rows.
- Diarization fix summary: stage-aware diagnostics now track audio inspection, conversion/prep, model/resource loading, Sortformer process, finalize, timeout stage, and per-stage timings without transcript/audio content. Production timeouts are split by stage: longer model/resource-load allowance for first-run Core ML work, separate process/finalize limits, and precise timeout messages naming the stage. Retry guard now has test coverage proving it remains blocked for truly uncooperative abandoned work but clears when a timed-out attempt later cooperatively exits.
- Layout fix summary: completed recording detail now puts a compact mini-player and speaker-label status into a pinned transcript header, reducing rejected top spacing and keeping the player/status visible while scrolling without covering transcript text or the bottom action bar. The Record screen title/status area uses tighter top padding and smaller status typography.
- Validation: `git diff --check` PASS; macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS; focused `DiarizationFallbackTests` PASS; focused `ProcessingDiagnosticsTests` PASS; focused completed-recording playback regression tests PASS; physical iPhone build/install/launch PASS on `iPhone 14 Pro` (`00008150-000909261440401C`), bundle `com.daniel.transcriber2.beta`.
- Device gates outstanding: Human Reviewer should retry short one-speaker and short two-speaker speaker labeling, inspect Diagnostics after any timeout to read the exact stage/timing, retry speaker labels after timeout, verify playback after timeout, scroll the transcript to confirm the compact sticky player/status remains present, and confirm the top title/status spacing is compact.
- Verdict: FIX FIRST remains until the Human Reviewer verifies the installed build. If stage diagnostics show FluidAudio consistently times out inside model/resource loading, process, or finalize on short recordings even with the longer model-load allowance, the Manager should return ASK USER for an engine/pipeline architecture decision before beta/OBJ-18.

## OBJ-17.1 — Human Reviewer FIX FIRST: Speaker-Turn Grouping and Header Tuning — 2026-06-23
- Source: Human Reviewer iPhone test after stage-timeout tuning. Result: FIX FIRST, but diarization now completes on device: speaker labels completed, 2 speaker labels detected, transcript remained available, and playback remained available.
- Speaker-turn tuning: completed transcript display now groups adjacent same-speaker segments into display-only speaker turns when the gap is 2 seconds or less, the grouped turn is 60 seconds or less, and the group has no more than 12 underlying segments. Grouping never crosses speaker changes, large pauses, blank/unknown speakers, or the max-turn limits. Raw transcript/saved `Recording.segments` data is not destructively rewritten; export behavior remains unchanged.
- Edit semantics: grouped cards preserve the first timestamp and contain all underlying segment IDs. Reassigning a grouped turn updates the speaker on those underlying segments only, preserving text and timing.
- Layout tuning: the large speaker-label status/Diagnostics block now scrolls away with transcript content. Only the compact mini-player remains above the scroll as a small persistent playback control; bottom Rename/Share actions remain separate.
- Future backlog note only: Model Selection & Rerun Transcription should be planned later as OBJ-17.3 or another 17.x feature objective. Later requirements: choose a different transcription model from transcript/detail, rerun transcription on existing audio, preserve/archive prior transcript safely, invalidate/retry speaker labels after transcript changes, never delete original audio, and expose clear processing state. This feature was not implemented.
- Validation: `git diff --check` PASS; macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS; focused `DiarizationFallbackTests` PASS; focused speaker grouping tests PASS; focused playback regression tests PASS; physical iPhone build PASS and install PASS on `iPhone 14 Pro` (`F8EA1DB6-2D3A-53EE-A3D9-80A6FE2CB204` / UDID `00008150-000909261440401C`). Command-line launch was denied because the device was locked.
- Device gates outstanding: Human Reviewer should verify same-speaker adjacent segments are visually grouped, speaker changes start new cards, playback works, scrolling moves the large status/Diagnostics area away, compact playback behavior is acceptable, Rename/Share remain usable, and Diagnostics remain accessible.

## OBJ-17.1 — Final Human Reviewer PASS and Gate — 2026-06-23
- Source: Human Reviewer accepted OBJ-17.1 after device testing. Confirmed diarization now completes on device; speaker labels are usable enough to proceed; speaker-turn grouping/display tuning is acceptable for now; header/player/status scrolling behavior is acceptable for now; transcript remains available; playback remains available; and the app is no longer trapped by FluidAudio timeout/cancel behavior.
- Gate: PASS / PROCEED for OBJ-17.1. OBJ-17.1 served its purpose as a diarization safety/tuning checkpoint and is complete.
- Deferred backlog only: launch readiness screen with default/Base English preload and Skip loading; rerun transcription with a different model from transcript/detail; delete downloaded models; further speaker-turn grouping polish; further sticky/compact player polish; broader diarization engine evaluation if FluidAudio becomes limiting; background processing/job architecture improvements; and diarization resource/model preload or warmup only after explicit approval. No active OBJ-17.2 or OBJ-17.3 objective is created during closeout.
- Validation retained from accepted OBJ-17.1 branch: `git diff --check` PASS; macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS; focused diarization/session-state tests PASS; focused speaker grouping tests PASS; focused playback regression tests PASS; physical iPhone build/install PASS. The only later edits in this closeout are planning/reporting updates and removal of the inactive OBJ-17.2 objective file.

## OBJ-18 — Mac Companion Parity — Agent Pass — 2026-06-23
- Tier: agent-verifiable implementation and launch completed; real Mac GUI workflow remains Human-owned.
- Build: macOS PASS / iOS-sim PASS.
- Unit/integration tests: full `TranscriberTests` PASS, 143/143. Focused Model Lab + playback/cache + transcript export + shared-audio import tests PASS, 35/35.
- Mac implementation: Model Lab is now a fourth primary Mac tab and is reachable from Dashboard and Settings. Mac Model Lab lists and runs curated Whisper models only; iOS continues to expose Whisper and Parakeet.
- Existing Mac paths audited: in-app file importer with security-scoped access and app-storage copy; Whisper final transcription; Library transcript review; accepted completed-recording M4A playback derivative; speaker/status presentation; diagnostics; phase timeline; TXT/SRT/JSON export; system sharing.
- Mac run: updated app launched successfully and remained running. This Codex session lacks Screen Recording and Accessibility permission, so native window capture/click-through could not be completed. Existing AppIntents service warning remained; no launch crash was observed.
- Auditor: ALIGNED. No iOS regression from platform guards; no dependency, schema, concurrency, project-setting, server/cloud/off-device, new-engine, deferred 17.x, OBJ-19, OBJ-20, or prohibited-path work.
- Intentional gaps: documented in `DECISIONS.md` D-011. Parakeet Model Lab comparison and the Share to Transcriber extension remain iOS-only; Mac uses in-app import and system share controls.
- Human Mac checklist outstanding: verify four tabs; import/transcribe; completed playback; transcript/speaker/status/diagnostics/timeline rendering; TXT/SRT/JSON share; Whisper-only Model Lab comparison/report; accept intentional gaps.
- Regression checklist: `git diff --check` PASS; accepted playback derivative unchanged; iOS simulator build PASS; deferred backlog untouched.
- Verdict: PASS for agent-verifiable scope. Manager gate recommendation: **ASK USER** until Human Reviewer Mac testing is accepted. Do not advance to OBJ-19.

## OBJ-18 — Human Review FIX FIRST Follow-Up — 2026-06-23
- Human findings addressed: stuck Mac recording sheet, Live Preview readiness not started, and adjacent same-speaker cards splitting at display caps.
- Mac close behavior: recording/import remains a SwiftUI sheet, so it now has an explicit Close toolbar button. Idle/completed/failed sheets dismiss directly. Active preparation, recording, transcription, or speaker labeling requires confirmation.
- Data safety: confirmed recording close stops capture and inserts a retryable Library record. Copied imported audio is also inserted before processing-close can dismiss, including cancellation races that move the session to failed first. Persistence failure keeps the sheet open with a durable Retry Save and Close path.
- Readiness: Mac launch starts non-blocking Whisper Live Preview preparation first. Default/Base English preload starts only after Live Preview succeeds. Failure is visible and retryable; recording and navigation are not gated. No full launch readiness screen was added. FluidAudio/Sortformer preload remains deferred to preserve deliberate transcription-to-diarization resource pacing.
- Speaker grouping: display-only grouping now follows same certain speaker plus an adjacent gap of 2 seconds or less. Different speakers, unknown speakers, and gaps over 2 seconds stay separate. The old 60-second/12-segment display caps no longer split a continuous turn. Grouped cards retain underlying IDs and show a start-end timestamp range. Raw segments and exports are unchanged.
- Auditor: final **ALIGNED** after Worker fixed import-cancellation preservation, durable save retry, and readiness serialization. No dependency, new engine, server/cloud/off-device, schema, strict-concurrency, project-setting, prohibited-path, OBJ-19, or OBJ-20 drift.
- Validation: `git diff --check` PASS; macOS build PASS; iOS simulator build PASS; full `TranscriberTests` PASS 147/147; focused readiness/close/grouping/playback/export/persistence/import tests PASS 43/43.
- Mac run: updated app launched and remained running. Logs showed launch-time model checks and Core ML/Apple Neural Engine loading with no launch crash. Native GUI interaction could not be automated because this Codex session lacks macOS Screen Recording/Accessibility permission.
- Human Mac gate: verify idle Close; active-recording Keep Open and Stop, Save, and Close; retryable Library item after close; Preparing/Loading and Retry states for Live Preview; improved same-speaker grouping; completed playback.
- Verdict: PASS for agent-verifiable FIX FIRST work. Manager gate recommendation: **ASK USER** for the real Mac interaction checklist. Keep OBJ-18 active and do not start OBJ-19/OBJ-20.

## OBJ-18 — Final Human Reviewer Acceptance — 2026-06-25
- Human decision: **PROCEED**. OBJ-18 is accepted as a limited Mac companion baseline.
- Accepted evidence: macOS build and app launch passed; the Mac recording sheet gained safe Close behavior; Live Preview readiness and ordered default-model preload were improved; same-speaker display grouping improved; playback behavior was not changed; full and focused tests passed.
- Validation boundary: exhaustive Mac parity was not Human-verified. Further Mac GUI validation/polish is deferred.
- Product priority: the mobile app remains the primary beta target, and mobile-first beta work proceeds to OBJ-19.
- Scope confirmation: no additional Mac feature work, full launch readiness screen, deferred 17.x feature objective, OBJ-19 implementation, dependency, engine, server/cloud/off-device path, or prohibited-path change was added during closeout.
- Final Manager gate: **PROCEED** for the accepted limited Mac companion baseline.

## OBJ-19 — Cancellation & Failure-Injection Hardening — 2026-06-25
- Tier: agent-verifiable cancellation/failure matrix completed; real iPhone framework/hardware realism remains Human-owned for OBJ-20.
- Build: macOS PASS / iOS-simulator PASS.
- Unit/integration tests: full `TranscriberTests` PASS, 163/163. Focused cancel/failure, diarization/session-state, model readiness/download, microphone fallback, import/persistence/save, write-error, playback, export, and stress suites PASS, 112/112.
- `git diff --check`: PASS.
- Cancellation coverage: imported initial final transcription; retry transcription; initial post-transcription speaker labeling; saved-recording label retry; current-session label retry; copied import processing; rapid cancel/retry; and superseding work on different audio.
- Preservation assertions: existing audio remains on disk; copied imports are inserted immediately as retryable Library records; completed transcript/raw timing survives label cancellation/timeout/failure; retry flags match the saved work; and stale attempts cannot overwrite newer results.
- UI/activity recovery: processing phases clear, speaker-label activity clears, Dashboard/Library activity entries do not remain stale, and canceled label work lands in completed/retryable state rather than a permanent “Identifying speakers” state.
- Failure injection: selected model verification failure; fallback model notice; microphone unavailable fallback/notice; diarization primary/fallback error, timeout, ignored cancellation, and overlap guard; download failure plus Repair/Redownload; persistence save failure plus later save retry; low-level audio write failure; and missing-file readiness reconciliation.
- Stress/regression: serialized rapid cancel/retry prevents stale publication; different-audio supersession clears the old activity without clearing the new one; 2,000-recording Dashboard filtering remains bounded/sorted; back-to-back model lifecycle states remain scoped; happy-path transcription/labeling remains green.
- Model cleanup: cancellation now calls unload for the injected transcription engine and, on iOS, both Whisper and any active Parakeet final engine; model state returns to not loaded.
- Playback/export regression: accepted M4A derivative implementation was not changed; playback/cache and TXT/SRT/JSON tests pass.
- Auditor: final **ALIGNED** after FIX FIRST. Initial audit found incomplete initial-path evidence, stale-activity assertions, and provider cleanup evidence. Follow-up added initial transcription/label cancellation, current-label cancellation, serialized overlap coverage, and activity cleanup. No data-loss path discovered remains unfixed.
- Scope audit: no prohibited paths, dependency revisions, server/cloud/off-device processing, new diarization engine, schema change, strict-concurrency weakening, accepted playback/M4A change, deferred feature, or OBJ-20 implementation.
- Device install: not attempted because the connected iPhone was unavailable to CoreDevice during QA.
- Remaining Human/device checks for OBJ-20: cancel a real recorded final transcription with Whisper and Parakeet where available; cancel and retry real speaker labeling; verify playback/export after cancellation; confirm immediate retry/model switching does not leave resources stuck; exercise unavailable microphone routing; stress rapid record/stop/cancel/retry; inspect a large real Library; and verify interruption/write-error messaging and audio preservation when a reproducible hardware/framework failure can be induced.
- Known limitation: deterministic unit tests can prove the app’s state and persistence contracts, but cannot prove Core ML/FluidAudio/AVAudioEngine physically release device resources or manufacture a genuine recorder write failure.
- Verdict: PASS. Manager gate: **PROCEED**. OBJ-19 is complete; OBJ-20 remains pending and was not started.

## OBJ-19 — Final Human Reviewer PASS and Gate — 2026-06-25
- Human decision: **PROCEED**. OBJ-19 is accepted.
- Confirmed: imported audio persists before processing; cancellation unloads final transcription models; stale attempts cannot overwrite newer results; UI activity/retry state recovers; deterministic failure seams and cancellation-matrix tests are present.
- Accepted validation: `git diff --check` PASS; macOS build PASS; iOS Simulator build PASS; full `TranscriberTests` PASS 163/163; focused OBJ-19 tests PASS 112/112; Auditor ALIGNED.
- Device-owned checks queued for OBJ-20: real provider resource release, genuine recorder write failure, microphone hardware fallback, rapid real-device interleavings, and physical iPhone install/device validation.
- Scope confirmation: no OBJ-20 implementation was included in OBJ-19. Deferred feature/fine-tuning ideas remain deferred until after the original 20 objectives are complete.
- Final Manager gate: **PROCEED**. Advance the planning pointer and branch to OBJ-20 without starting implementation.

## OBJ-20 — Beta Acceptance / Final QA — 2026-06-25
- Tier: agent-verifiable PASS; final device acceptance is Human-owned.
- `git diff --check`: PASS.
- Build: macOS PASS / iOS Simulator PASS / physical iPhone 17 Pro build PASS.
- Physical install: PASS on paired device shown as “iPhone 14 Pro” (iPhone 17 Pro hardware). Command-line launch was blocked because the phone was locked.
- Full unit/integration suite: `TranscriberTests` PASS, 163/163.
- Focused acceptance suites: PASS, 150 executions: acceptance/failure 27; playback/reassignment 15; TXT/SRT/JSON export and import 15; diarization/session 31; model readiness/download 25; microphone/recording/data preservation 37.
- Flake note: one Bluetooth reconnect test failed during an initial parallel run, then passed independently, in the serial 163/163 run, and in a second normal full-suite run. No product failure was reproduced.
- Auditor: **ALIGNED** after one stale planning phrase was corrected.
- Production changes: none. No dependency, schema, new engine, server/cloud/off-device, playback/M4A, strict-concurrency, or prohibited-path change.
- Beta-blocker assessment: no known audio/transcript loss, permanent stuck state, core-workflow crash, inability to record/transcribe/review/export, unbounded processing, or false-complete state was found in agent-verifiable evidence.

### Original 20-objective acceptance matrix

| OBJ | Expected behavior | Existing/agent evidence | Human/device coverage or limitation | Status |
|---|---|---|---|---|
| 01 | Governance, green baseline, persistence safeguards | Builds/tests and corruption/round-trip coverage | No device gate | PASS |
| 02 | Readiness comes from real model files | Present/missing/partial-file and stale-hint tests | Relaunch/reboot/offline persistence pending | NEEDS HUMAN DEVICE CHECK |
| 03 | Honest lifecycle states and safe Repair/Redownload | Lifecycle and cache-safety tests | Real download/corrupt-cache recovery pending | NEEDS HUMAN DEVICE CHECK |
| 04 | Default preload, refresh, verify, fallback | Preflight/refresh/fallback tests | Reboot persistence and offline transcription pending | NEEDS HUMAN DEVICE CHECK |
| 05 | Automatic/built-in/accessory mic selection | Discovery, persistence, route-resolution tests | Physical routing/enumeration pending | NEEDS HUMAN DEVICE CHECK |
| 06 | Test Mic and live meter | Permission/start/stop/failure tests | Real meter and microphone release pending | NEEDS HUMAN DEVICE CHECK |
| 07 | Missing selected mic falls back with notice | Fallback/active-label tests; prior Bluetooth evidence | Hardware-unavailable fallback pending | NEEDS HUMAN DEVICE CHECK |
| 08 | Background/lock and 5/15/30-minute reliability | Safe-stop/interruption tests; prior AirPods acceptance | Full duration/background matrix pending | NEEDS HUMAN DEVICE CHECK |
| 09 | Truthful Library status badges | Status truth table and non-destructive reconciliation | No required device gate | PASS |
| 10 | Dashboard status and core entry points | Dashboard filtering/warning tests | No required device gate | PASS |
| 11 | Model Lab comparison and diagnostics | Model Lab/report tests and prior timings | Exported benchmark polish deferred | PASS WITH DEFERRED POLISH |
| 12 | Segment reassignment with persistence/export | Reassignment and export tests | No required device gate | PASS |
| 13 | Consistent label states and label-only retry | Status/retry tests; prior two-speaker device acceptance | 3/4-speaker sampling pending | NEEDS HUMAN DEVICE CHECK |
| 14 | Timeline, elapsed state, Cancel/Retry | Processing-phase and affordance tests | No required device gate | PASS |
| 15 | Calm diagnostics on normal screens | Capture/formatting/failure tests | Real timing/performance remains device-owned | NEEDS HUMAN DEVICE CHECK |
| 16 | Usable TXT/SRT/JSON with speaker names | Export timing/shape/name tests | Real share-sheet tap-through pending | NEEDS HUMAN DEVICE CHECK |
| 17 | Accessibility and completed playback | Accessibility/playback tests and Human iPhone acceptance | Further polish deferred | PASS |
| 18 | Limited Mac companion baseline | Mac build/launch and focused tests; Human acceptance | Exhaustive Mac polish deferred | PASS WITH DEFERRED POLISH |
| 19 | Safe cancellation/failure recovery | Full deterministic failure matrix and preservation tests | Provider release, write realism, mic fallback, rapid interleavings pending | NEEDS HUMAN DEVICE CHECK |
| 20 | Final beta acceptance and honest limitations | Complete agent baseline, focused suites, physical build/install | Final Human iPhone acceptance pending | NEEDS HUMAN DEVICE CHECK |

### Known limitations and deferred work
- Human-owned: background/lock and 5/15/30-minute reliability; model persistence after reboot; offline operation; real microphone/Bluetooth fallback; genuine recorder interruption/write failure; provider resource release; rapid real-device interleavings; share/import workflows; battery, heat, and performance.
- Accepted limitation: Mac is a limited companion baseline; exhaustive Mac polish is deferred.
- Beta limitation: diarization may require retry/manual cleanup, especially with 3–4 speakers.
- Deferred feature/fine-tuning work was not implemented: launch readiness UI, model rerun, model deletion, session decomposition, language picker, speaker-color parsing changes, new diarization engines, and server/cloud/off-device processing.

### Final Human iPhone checklist
- [ ] Unlock the phone and open the newly installed build; confirm fresh launch.
- [ ] Confirm model readiness/download state.
- [ ] Record short audio; stop and save.
- [ ] Record while locked/backgrounded; verify complete audio afterward.
- [ ] Complete representative 5-, 15-, and 30-minute runs when practical; note battery, heat, performance, and crashes.
- [ ] Transcribe; confirm text appears before speaker labeling finishes.
- [ ] Complete speaker labeling; retry labels if needed; include 1-, 2-, 3-, and 4-speaker samples when available.
- [ ] Play the recording.
- [ ] Rename a speaker and reassign a segment.
- [ ] Share TXT, SRT, and JSON; confirm usable content and renamed speaker names.
- [ ] Import audio from Files or Voice Memos and transcribe it.
- [ ] Cancel transcription; confirm audio remains and retry works.
- [ ] Cancel speaker labeling; confirm transcript/playback remain and retry works.
- [ ] Exercise model unavailable/Repair/Redownload if feasible.
- [ ] Force-quit/relaunch and reboot; confirm downloaded models remain ready.
- [ ] Enable Airplane Mode after models are ready and complete offline transcription.
- [ ] Disconnect a selected microphone/Bluetooth device; confirm recording fallback and notice.
- [ ] Rapidly record, stop, cancel, and retry several times.
- [ ] Confirm transcription/diarization resources do not remain stuck after cancellation or model switching.
- [ ] Reproduce a real interruption or recorder write failure if feasible; confirm honest messaging and preserved audio.
- [ ] Confirm no audio or transcript is lost throughout.

- Release-readiness recommendation: **ASK USER**. If the checklist passes without data loss, crashes, permanent stuck processing, failed default transcription, or unusable review/export, the Manager may close OBJ-20 as `PROCEED`.

## OBJ-20 — Mac App Acceptance Hardening — 2026-06-27
- Tier: agent-verifiable PASS; short Human Mac spot-check remains.
- `git diff --check`: PASS.
- Build: macOS PASS / generic iOS Simulator PASS.
- Full unit/integration suite: `TranscriberTests` PASS, 164/164 with 0 failures or skips.
- Focused suites: recording close/reliability 5/5; shared inbox + persistence 13/13; cancellation/failure preservation 10/10; playback/transcript review 15/15 including 3 CAF/M4A cases; TXT/SRT/JSON export 9/9; launch/model readiness/preflight 9/9.
- Direct blocker fixed: Library navigation could freeze because `SharedAudioInbox.refresh()` enumerated the app-group inbox synchronously on the main UI thread. Enumeration and sorting now run off the MainActor and only the current, non-canceled refresh publishes results.
- Direct blocker fixed: export could show a blank 100×80 Mac sheet because URL and presentation Boolean state raced. One identifiable export item now atomically drives presentation; TXT/SRT/JSON generation is unchanged.
- Mac run PASS: clean launch; Dashboard/Library/Model Lab/Settings navigation; responsive Library; saved and completed item opening; playback progress/pause; readable speaker grouping/status; expanded diagnostics; recording sheet opening; Live Preview preparation; safe active close confirmation; cancel-to-retryable state; idle close; import picker open/cancel; export controls; corrected share-sheet presentation.
- Preservation: Worker and QA test recordings were stopped and saved, not deleted. The existing Worker-created retryable item was not altered by QA. No orphaned active session remained.
- Auditor: **ALIGNED**. No prohibited path, dependency, project setting, engine, server/cloud/off-device work, deferred feature, schema, strict-concurrency, persistence-contract, playback/M4A, or iOS regression found.
- Environment warnings only: local CoreSimulator framework version differed slightly from Xcode, but the required generic simulator build passed; macOS selected arm64 from matching arm64/x86_64 destinations.
- Evidence limitation: macOS denied screenshot capture, so GUI evidence came from accessibility-tree state and live state changes.
- Remaining Human Mac checklist: confirm playback is audibly correct; visually judge transcript density/window sizing; import one real external file and confirm the persisted Library item; complete TXT/SRT/JSON system-share destinations; exercise a real model loading/failure/retry state if practical; optionally confirm intended Mac microphone input.
- Manager gate: **ASK USER**. The Mac companion is usable enough for the limited beta baseline in agent evidence. Complete the short Human Mac spot-check, then proceed to final iPhone QA.

## OBJ-20 — Final Human Reviewer PASS and Beta 2.0 Acceptance — 2026-06-28
- Human decision: **PASS / PROCEED**. The iPhone app and limited Mac companion are acceptable for closing the original Transcriber 2.0 Beta roadmap.
- Human summary: everything works mostly; remaining limitations, UI polish, feature additions, and deeper fine-tuning move to Beta 2.1 planning.
- Final retained validation: `git diff --check` PASS; macOS build PASS; generic iOS Simulator build PASS; full `TranscriberTests` PASS 164/164; focused Mac close/readiness/import/persistence/playback/export and failure-preservation suites PASS.
- Accepted limitations: mobile remains the primary target; Mac is an accepted limited companion baseline without exhaustive GUI polish; diarization may still benefit from retry/manual cleanup; deeper device/performance and visual polish remain future work.
- No known remaining issue was accepted as a Beta 2.0 blocker. Audio/transcript preservation, retryable failure handling, and accepted playback/M4A behavior remain intact.
- Deferred Beta 2.1 discussion items are preserved in [DECISIONS.md](DECISIONS.md#d-016--2026-06-28--accept-beta-20-and-preserve-beta-21-planning-backlog); none was implemented during closeout and none blocks Beta 2.0 acceptance.
- Final Manager gate: **PROCEED**. OBJ-20 and the original 20-objective Beta 2.0 roadmap are complete.
