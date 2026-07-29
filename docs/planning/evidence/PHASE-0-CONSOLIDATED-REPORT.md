# Phase 0 Consolidated Report

Date: 2026-07-29

Manager: Codex

Authorization: Daniel explicitly authorized activation and continuous sequential execution of VX-01, VX-02, and VX-03, while forbidding Phase 1, private-audio use, deletion/movement, unscoped production behavior, dependency/model/schema changes, and absorption of unrelated dirty-worktree changes.

## Executive result

| Objective | Risk/workflow | Agent-verifiable result | Manager gate |
|---|---|---|---|
| VX-01 — Mac baseline and benchmark charter | Docs-only plus read-only build/test/resource inspection | Build PASS; 164/164 tests PASS; baseline and privacy charter complete | `PROCEED` |
| VX-02 — Mac-only boundary and removal inventory | Docs-only plus read-only cross-workspace inspection | Inventory PASS; no removal; nine Human disposition choices explicit | `ASK USER` |
| VX-03 — Versioned processing contracts and migration design | Docs-only design for future Critical storage work; independent Auditor then QA | Final Auditor `ALIGNED`; independent QA PASS; no implementation | `ASK USER` |

Phase 0 milestone: **`ASK USER`**.

Phase 1: **not active and not authorized**.

## Worktree preservation

- Starting branch: `codex/voxbot-accuracy-phase-0`.
- Starting commit: `ae01ecedfe3be891471d9f79a08f097d70fd1dd7`.
- The starting worktree already contained the governance rewrite, historical annotations, externally moved Python-app deletions, and untracked reference plans.
- Phase 0 did not revert, overwrite, stage, commit, or absorb those changes.
- No file was deleted or moved.
- `src/native/Transcriber2/` has no diff against HEAD.
- `../iOS Transcriber/`, `../Python Transcriber/`, `src/legacy-ios/`, `XCode App Build/`, `assets/`, root audio, application data, model caches, and `Voiceprint-downloads/` were not modified.

## VX-01 completed work

Evidence:

- [VX-01 baseline](VX-01-BASELINE.md)
- [VX-01 benchmark charter](VX-01-BENCHMARK-CHARTER.md)
- [VX-01 objective](../objectives/VX-01.md)

Recorded:

- non-sensitive M1 Max / 32 GB, macOS 26.5.2, Xcode 26.6 environment;
- macOS 26.0 target and strict concurrency;
- exact FluidAudio, WhisperKit, and Swift Argument Parser resolutions;
- current recording/import/transcription/diarization/persistence/Library/playback/export/model-readiness/Model Lab flows;
- current SwiftData and original-audio placement;
- build/test command process observations and their non-inference limitation;
- external private manifest, consent, ground truth, metrics, held-out comparison, and reporting rules.

Validation:

- Mac build: `** BUILD SUCCEEDED **`; 9.28 seconds.
- `TranscriberTests`: `** TEST SUCCEEDED **`; 164 passed, 0 failed, 0 skipped; 16.71 seconds.
- No model inference, model download, real/private audio, UI, thermal, or long-run claim was made.

Decision:

- The Phase 0 private-data policy is approved: no recording is used until Daniel approves an exact source or bounded collection and its permitted uses.
- Supported minimum hardware, exact private recordings, metric priorities, and thresholds remain deferred to their evidence-producing objectives.

## VX-02 completed work

Evidence:

- [VX-02 boundary inventory](VX-02-BOUNDARY-INVENTORY.md)
- [VX-02 objective](../objectives/VX-02.md)

Findings:

- The Mac and iOS sibling native trees each contain 71 non-`.DS_Store` files and were byte-identical under `diff -qr`.
- The sibling’s governance names it as the iOS product workspace, but its root is not currently a Git repository.
- The iOS-only share target, controller, plist, entitlement, target dependency, and embed phase exist in both copies.
- Eleven production Swift files contain iOS-specific behavior; Parakeet engine code is entirely iOS-gated. Removing branches piecemeal while the Mac project still builds iOS would break the shared project.
- The main app-group entitlement and shared-inbox code are cross-platform and are not proven removable with the share extension.
- `src/legacy-ios/` contains unique custom diarization/VAD/embedding/Whisper-bridge reference value.
- `XCode App Build/` is an ignored stale template with its own clean nested Git repository at commit `f4abfad`.
- `native/Builds/Transcriber 2.0 Beta.app` is an ignored local build artifact.
- `test_clip.m4a` and `Kelly Creek Dr.m4a` are untracked and ignored; their contents and extended metadata were not inspected.
- `assets/Transcriber.icns` remains referenced by the external Python build history; two tracked PNGs remain preserved visual references.
- `Voiceprint-downloads/` remains ignored research material, not production source.

No removal objective was executed. Proposed future mechanical objectives are evidence only and do not change the approved roadmap.

Human choices are listed in the inventory. The conservative resolution is to retain every candidate in place and defer all cleanup; this resolves the Phase 0 deletion gate without adding structural work before Phase 1.

## VX-03 completed work

Evidence:

- [VX-03 processing contracts](VX-03-PROCESSING-CONTRACTS.md)
- [VX-03 migration design](VX-03-MIGRATION-DESIGN.md)
- [VX-03 objective](../objectives/VX-03.md)

Designed:

- stable recording/source/artifact/run/attempt/transcript/unit/cluster/profile/correction/job IDs;
- original-audio microsecond timebase and honest precision;
- versioned envelopes, typed references, digests, provenance, privacy classes, and uncertainty;
- normalized prepared audio, timed transcription, diarization, identity, reconciliation, transcript version, correction, diagnostic, and provenance contracts;
- separate anonymous clusters, display names, and known/unknown/ambiguous identity;
- immutable verified/history semantics and append-only corrections;
- SwiftData control-plane, immutable artifact store, and regenerable-cache placement;
- durable pre-artifact ID assignment, lazy per-record adoption, dual-write, old-build compatibility, and no launch bulk migration;
- artifact → manifest commit → SwiftData projection ordering;
- pointer-authoritative `current` publication with `current.previous` fallback and no promotion of uncommitted manifests;
- corruption/unknown-version isolation, cleanup protection, low-disk behavior, recording deletion boundary, privacy, test matrix, and rollback.

Audit history:

1. Initial Auditor result: `DRIFT FOUND`.
2. Corrected four safety defects: durable identity recovery, commit/recovery contradiction, legacy Human-work replacement risk, and missing source-audio identity reuse.
3. Corrected one residual legacy compatibility label.
4. Final Auditor result: **`ALIGNED`**.

Independent QA:

- PASS for every agent-verifiable design/documentation criterion.
- `git diff --check`: PASS.
- Active/Phase 0 relative links: PASS.
- Strict concurrency and dependency pins: unchanged.
- Native source/test/project diff: empty.
- Private audio/application data/models/sibling writes: none.

Human gate:

Daniel must approve the nine principles in [VX-03 migration design §12](VX-03-MIGRATION-DESIGN.md#12-decisions-requiring-human-approval). This approval authorizes the design direction only; VX-04/VX-05 still require their own active objectives and risk workflows.

## Files added during Phase 0

- `docs/planning/objectives/VX-01.md`
- `docs/planning/objectives/VX-02.md`
- `docs/planning/objectives/VX-03.md`
- `docs/planning/evidence/VX-01-BASELINE.md`
- `docs/planning/evidence/VX-01-BENCHMARK-CHARTER.md`
- `docs/planning/evidence/VX-02-BOUNDARY-INVENTORY.md`
- `docs/planning/evidence/VX-03-PROCESSING-CONTRACTS.md`
- `docs/planning/evidence/VX-03-MIGRATION-DESIGN.md`
- `docs/planning/evidence/PHASE-0-CONSOLIDATED-REPORT.md`

## Existing governance/evidence files updated during Phase 0

- `OBJECTIVE.md`
- `PLAN.md`
- `DECISIONS.md`
- `QA.md`

No other pre-existing dirty file was edited during this Phase 0 run.

## Unresolved questions

Blocking the Phase 0 milestone:

1. Q-08: VX-02 disposition choices. Recommended safe answer: retain all candidates in place and defer cleanup.
2. Q-09: approve the nine VX-03 storage/migration principles.
3. Explicitly authorize VX-04 before Phase 1 begins.

Not blocking Phase 1 under the documented no-private-data/default behavior:

- Q-02: supported performance hardware target, needed for VX-12.
- Q-03: exact private recordings, needed before VX-08 uses any.
- Q-04: benchmark error priorities, needed for VX-09.

## Exact approval needed before Phase 1

Daniel may resolve the current gates conservatively with:

> I approve the nine VX-03 design principles. For VX-02, retain every candidate in place and defer all cleanup, movement, archival, audio use, and Mac/iOS project narrowing. I accept the Phase 0 milestone and authorize activation of VX-04 only.

Any different VX-02 disposition should name the exact candidate and action. Approval of Phase 0 does not authorize private-audio use, deletion, schema implementation, VX-05, model integration, or any later objective.
