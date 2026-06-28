# DECISIONS.md — Architecture & Product Decision Log

_Append-only log of non-obvious decisions, with rationale. The Manager records a decision here whenever a choice isn't self-evident from the code or PRD. Newest at the bottom of each section. See [docs/planning/](docs/planning/)._

Format per entry: **ID · Date · Decision · Why · Implications · Reversibility.**

---

## Standing policies

### D-001 · 2026-06-18 · Active development path is `src/native/Transcriber2/` only
**Why:** Three iOS-ish trees exist (`native/Transcriber2`, `legacy-ios`, stale `XCode App Build/`) plus the independent Python app. Editing the wrong one is a real risk (RISK R20).
**Implications:** Agents never modify `src/python/`; `src/legacy-ios/` and `XCode App Build/` are read-only reference. The Auditor checks touched paths.
**Reversibility:** Policy only.

### D-002 · 2026-06-18 · SwiftData migration policy for `Recording`
**Why:** Transcript/raw/speaker data are JSON blobs inside a SwiftData `@Model`; uncontrolled schema changes can lose beta data (RISK R2).
**Policy:**
1. Prefer **deriving** new info over storing it (e.g. `RecordingStatus` computed from existing flags).
2. If a stored field is required, it must be **additive with a safe default** so old rows decode.
3. Blob shape changes require a **versioned decode path** (try new, fall back to old) — never a destructive re-encode.
4. **No `Recording` schema change without a DECISIONS.md entry** describing the migration and a round-trip test.
**Implications:** Gates OBJ-09 (if `RecordingStatus` is stored rather than derived), OBJ-12, and OBJ-15 schema work.
**Reversibility:** Additive changes keep old code able to read data after a revert.

### D-003 · 2026-06-18 · Keep `SWIFT_STRICT_CONCURRENCY = complete`
**Why:** The pipeline is concurrency-heavy; strict checking is the canonical drift/regression alarm (RISK R7).
**Implications:** Never weaken the setting to compile; fix the concurrency issue instead.
**Reversibility:** N/A (do not change).

### D-004 · 2026-06-18 · Dependencies (WhisperKit, FluidAudio) are not bumped inside feature objectives
**Why:** Pinned by revision; a bump can change behavior or break the build (RISK R22).
**Implications:** Any bump is its own objective with full re-validation.
**Reversibility:** Revert the pin.

### D-005 · 2026-06-18 · Deliberate pipeline pacing is intentional
**Why:** The 1-second post-unload sleeps, the inference semaphore, sequenced (non-parallel) model loads, and the share-sheet scene-phase workaround are deliberate and commented in code; removing them risks GPU/ANE contention, OOM, or a stuck share sheet.
**Implications:** Do not remove/optimize these without on-device measurement; objectives touching the pipeline restate this.
**Reversibility:** Changes require measurement evidence before merge.

### D-006 · 2026-06-18 · Agent baseline test command targets the unit-test bundle
**Why:** The generated `Transcriber` scheme also attempts to launch `TranscriberUITests` on macOS, and that runner exited before bootstrapping during OBJ-01. The agent-verifiable baseline for every objective is the `TranscriberTests` unit-test bundle; UI workflows remain covered by scoped manual QA or later objective-specific UI tests.
**Implications:** Baseline test commands include `-only-testing:TranscriberTests`. UI-test runner failures are documented as QA evidence, not worked around by modifying the Xcode project in OBJ-01.
**Reversibility:** Remove the filter once the scheme/UI-test runner is intentionally configured and validated.

### D-007 · 2026-06-20 · iOS primary tabs are Dashboard, Library, Model Lab, Settings
**Why:** PRD §6 defines four primary tabs, and OBJ-11's Human Reviewer instruction confirmed Record should remain prominent as a Dashboard action instead of staying in the tab bar.
**Implications:** Dashboard owns the prominent Record/Import entry points; iOS Model Lab is a top-level tab; Settings may keep a secondary Model Lab link. Removing the Record tab is acceptable only while the Dashboard-triggered recording/import flow remains available.
**Reversibility:** Tab promotion and Dashboard-triggered Record/Import routing are UI-level changes and can be reverted without schema or data migration.

### D-008 · 2026-06-23 · Diarization and audio-pipeline guardrails before Mac parity
**Why:** Human Reviewer device testing accepted OBJ-17 playback/accessibility but did not accept speaker-label reliability. The app must remain useful when diarization is slow, canceled, times out, or fails.
**Decision:** Off-device/server diarization, pyannote, sherpa-onnx, and any new dependencies are investigation options only until the Human Reviewer explicitly approves them. The beta must preserve transcript availability and safe failure even if speaker labeling is imperfect. The M4A playback derivative is accepted as a cache/regenerable playback artifact, not the canonical source of truth. Background/locked-screen recording is mandatory for the product.
**Implications:** OBJ-17.1 stabilizes the current FluidAudio/Sortformer path first: diagnostics, timeout, cancellation, transcript preservation, playback preservation, retry safety, and overlapping-attempt protection. Future local/on-device alternatives may be researched, but not implemented without a scoped approval. Original/master audio remains preserved, and cache derivatives can be regenerated.
**Reversibility:** Policy/documentation only. Any future engine, dependency, or pipeline replacement requires its own approved objective and validation.

### D-009 · 2026-06-23 · Launch preload is approved for the default transcription model only
**Why:** The app should feel ready and intentional at launch, but model preparation must not trap the user or block core workflows.
**Decision:** OBJ-17.2 may add a skippable launch/readiness flow that begins preparing the default/Base English transcription model when the app opens. If the user skips, the app must enter Dashboard/Home and continue loading the transcription model in the background. Transcription model readiness must be visible, retryable on failure, and must not block recording, Library access, playback, or basic navigation. Diarization/FluidAudio preload is not approved yet.
**Implications:** OBJ-17.2 is limited to default transcription model readiness/preload and related status surfaces. Any diarization warmup, FluidAudio resource preload, new dependency, server/off-device processing, model-change/rerun backlog, or delete-downloaded-models backlog requires a separate approved objective.
**Reversibility:** Planning/product decision only until OBJ-17.2 implementation begins. Runtime changes must remain narrow and reversible when implemented.

### D-010 · 2026-06-23 · Finish original 20 objectives before new 17.x feature objectives
**Why:** The Human Reviewer accepted OBJ-17.1 and wants to finish the original 20 stated objectives before returning to a future feature/fine-tuning phase.
**Decision:** Launch readiness/default model preload, Skip loading with background preload, rerun transcription with a different model from transcript/detail, delete downloaded models, further speaker-turn/player polish, broader diarization engine evaluation, background processing/job architecture, and diarization resource/model preload are deferred backlog items only. Do not create active OBJ-17.2 or OBJ-17.3 objective files right now. OBJ-18 Mac companion parity is the next active original objective.
**Implications:** D-009 remains a product-direction note for a future phase, but it is no longer active sequencing before OBJ-18. Any future preload, model-rerun, model-delete, diarization-warmup, or broader engine/job work requires explicit Human approval and its own active objective.
**Reversibility:** Planning/product decision only. No runtime behavior changes are implied.

### D-011 · 2026-06-23 · Mac companion Model Lab is Whisper-only
**Why:** WhisperKit and the existing Model Lab import, comparison, diagnostics, and report-sharing paths are available on macOS. The Parakeet final-transcription implementation remains intentionally iOS-only.
**Decision:** Mac uses the established Dashboard, Library, Model Lab, and Settings structure. Model Lab is enabled on Mac for the curated Whisper models only. Parakeet model comparison and the Share to Transcriber extension remain iOS-only; Mac uses the in-app file importer and system share controls instead.
**Implications:** Mac remains a companion rather than a separate redesign. Import, transcription, playback, transcript review, TXT/SRT/JSON export, status badges, diagnostics, and progress UI reuse the shared app paths. Platform-specific model and share-extension gaps are visible and documented.
**Reversibility:** UI availability and filtering only; reverting restores the prior iOS-only Model Lab without data or schema migration.

### D-012 · 2026-06-23 · OBJ-18 Mac launch readiness is narrow and ordered
**Why:** Human Mac review found that Live Preview could reach recording before its Whisper resources had ever been prepared.
**Decision:** On Mac, launch begins a non-blocking Whisper preparation attempt for Live Preview first. After Live Preview preparation succeeds, the existing default/Base English model preload is scheduled. A failed Live Preview preparation remains visible and retryable without racing lower-priority model work. Recording, navigation, Library, and playback remain available throughout. FluidAudio/Sortformer resources are not preloaded in this pass because the current pipeline deliberately sequences transcription and diarization model loads to avoid GPU/ANE contention.
**Implications:** This is not the deferred launch readiness screen: there is no launch gate, progress screen, or Skip Loading flow. iOS keeps its existing preload behavior. Diarization preparation remains on demand until a separately approved design can preserve the pipeline pacing guardrails.
**Reversibility:** The coordinator and Mac launch hook are additive and can be reverted without changing stored data, model caches, or dependencies.

### D-013 · 2026-06-25 · Accept a limited Mac companion baseline and return focus to mobile
**Why:** Agent validation established a useful Mac companion baseline, while exhaustive Mac GUI validation and further polish would delay the remaining original mobile-first beta objectives.
**Decision:** OBJ-18 is accepted as a limited Mac companion baseline. Further Mac GUI validation/polish is deferred until after the original 20 objectives or a future fine-tuning phase. The mobile app remains the primary product and beta target.
**Implications:** This acceptance does not claim exhaustive Human verification of Mac parity. Existing intentional Mac gaps remain documented, no additional Mac feature work is implied, and OBJ-19 may proceed without completing the deferred Mac checklist.
**Reversibility:** Planning/product priority decision only. Future Mac validation or polish requires an explicitly approved scope.

### D-014 · 2026-06-25 · OBJ-20 is beta acceptance and final QA only
**Why:** The Human Reviewer wants the final original objective to establish release truth before any new feature, refactor, or fine-tuning work begins.
**Decision:** OBJ-20 verifies the original beta objectives, runs the agent acceptance suite, documents known limitations, and produces the final Human-owned iPhone checklist. The previously drafted `TranscriptionSession` decomposition, language picker, and speaker-color parsing change are removed from active OBJ-20 scope. Launch readiness/default-model preload UI, model rerun, delete-downloaded-models, new diarization engines, broader Mac polish, and all other feature/fine-tuning work remain deferred.
**Implications:** No production code, dependency, schema, playback/M4A, engine, server/cloud, or off-device change is authorized by OBJ-20 unless a narrow fix is required for a directly observed beta blocker. Any such blocker that requires product choice or broader feature scope returns `ASK USER` before implementation.
**Reversibility:** Planning/product decision only. Deferred work may be reconsidered after the original beta milestone is closed through a separately approved objective.

### D-015 · 2026-06-27 · Run a narrow Mac acceptance-hardening pass before final iPhone QA
**Why:** The Human Reviewer wants confidence that the accepted Mac companion baseline is usable enough before completing the final iPhone checklist.
**Decision:** Reopen OBJ-20 agent work only to run and inspect the Mac app and fix narrow blockers to basic companion usability. This does not authorize a Mac redesign, deferred features, a new feature/fine-tuning phase, dependency or schema changes, or changes to accepted playback/M4A behavior.
**Implications:** Launch, navigation, safe recording/live-preview dismissal, readiness messaging/retry, import persistence, Library/detail usability, playback, transcript review, export/share, and cancel/failure recovery may receive small reversible fixes. Any broader or product-dependent finding returns `ASK USER`.
**Reversibility:** The decision is planning-only; any resulting narrow code fix must remain independently revertible.

### D-016 · 2026-06-28 · Accept Beta 2.0 and preserve Beta 2.1 planning backlog
**Why:** The Human Reviewer passed final OBJ-20 acceptance and considers the original 20-objective build acceptable. Remaining issues are polish, feature additions, and deeper fine-tuning rather than Beta 2.0 blockers.
**Decision:** Close OBJ-20 and the original Beta 2.0 roadmap. Preserve for Beta 2.1 discussion: a launch readiness screen and default-model preload; possible priority loading of Live Preview first, transcription model second, and diarization resources third; Skip Loading with continued background loading; rerun transcription with a different model; delete downloaded models; further speaker grouping polish; further sticky/compact player and header polish; broader diarization-engine evaluation if FluidAudio becomes limiting; deeper Mac GUI QA and polish; background processing/job architecture improvements; and broader UI polish and feature fine-tuning.
**Implications:** None of these deferred items is a Beta 2.0 blocker or an active implementation objective. Their exact scope, ordering, and architecture require future Human-approved Beta 2.1 planning. No new dependency, engine, server/cloud/off-device processing, schema change, or implementation branch is authorized by this decision.
**Reversibility:** Planning and milestone acceptance only; no runtime behavior changes are implied.

---

## Decisions awaiting the Human Reviewer (open questions)

- **Q-1 (OBJ-01):** Archive the stale `XCode App Build/` template tree? (Proposal only; needs approval before any move.)
- **Q-3 (OBJ-03):** If model sizes aren't exposed by WhisperKit/FluidAudio, approve a static size table.
- **Q-4 (OBJ-02):** If WhisperKit's on-disk cache path isn't reliably discoverable, approve a loadability-probe approach for readiness.

_The Manager moves each answered question into a numbered D-### decision._
