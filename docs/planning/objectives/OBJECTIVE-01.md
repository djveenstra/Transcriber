# OBJECTIVE-01 — Governance, Green Baseline & Data-Safety Guardrails
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 0. Prerequisite for everything. **This is the first Codex run.** Read [PRD.md](../../../PRD.md) → [PLAN.md](../../../PLAN.md) → [OBJECTIVE.md](../../../OBJECTIVE.md) → [AGENTS.md](../../../AGENTS.md) before starting._

## Mission
Make change safe before any feature work: prove the project builds and tests green on macOS and iOS-simulator, lock in repo-hygiene conventions, confirm the SwiftData migration policy, and add (only if appropriate) test-only guardrails around the `Recording` data blobs so future objectives can't silently corrupt user data. **No production behavior changes.**

## This objective is intentionally narrow. Do ONLY these things:
1. **Verify the macOS build** (baseline command below).
2. **Verify the iOS-simulator build** (baseline command below).
3. **Verify the unit tests** (`xcodebuild test`, macOS, `TranscriberTests` bundle).
4. **Add data-safety guardrail tests _if appropriate_** — round-trip encode/decode for `Recording.segments`, `rawTranscription`, `speakerNames`, and behavior on corrupted blob data (returns `[]`/`[:]`, logs, never crashes). Tests only — see prohibitions.
5. **Document the active-path rule** (already in [AGENTS.md §2.3](../../../AGENTS.md) and [DECISIONS.md D-001](../../../DECISIONS.md)) — confirm it is present and correct; do not weaken it.
6. **Confirm the SwiftData migration policy** ([DECISIONS.md D-002](../../../DECISIONS.md)) is present and matches `Models.swift`; note any discrepancy in DECISIONS.md (do not change the schema).
7. **Append QA evidence** to [QA.md](../../../QA.md) using the entry format there.

## PROHIBITED in this objective (hard stops — escalate instead)
- ❌ **No behavior changes** to the app (UI, flows, pipeline, persistence semantics).
- ❌ **No feature work** of any kind.
- ❌ **No dependency bumps** (WhisperKit, FluidAudio, or any SPM revision).
- ❌ **No schema changes** to `Recording` or any model — _unless_ explicitly covered by the migration policy ([DECISIONS.md D-002](../../../DECISIONS.md)); for OBJ-01 the expectation is **zero schema change**.
- ❌ **No changes outside `src/native/Transcriber2/` and planning docs.** (Adding test files under `src/native/Transcriber2/TranscriberTests/` is allowed.)
- ❌ **No modifying `src/python/`** (independent Transcriber 1.x).
- ❌ **No modifying `src/legacy-ios/`.**
- ❌ **No moving, modifying, deleting, or archiving `XCode App Build/`** (or any folder). You may _inventory_ it and write a recommendation only.
- ❌ **No weakening `SWIFT_STRICT_CONCURRENCY = complete`.**

> If reaching a green build/test would require any prohibited change, **stop and escalate** (`BLOCKED` / `ASK USER`) with the specific blocker — do not proceed.

## Scope
- Run + confirm the three baseline commands; if a scheme/destination name is wrong, fix the **command text in [PLAN.md](../../../PLAN.md)** (not the Xcode project) and report.
- Add the `Recording` coding guardrail tests (new file `TranscriberTests/RecordingCodingTests.swift`) in the existing test style.
- Confirm active-path rule + migration policy are documented and accurate.
- Inventory the stale `XCode App Build/` tree; **propose** archiving (do not act).
- Append QA evidence to [QA.md](../../../QA.md).

## Out of Scope
- Everything in the PROHIBITED list.
- Any objective OBJ-02+ work.

## Worker Instructions
1. Run the three baseline commands. Capture output for QA evidence.
2. If the build is **not** green, do not attempt feature/behavior fixes: scope narrows to "reach green via test/config/doc-only means," and if that's impossible without a prohibited change, escalate to the Manager (`BLOCKED`).
3. Add the guardrail tests; confirm they pass and that they fail meaningfully if the blob logic is broken (temporarily mutate, observe failure, revert).
4. Confirm [DECISIONS.md](../../../DECISIONS.md) D-001 (active path) and D-002 (migration policy) are present and consistent with `Models.swift`; record any discrepancy as a new open question in DECISIONS.md.
5. Write the QA evidence entry; report files touched, assumptions, test results, and the `XCode App Build/` archive recommendation.

## Auditor Checklist
- [ ] No production code behavior changed (tests + docs only; new test file is acceptable).
- [ ] Touched paths are inside `src/native/Transcriber2/` and/or planning docs only.
- [ ] No dependency bump; `SWIFT_STRICT_CONCURRENCY = complete` unchanged.
- [ ] No `Recording`/model schema change.
- [ ] No file moved/deleted; `XCode App Build/` untouched (archive is a proposal only).
- [ ] Migration policy present and consistent with `Models.swift`.
- [ ] Guardrail tests genuinely exercise corruption + round-trip.
- [ ] Verified against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md.

## QA Checklist
- [ ] All three baseline commands pass; output captured in [QA.md](../../../QA.md).
- [ ] New tests pass and fail meaningfully when blob logic is broken (spot-check, then revert).
- [ ] Regression checklist (launch, record→transcript, import, library) still green.
- [ ] QA evidence appended to [QA.md](../../../QA.md).

## Acceptance Criteria
- macOS + iOS-sim builds and `xcodebuild test` for the `TranscriberTests` unit-test bundle all pass.
- Migration policy + active-path rule confirmed present/accurate in [DECISIONS.md](../../../DECISIONS.md).
- `Recording` coding guardrail tests added and green (if appropriate; if the project already covers this, note it instead).
- Archive recommendation for `XCode App Build/` recorded for the Human Reviewer.
- QA evidence appended to [QA.md](../../../QA.md).

## Validation Commands
See [PLAN.md](../../../PLAN.md) baseline (macOS build, iOS-sim build, macOS test). No additional commands.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md), plus: baseline green and documented; guardrail tests committed (or coverage confirmed already present); migration policy + active-path rule confirmed; QA evidence appended.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if baseline green + guardrail tests added/confirmed + policy confirmed + QA evidence appended.
- **FIX FIRST** if tests are missing, fail, or the regression checklist breaks.
- **ASK USER** to approve archiving `XCode App Build/` (do not act without approval).
- **BLOCKED** if the project does not build/test green and the only fixes would be prohibited changes — escalate with the specific blocker.

## Rollback Considerations
Pure additive (tests + docs). Revert the commit to fully undo. No data, schema, dependency, or behavior impact.

## Completion Report — 2026-06-18

**Gate:** PROCEED

**Worker report:**
- Files touched: `PLAN.md`, `OBJECTIVE.md`, `QA.md`, `DECISIONS.md`, `docs/planning/objectives/OBJECTIVE-01.md`. No production code changes remain.
- Assumptions: Existing `RecordingPersistenceTests` satisfy OBJ-01 guardrail coverage, so no new test file was needed.
- Tests run: macOS build PASS; iOS-simulator build PASS; original generated-scheme macOS test command failed because `TranscriberUITests` runner exited before bootstrap; corrected unit-test baseline `-only-testing:TranscriberTests` PASS with 49/49 tests.
- Failure injection: Temporarily broke `Recording.segments` setter; `RecordingPersistenceTests.segmentsRoundTripThroughSetterAndGetter()` failed as expected; restored production file and reran unit tests green.
- Objective items completed: active-path rule confirmed; SwiftData migration policy confirmed against `Models.swift`; `XCode App Build/` inventoried only; QA evidence appended.
- Deferred/blocked: Generated macOS UI-test runner is not part of the recurring baseline until intentionally configured.
- `XCode App Build/` recommendation: Archive later with Human Reviewer approval. It is a stale starter Xcode tree with its own nested `.git`; keep read-only until approved.

**Auditor report:** ALIGNED. Diff is planning docs only; no app behavior, schema, dependency, strict-concurrency, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes.

**QA report:** PASS. Evidence recorded in [QA.md](../../../QA.md#obj-01--governance-green-baseline--data-safety-guardrails--2026-06-18). No Human-owned real-device gate was claimed complete.
