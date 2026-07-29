# PLAN.md — Transcriber Mac Accuracy Roadmap

Last updated: 2026-07-28

Read with [PRD.md](PRD.md), [OBJECTIVE.md](OBJECTIVE.md), [AGENTS.md](AGENTS.md), and [DECISIONS.md](DECISIONS.md).

## 1. Mission

Evolve the existing Transcriber Mac app into an accuracy-first, locally processed transcription system using the ideas in [VoxBot Expanded PLN.md](VoxBot%20Expanded%20PLN.md), without rebuilding working recording, storage, playback, review, export, retry, diagnostics, or Model Lab foundations.

This plan deliberately separates:

1. Proving what exists.
2. Creating stable contracts and storage.
3. Measuring the current baseline.
4. Testing proposed models and runtimes.
5. Integrating only the candidates that earn their place.
6. Hardening the resulting product.

That sequencing prevents a speculative model choice from forcing a rewrite of the application around it.

## 2. Current starting point

The active app is `src/native/Transcriber2/`. On 2026-07-28, before this governance rewrite:

- The Mac target built successfully with strict concurrency enabled.
- The `TranscriberTests` unit-test bundle passed.
- The project resolved pinned WhisperKit and FluidAudio revisions.
- The app already contained actor-based engine seams, a guarded `TranscriptionSession`, SwiftData recording persistence, original-audio storage, transcript-first processing, retry/cancel/failure recovery, speaker reassignment, export, diagnostics, and Model Lab.

The current implementation is therefore the regression baseline, not disposable prototype code.

## 3. Non-negotiable delivery rules

1. Preserve original audio, existing recordings, confirmed transcripts, and corrections.
2. Keep the app usable at the end of every objective.
3. Make additive, versioned storage changes with migration and corruption tests.
4. Preserve `SWIFT_STRICT_CONCURRENCY = complete`.
5. Keep expensive model work serial until measurements prove a safe concurrent configuration.
6. Treat every new dependency, model runtime, schema migration, and pipeline replacement as High or Critical risk.
7. Do not make a named VoxBot candidate the default until it beats the appropriate baseline on representative data.
8. Keep draft transcription available when downstream accuracy or speaker work fails.
9. One active implementation objective at a time.
10. Plan removals explicitly; execute them only inside a scoped objective with proof that the replacement or sibling workspace owns the removed behavior.

## 4. Standard validation

Run from the repository root for every code objective:

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

Each objective adds focused tests and QA appropriate to its risk. Model-quality claims require benchmark evidence; packaging, microphone, long-run, memory-pressure, accessibility, and real-audio behavior require Human acceptance where automation is insufficient.

## 5. Objective format

Each objective file must declare:

- Mission and user outcome.
- Risk tier.
- Dependencies.
- Allowed and forbidden paths.
- Current behavior that must remain unchanged.
- In scope and out of scope.
- Implementation tasks.
- Data/migration impact.
- Validation and benchmark commands.
- Acceptance criteria.
- Rollback plan.
- Worker report, Auditor result when required, QA evidence, and Manager gate.

The canonical gates are `PROCEED`, `FIX FIRST`, `ASK USER`, and `BLOCKED` as defined in [AGENTS.md](AGENTS.md).

---

## Phase 0 — Establish truth and safe boundaries

### VX-01 — Mac baseline and benchmark charter

**Status (2026-07-29):** `PROCEED`. Baseline and benchmark charter recorded in `docs/planning/evidence/`; Mac build passed and 164/164 tests passed. Exact private recordings and production thresholds remain unapproved.

**Purpose:** Turn the current app into an explicit, reproducible baseline before changing the processing architecture.

**Work:**

- Record current build, tests, app flows, model/runtime revisions, storage locations, and representative resource use.
- Define the private benchmark dataset format, ground-truth rules, privacy handling, and metric calculations.
- Select benchmark categories without inventing pass thresholds.
- Identify which existing recordings may be used only after Daniel approves them.

**Preserves:** All production behavior.

**Gate:** `PROCEED` only when the baseline can be rerun and private test data handling is approved.

### VX-02 — Mac-only boundary and removal inventory

**Status (2026-07-29):** `ASK USER`. Read-only inventory is complete in `docs/planning/evidence/VX-02-BOUNDARY-INVENTORY.md`; no removal occurred. Sibling ownership, project narrowing, shared-inbox behavior, legacy/stale-tree preservation, build artifact, root audio, and visual-reference dispositions remain Human decisions.

**Purpose:** Remove ambiguity before removing code.

**Work:**

- Verify that `../iOS Transcriber/` owns the iOS product and contains every iOS behavior that may be removed from this checkout.
- Inventory iOS-only targets, share-extension files, `#if os(iOS)` branches, mobile-only model code, legacy reference trees, stale assets, duplicate governance, and root audio fixtures.
- Classify each item as retain, move to sibling, archive, remove later, or unresolved.
- Propose mechanical removal objectives; do not remove application files in VX-02.

**Candidate future removals, subject to proof:**

- The iOS Share to Transcriber target and plist/entitlements from the Mac workspace.
- iOS-only Parakeet live-preview and audio-session branches already owned by the sibling workspace.
- `src/legacy-ios/` after its unique reference value is confirmed elsewhere.
- Redundant or historical planning material after links and evidence are preserved.
- Test or personal audio at repository root after Daniel identifies it.

**Gate:** `ASK USER` for every unresolved ownership or deletion choice.

### VX-03 — Versioned processing contracts and migration design

**Status (2026-07-29):** `ASK USER`. Contracts and migration design are complete, final Auditor result is `ALIGNED`, and agent QA is PASS. Human approval of the nine data/model migration principles remains required; no schema or production change occurred.

**Purpose:** Define how future engines connect without changing production behavior yet.

**Work:**

- Specify normalized contracts for prepared audio, timed transcription, diarization, speaker identity, reconciliation, corrections, diagnostics, and provenance.
- Define stable identifiers and schema versions.
- Decide which data belongs in SwiftData, an artifact store, or regenerable cache.
- Design old-record compatibility, additive migrations, atomic writes, corruption handling, cleanup, and rollback.
- Define draft, verified, and historical transcript-version semantics.

**Gate:** Human approval of the data model and migration strategy before code changes.

**Phase 0 milestone:** The current app is reproducible, data ownership is clear, and future processing has approved contracts. No model integration begins before this milestone passes.

**Milestone status (2026-07-29):** `ASK USER`. VX-01 is `PROCEED`; VX-02 inventory is complete at `ASK USER`; VX-03 is aligned and QA-green at `ASK USER`. Phase 1 is not active.

---

## Phase 1 — Strengthen the existing core

### VX-04 — Extract orchestration seams from `TranscriptionSession`

**Purpose:** Reduce risk in the current 1,900-line session coordinator without changing user behavior.

**Work:**

- Characterize the existing state machine and persistence checkpoints with tests.
- Extract small services for final transcription, diarization attempts, and persistence coordination behind protocols.
- Keep `TranscriptionSession` as the UI-facing state owner during the transition.
- Preserve cancellation, stale-attempt protection, timeouts, fallback, and transcript-first behavior.

**Not allowed:** A rewrite, new models, new product states, or storage migration.

### VX-05 — Processing artifact store

**Purpose:** Add versioned, inspectable processing artifacts without bloating or destructively rewriting `Recording`.

**Work:**

- Implement the approved VX-03 store and manifest format.
- Add atomic writes, checksums where useful, versioned decode, corruption isolation, and cleanup rules.
- Preserve existing `Recording` fields as compatibility projections.
- Add round-trip, legacy-read, corrupt-data, interrupted-write, and rollback tests.

### VX-06 — Persistent processing jobs and relaunch recovery

**Purpose:** Let the Mac resume or safely retry work after relaunch while keeping partial results honest.

**Work:**

- Persist stage state and completed artifact references.
- Reconcile interrupted jobs on launch.
- Never infer completion from an in-memory flag.
- Prevent an older attempt from overwriting a correction or newer attempt.
- Expose retry, cancel, and partial-success states through existing UI patterns.

### VX-07 — Versioned audio preparation and quality analysis

**Purpose:** Create consistent model input while preserving the source.

**Work:**

- Generate versioned mono 16 kHz working audio without replacing the original.
- Retain original channel metadata.
- Add measured duration, clipping, silence/speech activity, level, and initially reliable quality signals.
- Treat denoising/source separation as optional later experiments.
- Add deterministic derivative naming, invalidation, cleanup, and reproducibility tests.

**Phase 1 milestone:** The existing app behaves the same, but processing is modular, recoverable, and able to store comparable versioned results.

---

## Phase 2 — Make Model Lab the evidence system

### VX-08 — Benchmark dataset and ground-truth workflow

**Purpose:** Create the evidence needed to make accuracy decisions.

**Work:**

- Add private dataset manifests that reference, but do not commit, private audio.
- Support ground-truth words, speaker regions, enrolled/unenrolled identity, recording condition, and correction provenance.
- Implement metric calculations and reproducible report export.
- Include quiet, noisy, far-field, vehicle, television, reverberant, speakerphone, overlapping, short-reply, names, technical vocabulary, and compressed-audio cases.

### VX-09 — Measure the current production baseline

**Purpose:** Establish the number every proposed change must beat.

**Work:**

- Run current WhisperKit transcription, FluidAudio Sortformer diarization, and `TranscriptMerger`.
- Capture word accuracy, speaker accuracy, review burden, failures, processing time, and memory.
- Record known limitations without “fixing while measuring.”
- Select Human-approved thresholds and priorities from the observed dataset.

**Phase 2 milestone:** Accuracy and reliability are measurable, and production thresholds are evidence-based.

---

## Phase 3 — Multi-engine transcription and consensus

### VX-10 — High-accuracy Whisper candidate

**Purpose:** Evaluate an accuracy-focused Whisper configuration, including Large v3 if it is practical.

**Work:**

- Add a provider adapter that emits VX-03 normalized results and retains raw output.
- Validate download size, loadability, memory, speed, licensing, packaging, cancellation, and failure recovery.
- Compare it with the current selected Whisper baseline.

**Gate:** The candidate remains Model-Lab-only unless its benefit justifies its resource cost.

### VX-11 — Mac Parakeet feasibility and candidate integration

**Purpose:** Determine whether Parakeet provides an independent, useful Mac transcript candidate.

**Work:**

- First test the capabilities already present through pinned FluidAudio.
- Do not assume the iOS-only `ParakeetFinalTranscriptionEngine` can be enabled unchanged on macOS.
- Validate word timing, raw output, model storage, cancellation, memory, licensing, and packaging.
- Integrate behind the normalized contract only after feasibility passes.

**Gate:** `BLOCKED` or a different engine candidate is acceptable if Parakeet is not production-safe on Mac.

### VX-12 — Resource-aware scheduler and concurrency experiment

**Purpose:** Replace inherited serialization only when the Mac can run work concurrently without becoming less reliable.

**Work:**

- Measure sequential, limited-parallel, and proposed CPU/GPU/Neural Engine arrangements.
- Observe peak unified memory, pressure, thermal behavior, model load contention, cancellation, and total time.
- Implement concurrency limits and safe fallback to sequential execution.

**Gate:** Sequential execution remains the production default unless measured parallel execution is stable on the supported hardware.

### VX-13 — Deterministic transcript alignment and consensus

**Purpose:** Produce a better transcript from independent evidence without allowing free-form rewriting.

**Work:**

- Align timed units from two candidates.
- Record agreement, formatting differences, insertions, deletions, substitutions, and unaligned regions.
- Implement conservative consensus rules.
- Preserve both candidates and each decision.
- Compare consensus with the best individual model.

**Gate:** Consensus ships only if it improves the approved accuracy metrics without unacceptable hallucination or review burden.

**Phase 3 milestone:** Transcriber can produce a versioned draft plus an evidence-backed reconciled transcript when the ensemble is beneficial.

---

## Phase 4 — Speaker-attribution foundation

### VX-14 — Current diarization baseline and richer contract

**Purpose:** Strengthen the working FluidAudio path before replacing it.

**Work:**

- Persist raw Sortformer output, cluster timelines, stage diagnostics, and available overlap/quality evidence.
- Measure diarization error, attributed-word accuracy, fragmentation, merges, speaker count, and timeouts.
- Keep current fallback, cancellation, and transcript preservation intact.

### VX-15 — Alternative diarization feasibility gate

**Purpose:** Evaluate Pyannote or another local Mac candidate without coupling the app to an unproven runtime.

**Work before integration:**

- Review model and dependency licenses.
- Prove Apple Silicon runtime, sandbox compatibility, packaging, offline behavior, memory use, cancellation, and data flow.
- Compare quality with the improved current baseline.
- Decide whether a helper process is acceptable and how it is authenticated, versioned, recovered, and removed.

**Gate:** Human architecture approval is required before adding Python, a helper executable, a server process, or a new diarization dependency.

### VX-16 — Speaker-attributed reconciliation

**Purpose:** Combine transcript timing and diarization evidence while preserving temporary cluster truth.

**Work:**

- Attach words to temporary clusters through explicit, tested rules.
- Preserve overlaps and unresolved assignments instead of smoothing away all uncertainty.
- Store anonymous cluster labels separately from display names and future identities.
- Surface conflicts and low-quality regions for review.

**Phase 4 milestone:** Anonymous speaker attribution is versioned, measurable, reviewable, and independent of person identification.

---

## Phase 5 — Known-speaker identification

### VX-17 — Speaker profiles, enrollment, privacy, and deletion

**Purpose:** Build the user-owned data foundation before selecting an identity model.

**Work:**

- Add stable profile IDs, display names, approved enrollment samples, quality metadata, and version metadata.
- Require multiple suitable samples and explicit enrollment.
- Define export, deletion, retained-audio, cache, and migration behavior.
- Keep profile data local and clearly state that voiceprints are not authentication.

### VX-18 — Primary voiceprint candidate and open-set decision

**Purpose:** Prove one local embedding model and conservative known/unknown/ambiguous behavior.

**Work:**

- Evaluate ERes2NetV2 or the strongest feasible candidate against the approved contract.
- Extract only suitable diarized speech.
- Retain per-sample embeddings rather than prematurely averaging them.
- Calibrate absolute acceptance and best-versus-second-best separation.
- Aggregate evidence across turns.

**Gate:** False known-person identification is the primary blocker. A high unknown rate is acceptable when it reduces wrong names.

### VX-19 — Independent second model and calibrated fusion

**Purpose:** Add ReDimNet2 or another independent candidate only if it improves identity reliability.

**Work:**

- Calibrate each model separately.
- Fuse calibrated evidence with transparent features such as duration, quality, margin, and agreement.
- Detect contradictory cluster evidence and send it to review rather than silently renaming.

### VX-20 — Difficult-case voiceprint fallback

**Purpose:** Test w2v-BERT 2.0 or another costly fallback only on selected ambiguous cases.

**Work:**

- Define escalation conditions.
- Measure accuracy gained, false identification, processing time, memory, and cache behavior.
- Remove or leave the fallback out if it provides no material benefit.

**Phase 5 milestone:** If benchmarks justify shipping it, speaker identity returns known, unknown, or ambiguous results with calibrated evidence and user-controlled profiles.

---

## Phase 6 — Review, correction, and controlled learning

### VX-21 — Uncertainty-focused transcript review

**Purpose:** Let the user spend time where the systems disagree or lack evidence.

**Work:**

- Surface disputed words, poor audio, overlaps, unresolved names, ambiguous identity, and cluster conflicts.
- Add transcript text editing and candidate confirmation/rejection.
- Preserve correction history and verified transcript versions.

### VX-22 — Speaker correction and reprocessing

**Purpose:** Extend existing rename/reassignment into complete reconciliation controls.

**Work:**

- Merge and split temporary clusters.
- Confirm or reject identity suggestions.
- Reprocess selected regions or the full recording.
- Offer confirmed clean speech for enrollment only through an explicit approval step.
- Convert corrections into private benchmark evidence without uncontrolled retraining.

**Phase 6 milestone:** The user can understand and correct every material transcript and speaker decision.

---

## Phase 7 — Difficult-region processing and optional AI

### VX-23 — Targeted disputed-region reprocessing

**Purpose:** Spend extra compute only where it may improve the result.

**Work:**

- Extract context windows around disagreements.
- Test alternate decoding, longer context, and approved audio derivatives.
- Store each attempt and result without changing accepted text until a decision is made.

### VX-24 — Constrained adjudication gate

**Purpose:** Decide whether an AI adjudicator adds accuracy without becoming a transcript author.

**Required Human decisions:**

- Entirely local versus optional network service.
- Privacy and retention rules.
- Approved provider/model and cost limits if networked.
- Whether audio clips may leave the Mac.

**If approved:**

- Give the adjudicator a disputed clip, existing candidates, accepted context, timing, and vocabulary.
- Restrict output to selecting candidates, supported combinations, uncertainty, or human review.
- Benchmark against deterministic and targeted-reprocessing baselines.

**Gate:** Do not ship if it increases hallucination, hides provenance, or fails privacy requirements.

---

## Phase 8 — Production hardening

### VX-25 — Recovery, privacy, packaging, and licensing

**Purpose:** Turn the selected pipeline into a durable Mac product.

**Work:**

- Stress cancellation, relaunch, partial results, corruption, low disk, memory pressure, and model failure.
- Complete profile protection, export, and deletion verification.
- Complete dependency/model license review.
- Validate model download, update, repair, removal, app sandbox, signing, notarization, and installation.
- Remove only components proven superfluous by VX-02 and later decisions.

### VX-26 — Final regression benchmark and Human acceptance

**Purpose:** Decide whether the accuracy expansion is production-ready.

**Work:**

- Run the full private benchmark and compare every production stage with the VX-09 baseline.
- Confirm no optional stage is retained without measurable benefit.
- Run migration and backward-compatibility tests against existing recordings.
- Complete real-audio, long-run, resource-pressure, accessibility, privacy, and release checklists.
- Document limitations and choose the default pipeline.

**Gate:** `PROCEED` only with green automated evidence, approved benchmark results, and Human acceptance.

---

## 6. Dependency summary

```text
VX-01 -> VX-08 -> VX-09 ------------------------------+
   |                                                   |
   +-> VX-03 -> VX-04 -> VX-05 -> VX-06 -> VX-07 -----+
                                                        |
VX-02 --------------------------------------------------+-> approved removals in VX-25

VX-07 + VX-09 -> VX-10 -> VX-11 -> VX-12 -> VX-13
VX-09 --------> VX-14 -> VX-15 -> VX-16
VX-03 + VX-16 -> VX-17 -> VX-18 -> VX-19 -> VX-20
VX-13 + VX-16 + VX-20 -> VX-21 -> VX-22
VX-13 + VX-21 -> VX-23 -> VX-24
all selected production objectives -> VX-25 -> VX-26
```

VX-10 and VX-11 may be evaluated independently. VX-15 may conclude that the current FluidAudio path remains best. VX-19, VX-20, and VX-24 are optional: failing their benefit gates does not block a production release built from the strongest simpler pipeline.

## 7. Planned removals are not implementation permission

This plan explicitly permits future objectives to remove code or files that have become superfluous. Every such objective must:

1. Identify the exact target.
2. Prove that no active Mac behavior or user data depends on it.
3. Confirm whether the sibling iOS workspace owns it.
4. Preserve useful history or unique reference material.
5. Run the baseline before and after removal.
6. Include a simple rollback.

Original audio, user transcripts, corrections, speaker profiles, and enrollment samples are never “cleanup.”

## 8. Plan change policy

The Manager may record completion evidence, discovered dependencies, or risk changes without changing product scope. Adding, removing, reordering, or materially widening objectives requires Daniel’s approval.

The next implementation objective is not active merely because it appears here. [OBJECTIVE.md](OBJECTIVE.md) must explicitly activate it after Daniel approves the start.
