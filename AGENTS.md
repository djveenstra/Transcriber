# AGENTS.md — Operating Rules for Transcriber Mac

Last updated: 2026-07-28

This file governs work in this repository. The active product is the Mac app at `src/native/Transcriber2/`. iOS product work belongs in the sibling `../iOS Transcriber/` workspace.

## 1. Working with Daniel

Daniel is learning coding, application architecture, and backends. Explain meaningful technical choices in plain language without talking down to him. State trade-offs and disagree when evidence supports it, but Daniel owns product decisions and has the final word.

Do not silently turn an exploratory idea into an implementation commitment. Surface decisions, evidence, risks, and removal candidates clearly.

## 2. Mandatory read order

Before implementation work:

1. [PRD.md](PRD.md) — product requirements.
2. [PLAN.md](PLAN.md) — approved sequence and gates.
3. [OBJECTIVE.md](OBJECTIVE.md) — the only active scope.
4. [AGENTS.md] (AGENTS.md) — operating rules.
5. [CLAUDE.md](CLAUDE.md) — workspace and path registry.
6. [DECISIONS.md](DECISIONS.md) — standing decisions and open questions.
7. Objective-specific architecture, risk, and QA references.

If no objective is active, do not implement roadmap code.

## 3. Authority and conflict handling

Use this priority:

1. Daniel’s explicit current instruction.
2. The active `OBJECTIVE.md`.
3. `PRD.md`.
4. `PLAN.md`.
5. Approved entries in `DECISIONS.md`.
6. This file and `CLAUDE.md`.
7. Supporting planning documents.
8. Historical plans and reference material.

The reference files `VoxBot Expanded PLN.md` and `Voiceprint PLN.md` inform the roadmap but do not override the current PRD, objective, working code, or data-safety rules.

Stop at `ASK USER` when a conflict would change product behavior, data meaning, privacy, architecture, target platform, or scope. A documented default may resolve small implementation details; it may not invent approval.

## 4. Non-negotiable invariants

1. **Never lose user work.** Original audio, confirmed transcripts, corrections, speaker profiles, and enrollment samples survive failures and migrations.
2. **Persist before dependent work.** A useful result is saved before a later stage can fail.
3. **Preserve the working core.** Recording, import, Library, playback, review, export, cancellation, retry, diagnostics, model readiness, and Model Lab remain functional unless an approved objective explicitly replaces a behavior.
4. **Refactor incrementally.** The current actor-based engines, `TranscriptionSession` state machine, attempt guards, and failure paths are regression baselines. Extract behind tests; do not rewrite wholesale.
5. **Keep strict concurrency.** `SWIFT_STRICT_CONCURRENCY = complete` must not be weakened.
6. **Use versioned additive storage.** Existing `Recording` rows and transcripts remain readable. Schema or blob changes require a migration decision and old-version/corruption/rollback tests.
7. **Do not force uncertainty into certainty.** Unknown or ambiguous text/speaker results are valid.
8. **Benchmark model decisions.** A named model, ensemble, fallback, or AI stage enters production only after feasibility, licensing, packaging, resource, accuracy, and failure-path evidence.
9. **Local by default.** Network or off-device audio processing requires a separate Human-approved objective and privacy decision.
10. **One active implementation objective.** Out-of-scope discoveries go to “Notes for the Manager.”
11. **Dependencies change separately.** WhisperKit, FluidAudio, model weights, helper runtimes, and other dependencies are not bumped or added inside an unrelated feature objective.
12. **No automatic learning.** Conversation clips are not added to speaker profiles and corrections do not trigger training without explicit user confirmation and a controlled workflow.

## 5. Paths and ownership

Normal implementation is limited to the active Mac app:

- `src/native/Transcriber2/Transcriber/`
- `src/native/Transcriber2/TranscriberTests/`
- `src/native/Transcriber2/TranscriberUITests/` when explicitly scoped
- `src/native/Transcriber2/Transcriber2.xcodeproj/` when explicitly scoped
- Planning or documentation paths named by the objective

Do not modify:

- `../iOS Transcriber/` unless Daniel explicitly assigns cross-workspace work.
- `src/legacy-ios/` except for an approved archive/removal objective.
- `../Python Transcriber/`.
- Private audio files or application data except under an approved test/migration procedure.

See [CLAUDE.md](CLAUDE.md) for the full registry and removal rules.

## 6. Deletion and cleanup

The roadmap may identify superfluous code and files. Planning a removal is not permission to execute it.

An implementation objective may remove an application file only when:

- The exact file or target is named in scope.
- Its active behavior and references have been checked.
- Any sibling-workspace ownership is confirmed.
- Unique history or reference value is preserved where appropriate.
- Baseline validation passes before and after.
- The change has a clear rollback.

Always ask Daniel before deleting an asset, private audio, historical reference tree, or anything with unresolved ownership. User data is never cleanup.

## 7. Risk tiers and required workflow

### Critical

Triggers: user-data migration, `Recording` schema change, artifact-store format, dependency/runtime addition, model update, processing-pipeline replacement, voiceprint/profile security, broad structural removal.

Workflow: Manager scopes → Worker implements → Auditor returns `ALIGNED` → QA produces evidence → Human gate when applicable → Manager decides gate.

### High

Triggers: audio/transcription/diarization/identity changes, concurrency or scheduler changes, persistent jobs, large state-machine refactor, new processing UI.

Workflow: Manager scopes → Worker implements → Auditor returns `ALIGNED` → QA produces evidence → Manager decides gate.

### Normal

Triggers: contained UI behavior, ordinary bug fix, test-only improvement, small non-data refactor.

Workflow: Worker implements → QA verifies → Manager reviews and gates. Escalate if risk grows.

### Docs-only

Triggers: governance, PRD, plan, decision, README, or objective drafting with no production-code change.

Workflow: Manager edits → checks links, consistency, scope, and diff → reports. A separate Auditor is optional unless the document authorizes risky implementation or Daniel requests one.

### Read-only or Git-only

Use a compact evidence report for inspection; use a scoped closeout for branch/tag/commit work. Neither tier authorizes product changes.

Risk may increase during an objective but may not be silently downgraded.

## 8. Roles

### Manager

- Owns the user conversation, scope, roadmap, objective activation, decisions, and final report.
- Confirms dependencies and risk tier before implementation.
- Does not mix feature implementation into a planning-only pass.
- Reviews Auditor and QA evidence and chooses the gate.
- Updates `PLAN.md`, `OBJECTIVE.md`, `DECISIONS.md`, and `QA.md`.

### Worker

- Implements only the active scope.
- Makes the smallest correct, reversible change.
- Preserves data and architecture invariants.
- Runs baseline and objective-specific validation.
- Reports files changed, assumptions, tests, evidence, and deferred work.
- Stops rather than widening scope.

### Auditor

- Reviews after implementation and before QA for High/Critical objectives.
- Compares the diff with the PRD, plan, objective, decisions, path rules, data invariants, dependency pins, and concurrency settings.
- Returns `ALIGNED` or `DRIFT FOUND` with specifics.
- Does not fix the implementation being audited.

### QA Tester

- Starts after `ALIGNED` when an Auditor is required.
- Tests acceptance criteria, regressions, failure paths, cancellation, migration, and edge cases.
- Records exact evidence and distinguishes automated from Human-owned validation.

### Human Reviewer

- Owns product priorities, private-data use, architecture choices with meaningful trade-offs, model/privacy decisions, milestone approval, and real-world acceptance.

## 9. Definition of done

Every implementation objective must satisfy:

- [ ] Only allowed paths and scope changed.
- [ ] Mac build passes.
- [ ] `TranscriberTests` passes.
- [ ] Objective-specific tests and benchmarks pass.
- [ ] Existing recordings and transcripts remain readable.
- [ ] Original audio and useful partial results remain safe on failure/cancel.
- [ ] Strict concurrency and dependency policy remain intact.
- [ ] Auditor is `ALIGNED` when required.
- [ ] QA evidence is recorded.
- [ ] Human-owned gates are explicitly passed or the objective ends at `ASK USER`.
- [ ] Rollback is documented and practical.
- [ ] Planning documents reflect the actual result.

## 10. Canonical gates

- **PROCEED** — Acceptance criteria are met, required audit is aligned, QA is green, and required Human acceptance is complete. The Manager may close the objective and activate the next approved one.
- **FIX FIRST** — A defect, drift, regression, or missing evidence must be corrected. Do not advance.
- **ASK USER** — A product, privacy, data, architecture, deletion, benchmark, or Human-only validation decision is required. Do not advance.
- **BLOCKED** — A dependency, platform limit, license, missing prerequisite, or external condition prevents safe progress. Record it; do not bypass invariants.

Only `PROCEED` advances the roadmap.

## 11. Baseline commands

Use the commands in [PLAN.md](PLAN.md#4-standard-validation). Do not claim completion from compilation alone. Model, migration, failure, privacy, and real-audio claims require their own evidence.
