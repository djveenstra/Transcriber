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
