# QA.md — QA Evidence Log

_QA evidence is appended here after each objective by the QA Tester / Manager. Strategy and test types live in [docs/planning/QA_STRATEGY.md](docs/planning/QA_STRATEGY.md). Device test scripts (Human-owned gates) are recorded in this file as they are written (e.g. OBJ-08)._

## Evidence entry format

```
## OBJ-NN — <title> — <date>
- Tier: agent-verifiable | device (Human)
- Build: macOS ✅ / iOS-sim ✅
- Unit/integration tests: <n passed / n total> (new test names)
- Manual UI: <steps + result>
- Failure injection: <cases + result>
- Regression checklist: ✅ / notes
- Device gates outstanding: <list, for Human Reviewer>
- Verdict: PASS / FAIL (defects: …)
```

## Baseline validation commands (run every objective)

```sh
xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild test -project "src/native/Transcriber2/Transcriber2.xcodeproj" -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:TranscriberTests
```

## Standing regression checklist (scope to touched screens)

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
