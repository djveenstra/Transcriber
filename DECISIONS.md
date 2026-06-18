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

---

## Decisions awaiting the Human Reviewer (open questions)

- **Q-1 (OBJ-01):** Archive the stale `XCode App Build/` template tree? (Proposal only; needs approval before any move.)
- **Q-2 (OBJ-10):** Does "Record" remain its own tab, or become a Dashboard action, once the Dashboard exists (PRD §6 lists four tabs: Dashboard, Library, Model Lab, Settings)?
- **Q-3 (OBJ-03):** If model sizes aren't exposed by WhisperKit/FluidAudio, approve a static size table.
- **Q-4 (OBJ-02):** If WhisperKit's on-disk cache path isn't reliably discoverable, approve a loadability-probe approach for readiness.

_The Manager moves each answered question into a numbered D-### decision._
