# VX-01 Baseline Evidence

Baseline version: `vx01-baseline-v1`

Captured: 2026-07-29

Scope: Transcriber Mac, read-only application inspection plus standard build and unit-test execution

## Reproduction commands

From the repository root:

```sh
xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" \
  -scheme Transcriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild test \
  -project "src/native/Transcriber2/Transcriber2.xcodeproj" \
  -scheme Transcriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:TranscriberTests
```

Optional command-process observation:

```sh
/usr/bin/time -l <xcodebuild command>
```

## Source and worktree boundary

- Branch: `codex/voxbot-accuracy-phase-0`
- Starting commit: `ae01ecedfe3be891471d9f79a08f097d70fd1dd7`
- The worktree was already dirty before VX-01. It contained the 2026-07-28 governance rewrite, historical-document annotations, the separately authorized Python-app extraction represented by tracked deletions, and untracked reference plans.
- VX-01 did not absorb, revert, stage, commit, or overwrite those changes.
- Phase 0 additions are limited to new VX objective/evidence documents and scoped updates to active governance and QA records.

## Build environment

Sensitive machine identifiers are intentionally omitted.

| Item | Observed value |
|---|---|
| Mac | MacBook Pro, Apple M1 Max |
| CPU | 10 cores: 8 performance, 2 efficiency |
| Unified memory | 32 GB |
| Architecture | arm64 |
| macOS | 26.5.2, build 25F84 |
| Xcode | 26.6, build 17F113 |
| Mac deployment target | 26.0 |
| App bundle identifier | `com.daniel.transcriber2.beta` |
| Swift concurrency | `SWIFT_STRICT_CONCURRENCY = complete` |

This machine describes the current evidence host. It is not yet the Human-approved minimum supported Mac for product performance.

## Dependency baseline

The Xcode project and `Package.resolved` agree:

| Package | Repository | Resolved revision/version |
|---|---|---|
| FluidAudio | `FluidInference/FluidAudio` | `17081252411e0cf69574ee85ec1cd4675765c458` |
| WhisperKit | `argmaxinc/WhisperKit` | `94cf6b120cf9dde32d9dea01acc326e77371302c` |
| Swift Argument Parser | `apple/swift-argument-parser` | `6a52f3251125d74daf04fcbd5e6f08a75d074382`, version 1.8.2 |

No dependency, revision, package resolution, model weight, or runtime was changed.

## Current product flows

Read-only code and test inspection confirms these regression-baseline flows:

1. Dashboard launches recording/import and summarizes microphone, model, and speaker-label status.
2. Recording begins independently of final-model readiness; stopping saves audio before final transcription.
3. Import copies supported audio into application-owned storage before dependent processing.
4. WhisperKit produces Mac live/final transcription through actor-based engine seams.
5. FluidAudio Sortformer applies diarization after a transcript exists, with guarded fallback, timeout, cancellation, and retry.
6. Transcript data is persisted before speaker labeling; diarization failure leaves the transcript usable.
7. Library supports saved-item status, playback, speaker rename/reassignment, retry, and explicit deletion behavior.
8. TXT, SRT, and JSON export preserve speaker display names.
9. Model readiness is reconciled against files and supports repair/redownload.
10. Model Lab compares curated Mac Whisper choices and exports diagnostics.

This is a code-and-test baseline, not a fresh manual UI or real-audio acceptance run.

## Current storage baseline

- SwiftData `Recording` rows contain title, creation time, duration, audio filename, final transcript JSON, raw timed transcription JSON, speaker-name JSON, retry state, and final transcription model ID.
- Application-owned audio is resolved under `Application Support/Transcriber2Beta/Recordings/`.
- Recorded source audio remains the source of truth; playback derivatives are regenerable.
- VX-01 did not open application data, enumerate recordings, or inspect repository audio contents.

## Automated results

### Mac build

- Result: PASS — `** BUILD SUCCEEDED **`
- Elapsed: 9.28 seconds
- `/usr/bin/time` maximum resident set size: 167,641,088 bytes
- `/usr/bin/time` peak memory footprint: 78,578,600 bytes

### `TranscriberTests`

- Result: PASS — `** TEST SUCCEEDED **`
- Tests: 164 passed, 0 failed, 0 skipped
- Elapsed: 16.71 seconds
- `/usr/bin/time` maximum resident set size: 260,702,208 bytes
- `/usr/bin/time` peak memory footprint: 153,076,816 bytes

The Xcode destination warning selected the arm64 Mac destination from equivalent arm64/x86_64 entries. The resulting test summary reports arm64.

## Resource-evidence boundary

The measurements above cover the `xcodebuild` command processes on a warm local checkout. They are useful for rerunning the development baseline but are not representative transcription or diarization measurements.

VX-01 did not:

- load or download a speech model;
- run transcription, diarization, or identity inference;
- use private or repository audio;
- measure app peak unified memory, thermal behavior, energy, or long-run responsiveness.

Those measurements require an approved dataset and the VX-08/VX-09 benchmark workflow.

## Reproducibility verdict

PASS. The code revision boundary, non-sensitive machine environment, deployment/concurrency settings, exact package pins, storage/flow baseline, commands, test count, timings, and evidence limitations are recorded without changing production behavior or accessing private audio.
