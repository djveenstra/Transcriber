# QA Strategy — Transcriber 2.0 Beta

_Derived from the PRD §17 Beta Acceptance Tests. Defines what to test, how, and **when in the development cycle** each test runs. QA evidence is appended to [QA.md](../../QA.md) after each objective._

## Principles

1. **Two tiers of truth.** Agent-verifiable (build, unit tests, simulator behavior, code inspection) vs **Human-owned device gates** (real mic, background/lock, model persistence across reboot, performance, battery, offline). QA must label every result as one or the other.
2. **Data safety is the top QA priority.** Every failure-path test must confirm audio + transcript survive.
3. **Regression budget on every objective.** Each objective re-runs the baseline build/test + a short regression checklist for the screens it touches.
4. **Failure injection is first-class**, not an afterthought — the PRD is explicit about fallbacks and retries.

## Test types & when they run

| Type | What it covers | Cadence / when | Owner |
|---|---|---|---|
| **Unit (automated)** | Pure logic: `TranscriptMerger`, exporters, model-choice/migration, readiness checks, watchdog/fallback, status derivation, reassignment logic | Every objective (added with the feature); CI-equivalent each session | Worker → QA |
| **Build / strict-concurrency** | macOS + iOS-simulator build with `CODE_SIGNING_ALLOWED=NO`; concurrency stays `complete` | Every objective (the drift alarm) | Worker → Auditor |
| **Integration (semi-automated)** | Engine boundaries with fakes (e.g. `FakeDiarizationEngine`), session orchestration, persistence round-trips | Objectives touching the pipeline/persistence (OBJ-02–04, 09, 12–15, 19–20) | Worker → QA |
| **Manual UI (simulator)** | Navigation, tab structure, empty/failure states, share sheet, rename/reassign, settings flows | Objectives touching UI (OBJ-06,07,09–17); regression each objective | QA |
| **Regression** | Prior-objective behavior on touched screens; the [shared checklist](#regression-checklist) | Every objective | QA |
| **Performance** | Transcription/diarization speed (RTF), model load times, live-preview latency, memory at 5/15/30 min | Phase 1, 2, 5, 8 milestones; OBJ-04, 08, 15, 20 | Human (device) + Model Lab |
| **Stress** | Rapid record/stop/cancel/retry interleavings; many recordings in Library; back-to-back model switches | OBJ-19, OBJ-20 | QA (sim) + Human (device) |
| **Failure injection** | Model load failure → fallback/notice; mic unavailable → fallback/notice; diarization timeout/error → approximate/retry; download failure → repair/redownload; save failure → storage alert; write error → retryable | OBJ-03,04,07,13,15,19 | QA |
| **Device** | Real mic capture; background/lock recording; force-quit/relaunch/reboot model persistence; airplane-mode offline; battery | OBJ-04,08,18,20 (Human gates) | Human Reviewer |
| **Accessibility** | Dynamic Type scaling, VoiceOver labels/traits, contrast, non-color status | OBJ-17; spot-check thereafter | QA + Human |

## Mapping PRD §17 acceptance tests to the cycle

### Recording (PRD §17)
- 5 / 15 / 30-min record → stop → transcribe → label → share — **OBJ-08 (sim partial), OBJ-20 (device, Human)**.
- Lock phone / switch apps during recording, audio preserved — **OBJ-08 (device, Human gate)**.

### Import
- Share a Voice Memo to Transcriber; import from Files; transcribe + label imported audio — **OBJ-01 baseline / continuous; re-verified OBJ-16, OBJ-20**.

### Transcription & diarization
- Transcript appears before labeling completes — **continuous; asserted in session tests + manual (OBJ-13, OBJ-14)**.
- 2/3/4-speaker labeling; single-speaker doesn't fail; failed diarization preserves transcript + retry; retry labels doesn't re-transcribe — **OBJ-12, OBJ-13, OBJ-19 (failure injection)**; unit-covered via `runDiarizationWithFallback` tests.

### Cancellation & failure
- Cancel during final transcription / during speaker labeling; state safe after cancel; forced model failure → fallback/notice; forced mic unavailable → fallback/notice — **OBJ-07, OBJ-19**.

### Models
- Download default; force-quit; reopen ready; reboot ready; transcribe without redownload; corrupt/remove model → Repair/Redownload appears — **OBJ-02,03,04 (sim/code), device persistence is Human gate (OBJ-04, OBJ-20)**.

### Export
- Export TXT/SRT/JSON; speaker names appear when renamed — **OBJ-16 (unit + manual)**.

### Model Lab
- Compare ≥2 downloaded models on one recording; records load time, processing time, failure, transcript, report export — **OBJ-11, OBJ-15**.

### Mac companion
- Import/open, play, share where supported — **OBJ-18**.

## Regression checklist (run every objective, scope to touched screens)

1. App launches; all tabs reachable; default model state correct.
2. Record → stop → transcript appears → labels apply (or fail gracefully with retry).
3. Import a file → transcribe → share TXT.
4. Library lists recordings; open detail; play; rename; share; delete (audio + row handled).
5. Cancel during processing leaves transcript/audio safe.
6. No new strict-concurrency warnings; both builds + unit tests green.
7. Forced dark mode intact; no invisible text; no broken share sheet.

## Current automated coverage (baseline) & gaps to fill

**Covered:** `TranscriptMerger`, diarization fallback/watchdog (fakes), audio file writer, recording persistence, transcript export (basic), model choice/migration, shared inbox, WhisperKit engine smoke.
**Gaps (add as features land):** exporter SRT/JSON correctness + speaker names (OBJ-16); model readiness/state machine (OBJ-02,03); `RecordingStatus` derivation (OBJ-09); segment reassignment (OBJ-12); diagnostics capture (OBJ-15); cancellation matrix (OBJ-19). UI flows remain mostly manual; document scripts here when UI tests are impractical.

## Evidence format (append to [QA.md](../../QA.md))

```
## OBJ-NN — <title> — <date>
- Tier: agent-verifiable | device (Human)
- Build: macOS ✅ / iOS-sim ✅
- Unit/integration tests: <n passed / n total> (names of new tests)
- Manual UI: <steps + result>
- Failure injection: <cases + result>
- Regression checklist: ✅ / notes
- Device gates outstanding: <list, for Human Reviewer>
- Verdict: PASS / FAIL (defects: …)
```
