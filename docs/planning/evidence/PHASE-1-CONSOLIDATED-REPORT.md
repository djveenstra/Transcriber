# Phase 1 Consolidated Report

Date: 2026-07-29

Branch: `codex/voxbot-accuracy-phase-1`

Milestone gate: `PROCEED`

## Outcome

Phase 1 is complete. VX-04 through VX-07 were activated and executed sequentially, each under its own risk tier and gate. The current Mac application remains usable through its existing production paths; new artifact and prepared-audio infrastructure is dormant.

No VX-02 cleanup, private-audio use, downloaded research-model integration, dependency update, iOS/Python workspace change, or Phase 2 work occurred.

## Objective gates

| Objective | Risk | Result | Auditor | Independent focused QA | Full tests at gate |
|---|---:|---|---|---:|---:|
| VX-04 orchestration seams | High | `PROCEED` | `ALIGNED` | 25/25 | 167/167 |
| VX-05 artifact store | Critical | `PROCEED` | `ALIGNED` | 20/20 | 187/187 |
| VX-06 jobs/relaunch | Critical | `PROCEED` | `ALIGNED` | 37/37 | 208/208 |
| VX-07 audio preparation | High | `PROCEED` | `ALIGNED` | 17/17 | 225/225 |

## Delivered behavior

### VX-04

Extracted narrow final-transcription, persistence, and diarization-attempt collaborators while retaining `TranscriptionSession` as the MainActor state owner. Transcript-first persistence, cancellation, watchdog, fallback, stale-attempt, and failure behavior remain regression baselines.

### VX-05

Added a dormant versioned artifact store with immutable artifacts/manifests, authoritative current/previous pointers, digests, graph validation, atomic publication ordering, corruption isolation, symlink containment, fail-closed cleanup, and interruption recovery.

### VX-06

Added nil-defaulted durable processing/source IDs, per-recording versioned job files, atomic checkpoints, legal transitions, stale-input protections, honest partial/success semantics, and idempotent relaunch recovery through existing retry projections. A separately generated synthetic pre-VX-06 store proves old optional-field compatibility.

### VX-07

Added dormant versioned mono 16 kHz Float32 preparation, source/output/time-map metadata, conservative quality measurements, deterministic reuse/invalidation, sidecar-last publication, and deletion-authority checks that preserve sources and unowned occupants.

## Files changed

Governance and evidence:

- `DECISIONS.md`
- `OBJECTIVE.md`
- `PLAN.md`
- `QA.md`
- `docs/planning/objectives/VX-02.md` through `VX-07.md` as applicable
- `docs/planning/evidence/PHASE-0-CONSOLIDATED-REPORT.md`
- `docs/planning/evidence/VX-04-REPORT.md` through `VX-07-REPORT.md`
- `docs/planning/evidence/PHASE-1-CONSOLIDATED-REPORT.md`

Production:

- `Models.swift`
- `Transcriber2App.swift`
- `TranscriptionSession.swift`
- `FinalTranscriptionRunner.swift`
- `PersistenceCoordinator.swift`
- `DiarizationAttemptCoordinator.swift`
- `ProcessingArtifactStore.swift`
- `ProcessingJobStore.swift`
- `RecordingProcessingIdentity.swift`
- `AudioPreparationService.swift`

Tests and synthetic fixture:

- `RecordingPersistenceTests.swift`
- `TranscriptionSessionTests.swift`
- `ProcessingArtifactStoreTests.swift`
- `ProcessingJobStoreTests.swift`
- `AudioPreparationServiceTests.swift`
- `TranscriberTests/Fixtures/pre-vx06.store`

## Final validation

- Mac build: **PASS** with `CODE_SIGNING_ALLOWED=NO`.
- Governed full unit baseline: **225/225 PASS**, 0 failed/skipped/expected failures.
- Final full xcresult: `Test-Transcriber-2026.07.29_13-33-14--0400.xcresult`.
- Final VX-07 independent focused QA: **17/17 PASS**, xcresult `Test-Transcriber-2026.07.29_13-34-30--0400.xcresult`.
- `git diff --check`: **PASS**.
- Branch: `codex/voxbot-accuracy-phase-1`.
- Six checked build settings remain `SWIFT_STRICT_CONCURRENCY = complete`.
- FluidAudio remains `17081252411e0cf69574ee85ec1cd4675765c458`.
- WhisperKit remains `94cf6b120cf9dde32d9dea01acc326e77371302c`.
- Project file and package resolution are unchanged.

A broader non-gating scheme run also started `TranscriberUITests`: all 213 unit tests in that intermediate state passed, while the known generated UI-test runner failed before bootstrap. Per D-007 and the standard validation command, the governed unit-only run is the applicable baseline and passed 225/225.

## Preservation and scope evidence

- Existing recordings, transcript blobs, corrections, speaker mappings, audio filenames, playback/export compatibility, and current retry/cancel projections remain covered by the full suite.
- Original audio is never prepared in place and is guarded against exact-path and symlink-alias deletion.
- Useful results persist before downstream enrichment as before.
- Existing dependencies, pins, strict-concurrency settings, project settings, and current model choices remain unchanged.
- New stores/services are either additive compatibility infrastructure or dormant; no downloaded research model or new runtime was integrated.
- No private or repository audio was read for implementation or tests.
- iOS, Python, legacy, assets, model caches, and VX-02 cleanup candidates were not modified.

## Remaining risks and deferred evidence

- Fault injection proves defined interruption boundaries, not literal sudden power loss on a production application store.
- VX-06 relaunch tests use synthetic/file-backed stores; no private production Library or manual force-quit run was used.
- VX-07 quality thresholds are versioned conservative measurements, not yet calibrated against representative recordings.
- The artifact store and prepared-audio service are dormant; production adoption requires later benchmark and integration gates.
- Real microphone, representative audio, long-run/resource-pressure, packaging, and manual UI behavior were outside Phase 1 scope.
- Q-03 private benchmark source selection and Q-04 accuracy trade-offs remain open.

## Rollback

Each objective is independently reversible:

- VX-04 restores the prior session implementation and removes the three seam files.
- VX-05 removes the dormant artifact store/tests.
- VX-06 disables job bridging/recovery and removes job infrastructure; nil-defaulted IDs remain harmless and old builds ignore them.
- VX-07 removes the dormant preparation service/tests and only test-generated derivatives.

No rollback requires transforming or deleting original audio, existing recordings, transcripts, corrections, or legacy blobs.

## Phase 2 authorization

Phase 2 is not active. The exact approval needed to begin is:

> I accept the Phase 1 milestone and authorize activation of VX-08 only.

That approval does not by itself authorize private audio. Any private dataset use still requires approval of exact recordings or an explicitly bounded collection under D-027.
