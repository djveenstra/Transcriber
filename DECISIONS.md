# DECISIONS.md — Transcriber Architecture and Product Decisions

Last updated: 2026-07-29

This log records choices that are not obvious from the code or PRD. A decision remains in force until a later entry explicitly supersedes it.

Each entry states: decision, reason, implications, and reversibility.

## Active standing decisions

### D-001 · 2026-06-18 · Active implementation path

**Decision:** Product work in this repository targets `src/native/Transcriber2/`.

**Reason:** Multiple app and reference trees have existed, making wrong-tree edits a recurring risk.

**Implications:** `src/legacy-ios/` is reference-only; the Python app remains in `../Python Transcriber/`; iOS product work belongs in `../iOS Transcriber/`.

**Reversibility:** Workspace policy; changing it requires a Human-approved structural objective.

### D-002 · 2026-06-18 · `Recording` migration policy

**Decision:**

1. Prefer derived information over stored duplication.
2. Stored additions require safe defaults and old-record compatibility.
3. Blob changes require versioned decode with legacy fallback.
4. No `Recording` or artifact-format change ships without migration, round-trip, corrupt-data, interrupted-write, and rollback evidence.
5. Original audio is never migrated destructively.

**Reason:** `Recording` is SwiftData-backed and contains JSON `Data` fields. Uncontrolled changes can make existing work unreadable.

**Implications:** Storage objectives are Critical risk.

**Reversibility:** Additive formats and compatibility projections must permit rollback.

### D-003 · 2026-06-18 · Strict concurrency remains complete

**Decision:** Keep `SWIFT_STRICT_CONCURRENCY = complete`.

**Reason:** The pipeline is actor- and task-heavy; strict checking is an important regression alarm.

**Implications:** Fix isolation problems rather than weakening the setting.

**Reversibility:** Not intended to be reversed.

### D-004 · 2026-06-18 · Dependency and model updates are isolated objectives

**Decision:** Do not add or bump WhisperKit, FluidAudio, helper runtimes, model weights, or other processing dependencies inside an unrelated feature objective.

**Reason:** A dependency change can alter output, storage, resource use, licensing, packaging, and concurrency behavior at once.

**Implications:** Each update receives its own feasibility, benchmark, failure, and rollback evidence.

**Reversibility:** Pin restoration plus artifact compatibility must be tested.

### D-005 · 2026-06-18 · Current resource pacing is intentional

**Decision:** Preserve the inference semaphore, sequenced expensive model loads, post-unload pacing, and diarization attempt guards until Mac measurements prove a safer configuration.

**Reason:** These controls prevent resource contention, overlapping unsafe work, and stale results.

**Implications:** VoxBot’s desired parallel processing is a VX-12 experiment, not an assumption.

**Reversibility:** Any scheduler change must retain a sequential fallback.

### D-006 · 2026-06-18 · Automated baseline targets the Mac unit-test bundle

**Decision:** The standard automated test command uses `-only-testing:TranscriberTests`.

**Reason:** This is the established reliable unit-test baseline; UI and real-device behavior require separate scoped evidence.

**Implications:** A passing unit bundle does not prove microphone, model, UI, long-run, or packaging behavior.

**Reversibility:** Expand the baseline when the UI-test runner is intentionally made reliable.

### D-008 · 2026-06-23 · Transcript survives speaker-system failure

**Decision:** Diarization and identity are downstream, optional enrichments. A failure, timeout, cancellation, or ambiguous result must leave the transcript and audio usable.

**Reason:** Speaker quality is valuable but must not turn a successful transcription into total failure.

**Implications:** Every new diarizer and voiceprint engine preserves anonymous labels and retryable partial success.

**Reversibility:** Product safety policy; not intended to be reversed.

### D-011 · 2026-06-23 · Current Mac model baseline

**Decision:** The current Mac app uses WhisperKit transcription and FluidAudio Sortformer diarization. Mac Model Lab currently evaluates curated Whisper choices.

**Reason:** That is the implementation present in the working Mac app.

**Implications:** Parakeet on Mac, Pyannote, ERes2NetV2, ReDimNet2, and w2v-BERT are unintegrated candidates until their roadmap gates pass.

**Reversibility:** Superseded only by benchmark-backed objectives.

### D-018 · 2026-07-28 · Python app remains outside this repository

**Decision:** The former Python Transcriber and its generated output remain in `../Python Transcriber/`.

**Reason:** Native Mac development should not carry or accidentally rebuild the independent legacy Python product.

**Implications:** A future Pyannote or helper-runtime proposal must be designed as a new, isolated component; it must not copy the old Python application back into this repo.

**Reversibility:** Requires a Human-approved structural decision.

## Accuracy-expansion decisions

### D-019 · 2026-07-28 · This is now a Mac product roadmap

**Decision:** This checkout’s active PRD and roadmap are Mac-first. iOS requirements and implementation are owned by `../iOS Transcriber/`.

**Reason:** The workspace was split, but the root governance still described the completed iPhone-first Beta 2.0 roadmap.

**Implications:** Mac product needs no longer inherit mobile resource or navigation assumptions by default. Shared-code removal still requires an ownership audit.

**Reversibility:** Product/workspace decision; Daniel may later authorize a shared strategy.

### D-020 · 2026-07-28 · Strengthen the current application rather than rebuild it

**Decision:** Existing recording, import, storage, playback, review, export, retry, cancellation, diagnostics, Model Lab, actor protocols, and state-machine behavior are the baseline.

**Reason:** Code inspection and a green Mac build/test run show a substantial working core.

**Implications:** Architecture is improved through tested extraction and additive contracts. A new subsystem does not justify replacing unrelated working UI or data paths.

**Reversibility:** Foundational roadmap policy.

### D-021 · 2026-07-28 · VoxBot model names are candidates, not promises

**Decision:** Whisper Large v3, Parakeet TDT, Pyannote, ERes2NetV2, ReDimNet2, and w2v-BERT 2.0 must pass feasibility, license, package, privacy, resource, accuracy, and failure-isolation gates before production integration.

**Reason:** The current project ships only pinned WhisperKit and FluidAudio dependencies, and several proposed runtimes may not fit a sandboxed native Mac app without architectural consequences.

**Implications:** A feasibility objective may validly conclude “do not integrate.” The roadmap can ship the strongest simpler pipeline.

**Reversibility:** Individual model choices remain replaceable behind normalized contracts.

### D-022 · 2026-07-28 · Versioned artifacts supplement existing `Recording`

**Decision:** Raw model results, prepared audio, provenance, candidate transcripts, and future identity evidence should use an application-owned versioned artifact design. Existing `Recording` fields remain readable compatibility projections during migration.

**Reason:** Continually adding opaque blobs to one SwiftData model would make migrations, inspection, and reprocessing fragile.

**Implications:** VX-03 designs the format; VX-05 implements only after Human approval and migration tests.

**Reversibility:** Additive storage and legacy projections must support rollback.

### D-023 · 2026-07-28 · Open-set identity is mandatory if voiceprints ship

**Decision:** Voice identity returns `known`, `unknown`, or `ambiguous`. Nearest-neighbor ranking alone may not assign a person’s name.

**Reason:** A confident wrong name is more harmful than leaving a speaker unresolved.

**Implications:** False known-person identification is the primary voiceprint gate; calibration and best-versus-second-best separation are required.

**Reversibility:** Product safety policy; not intended to be reversed.

### D-024 · 2026-07-28 · AI cannot freely author transcript content

**Decision:** Any future AI adjudicator is limited to disputed regions and constrained outcomes: choose supported candidates, combine only with evidence, mark uncertainty, or request review.

**Reason:** Whole-transcript generative rewriting can create linguistically plausible dialogue unsupported by audio.

**Implications:** Off-device audio or text processing requires a separate privacy decision. Deterministic reconciliation and targeted reprocessing are built first.

**Reversibility:** The adjudicator is optional and removable.

### D-025 · 2026-07-28 · Governance rewrite does not activate implementation

**Decision:** The new PRD and PLAN authorize planning direction only. No VX objective is active until Daniel explicitly approves its start and `OBJECTIVE.md` is updated.

**Reason:** A roadmap should not silently become permission for dependency, schema, model, privacy, or removal work.

**Implications:** The next proposed scope is VX-01.

**Reversibility:** Daniel can activate an objective at any time.

### D-026 · 2026-07-28 · Planned removal requires proof

**Decision:** The roadmap may plan to remove superfluous code, targets, assets, or reference material, but execution requires an exact scoped objective, ownership proof, baseline validation, and rollback.

**Reason:** Daniel authorized planning for cleanup but explicitly did not authorize deleting application material during this governance pass.

**Implications:** VX-02 is an inventory and recommendation objective. Actual removals occur later.

**Reversibility:** Each removal must be independently reversible.

### D-027 · 2026-07-29 · Private benchmark handling charter

**Decision:** The private benchmark uses opaque tracked case metadata plus an untracked private source/ground-truth overlay. Audio remains outside Git and read-only. No recording is eligible until Daniel approves the exact source or an explicitly bounded collection and its permitted uses. Reports omit private paths, transcript text, names, embeddings, and audio by default.

**Reason:** VX-01 needs a reproducible evidence format without turning repository or personal recordings into assumed fixtures.

**Implications:** VX-08 implements the versioned manifest and validation contract in [VX-01-BENCHMARK-CHARTER.md](docs/planning/evidence/VX-01-BENCHMARK-CHARTER.md). VX-09 derives thresholds from approved data. Phase 0 accesses no private audio.

**Reversibility:** The manifest tooling and private overlay can be replaced behind a versioned import/export boundary; source audio is never modified.

### D-028 · 2026-07-29 · Phase 0 Human gates resolved conservatively

**Decision:** Retain every VX-02 candidate in place and defer all cleanup, movement, archival, audio use, and Mac/iOS project narrowing. Approve all nine VX-03 principles in `VX-03-MIGRATION-DESIGN.md §12`.

**Reason:** Daniel explicitly chose the conservative VX-02 disposition and approved the complete audited VX-03 design on 2026-07-29.

**Implications:** Q-08 and Q-09 are resolved. No VX-02 cleanup is authorized. Phase 0 passes, and the approved storage principles govern VX-05 and later compatible work. Daniel separately authorized sequential activation and execution of VX-04 through VX-07 without another between-objective start request.

**Reversibility:** Cleanup remains deferred and can be reconsidered only through a future exact objective. A change to the VX-03 principles requires a new Human-approved design decision and compatibility analysis.

### D-029 · 2026-07-29 · Phase 1 closes without activating Phase 2

**Decision:** VX-04, VX-05, VX-06, and VX-07 each close at `PROCEED` after their prescribed audit, QA, validation, and Manager gates. Phase 2 and VX-08 remain inactive.

**Reason:** The four objectives met their acceptance criteria while preserving current production behavior and the repository invariants. Daniel explicitly authorized the continuous Phase 1 run but explicitly prohibited beginning Phase 2.

**Implications:** The new artifact store and audio-preparation service remain dormant. No benchmark dataset, private-audio use, new model, dependency, or production-pipeline adoption begins until a new Human authorization activates VX-08 and any private-data permission is separately resolved.

**Reversibility:** Each Phase 1 objective has an independent rollback. The roadmap may proceed only through a future explicit VX-08 activation.

## Historical decisions

The completed Beta 2.0 objective files and the `beta-2.0-complete` Git tag preserve the detailed pre-split record. Earlier decisions about iOS primary tabs, iPhone preload, device validation, and the original OBJ-01…20 sequence are historical in this Mac workspace; they do not override D-019 or the new PRD.

## Open Human decisions

These questions are intentionally deferred to the objective that can provide evidence:

| ID | Decision | Needed by |
|---|---|---|
| Q-01 | Keep the app name Transcriber or adopt VoxBot branding? | Before release/packaging UI work |
| Q-02 | What Apple Silicon Mac and memory configuration define the supported performance target? | VX-01 / VX-12 |
| Q-03 | Which private recordings, if any, may become benchmark references? | VX-01 / VX-08 |
| Q-04 | Which benchmark errors matter most when trade-offs conflict? | VX-09 |
| Q-05 | May an alternative diarizer use a signed helper process or Python-derived runtime? | VX-15 |
| Q-06 | What protection and retention policy should speaker profiles and enrollment audio use? | VX-17 |
| Q-07 | May disputed audio or transcript text ever be sent to an optional network adjudicator? | VX-24 |

### VX-02 decision detail — 2026-07-29

Q-08 and Q-09 were resolved by D-028. The retained detail remains in [VX-02-BOUNDARY-INVENTORY.md](docs/planning/evidence/VX-02-BOUNDARY-INVENTORY.md), [VX-03-PROCESSING-CONTRACTS.md](docs/planning/evidence/VX-03-PROCESSING-CONTRACTS.md), and [VX-03-MIGRATION-DESIGN.md](docs/planning/evidence/VX-03-MIGRATION-DESIGN.md). No cleanup, movement, archival, audio use, or project narrowing was authorized.
