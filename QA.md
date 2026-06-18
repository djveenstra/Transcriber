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

> _Populated by OBJ-08 (background/lock + 5/15/30-min), OBJ-04/OBJ-20 (model reboot persistence), OBJ-18 (Mac), OBJ-20 (offline/airplane mode, battery, performance). Until then, see PRD §17._

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
