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
