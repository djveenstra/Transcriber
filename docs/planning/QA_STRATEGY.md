# QA Strategy — Transcriber Mac Accuracy Expansion

Last updated: 2026-07-28

## 1. Quality model

The app must remain safe and useful while accuracy features are added. QA therefore evaluates five separate truths:

1. **Build truth** — the Mac target compiles with strict concurrency.
2. **Behavior truth** — recording, import, persistence, cancellation, retry, playback, review, and export still work.
3. **Data truth** — existing and new artifacts remain readable, versioned, recoverable, and private.
4. **Accuracy truth** — a new model or pipeline measurably improves representative ground truth.
5. **Release truth** — real audio, resource pressure, accessibility, sandboxing, signing, installation, and long runs work on the supported Mac.

A green build cannot substitute for the other four.

## 2. Baseline

Every code objective runs:

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

The objective adds focused validation; it does not replace the baseline.

## 3. Test layers

### 3.1 Pure unit tests

Use for:

- Versioned encoding/decoding.
- Alignment and consensus rules.
- Metric calculations.
- Speaker assignment and cluster reconciliation.
- Identity threshold/margin/fusion logic.
- State transitions and display models.
- Retention and path policies.

These tests should be deterministic and should not download models.

### 3.2 Integration-style tests with fakes

Use engine protocols and injected persistence to cover:

- Stage sequencing.
- Partial success.
- Cancellation.
- Timeout.
- Fallback.
- Relaunch reconciliation.
- Stale-attempt rejection.
- Failure during atomic writes.
- Model/provider failure isolation.

Fakes prove orchestration behavior, not model quality.

### 3.3 Storage and migration fixtures

Each format or schema change needs:

- Current-version round trip.
- Previous-version read.
- Empty and optional fields.
- Corrupt/truncated data.
- Interrupted write.
- Missing artifact.
- Newer-unknown version handling.
- Rollback compatibility.
- Existing audio filename/path compatibility.

Never run a migration test first against Daniel’s only copy of real application data.

### 3.4 Generated and approved audio fixtures

Use generated audio or tiny approved fixtures for timing, format, conversion, silence, clipping, and path behavior.

Private real recordings belong in an external dataset manifest after explicit approval. Do not commit them or derived voice clips.

### 3.5 Benchmark tests

Benchmark reports must record:

- Dataset and ground-truth version.
- Model/runtime/preprocessing/pipeline versions.
- Configuration and supported Mac hardware.
- Per-condition and aggregate metrics.
- Failures and excluded cases with reasons.
- Time, peak memory, and relevant resource observations.
- Comparison with the current production baseline and best individual component.

Required metric families:

- Transcription: WER, insertions, deletions, substitutions, names/terms, hallucinations, review percentage.
- Diarization: DER or equivalent breakdown, speaker count, fragmentation, merges, overlap, attributed-word accuracy.
- Identity: false identification, false acceptance/rejection, unknown rejection, ambiguity, margins, duration/condition breakdown.
- System: total time, peak memory, failure recovery, relaunch recovery, correction time.

Benchmarks are not ordinary unit tests and may be intentionally opt-in because they use private data and expensive models.

### 3.6 Manual Mac UI QA

Scope to changed surfaces:

- Keyboard and pointer navigation.
- VoiceOver labels and non-color status.
- Recording/import state.
- Draft versus verified state.
- Progress by workstream.
- Cancel/retry/relaunch.
- Playback.
- Transcript and speaker corrections.
- Profile consent, export, and deletion.
- Model download/repair/removal.
- Error messages that state what is safe and retryable.

### 3.7 Human-owned system QA

Daniel owns final validation that cannot be honestly automated:

- Real microphones and representative rooms.
- Long recordings.
- Downloaded model behavior after quit/reboot.
- Memory pressure, thermals, and responsiveness on target hardware.
- Perceived review usefulness and accuracy.
- Private-data policy decisions.
- Signed/notarized installation and launch.
- Final accessibility and production acceptance.

## 4. Mandatory failure matrix

Objectives touching a stage must test applicable failures:

| Failure | Required safe result |
|---|---|
| Recording write error | Existing captured file preserved; no false complete state |
| Import copy failure | Source untouched; no orphan success row |
| Prepared derivative failure | Original preserved; stage retryable |
| Primary transcript failure | Audio preserved; retryable |
| Secondary transcript failure | Successful draft remains usable |
| Diarization failure/timeout | Transcript preserved; anonymous/retry state |
| Identity failure | Anonymous cluster preserved |
| Reconciliation failure | Candidate transcripts preserved |
| Adjudication failure | Accepted deterministic transcript unchanged |
| Save/manifest failure | Prior valid version remains authoritative |
| Cancel | Last useful persisted result remains |
| Relaunch mid-stage | Honest interrupted/retry state; no invented completion |
| Older task finishes late | Cannot overwrite newer task or correction |
| Low disk | No partial authoritative artifact; clear recovery message |
| Corrupt artifact | Isolate damage; original and other artifacts remain usable |

## 5. Privacy QA

For profile, voiceprint, benchmark, or adjudication objectives:

- Search Git status for private artifacts.
- Inspect logs for private paths, transcript text, embeddings, or profile names.
- Verify diagnostic export contents.
- Verify deletion scope and cache cleanup.
- Verify network-disabled behavior.
- Verify every network request is expected, visible, and approved.

## 6. Evidence and verdicts

Append objective evidence to [QA.md](../../QA.md). Include exact commands, pass/fail, relevant report paths, and Human gates.

Verdicts:

- **PASS** — all agent-verifiable acceptance criteria pass.
- **FAIL** — a required behavior or invariant fails.
- **PARTIAL** — automated evidence is green but a named Human/system gate remains.

The Manager maps QA plus audit and Human evidence to the canonical roadmap gate.
