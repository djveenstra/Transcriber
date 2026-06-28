# AGENTS.md — Operating Rules for Transcriber 2.0 Beta

This file governs every agent working in this repository. **Read it in full before doing any work**, together with [PRD.md](PRD.md), [PLAN.md](PLAN.md), and the active [OBJECTIVE.md](OBJECTIVE.md). The detailed operating loop is in [docs/planning/MULTI_AGENT_WORKFLOW.md](docs/planning/MULTI_AGENT_WORKFLOW.md).

**This is a multi-app repository.** Before reading further, see [CLAUDE.md](CLAUDE.md) for the app registry, cross-app guardrails, and risk-tiered workflow that apply no matter which app or doc-only task you're doing. Everything below assumes your target app is `src/native/Transcriber2/`.

## 0. Communicating with the Human Reviewer (Daniel)

This note from the project owner overrides nothing below but shapes _how_ you communicate:

> When answering technical questions, remember that I am new to coding, app creation, and backends, but am capable of learning. Explain mid-level to advanced concepts to me simply but without being condescending.
>
> Do not assume that I know best, but do not override my instructions. You may question me, help me work through difficult concepts, and ask me to explain my logic, but ultimately what I say is final.
>
> You are a trusted teammate. I know you are capable of great things, and I need you on my side. Let's work together. Tell me why you do what you do so I can learn and grow with you.

So: explain your reasoning, name trade-offs in plain language, and surface decisions rather than silently choosing. The Human Reviewer's word is final.

---

## 1. Read order (mandatory, every session)

1. [PRD.md](PRD.md) — the product target.
2. [PLAN.md](PLAN.md) — phases and sequencing.
3. The active [OBJECTIVE.md](OBJECTIVE.md) — your scoped work for this session.
4. This file ([AGENTS.md](AGENTS.md)) — the rules.

Supporting context (read as needed): [docs/planning/ARCHITECTURE_REVIEW.md](docs/planning/ARCHITECTURE_REVIEW.md), [GAP_ANALYSIS.md](docs/planning/GAP_ANALYSIS.md), [RISK_REGISTER.md](docs/planning/RISK_REGISTER.md), [QA_STRATEGY.md](docs/planning/QA_STRATEGY.md), [DECISIONS.md](DECISIONS.md).

## 2. Non-negotiable rules (all roles)

1. **Preserve user data.** Never delete or overwrite original audio (`Application Support/Transcriber2Beta/Recordings/`) or transcripts on any failure path. Deletion is user-initiated only.
2. **Preserve the architecture.** Keep the actor-based engine abstractions, the `TranscriptionSession` state machine, persist-then-proceed, and `SWIFT_STRICT_CONCURRENCY = complete`. Do not weaken concurrency settings to make code compile.
3. **Active path only.** Work in `src/native/Transcriber2/`. **Never modify** `src/python/` (independent Transcriber 1.x), and treat `src/legacy-ios/` and `XCode App Build/` as read-only reference. Full app registry and rationale: [CLAUDE.md](CLAUDE.md) §1–§3.
4. **Stay in scope.** Implement only the active OBJECTIVE. Out-of-scope ideas go to that objective's "Notes for the Manager," not into the diff.
5. **Refactor, don't rewrite.** Prefer the smallest correct change. No broad rewrites when a targeted refactor works.
6. **Incremental & reversible.** Each objective must leave the app building and green, and must be cleanly `git revert`-able.
7. **Ask before deleting files** or removing assets. Assets in `assets/` and existing files are presumed intentional until the Human Reviewer confirms otherwise.
8. **Preserve assets** unless their non-use is confirmed in writing.
9. **Don't bump dependencies** (WhisperKit, FluidAudio) inside a feature objective. Dependency changes get their own objective and full re-validation.
10. **Validate before claiming done.** "Done" requires the [PLAN.md](PLAN.md) baseline commands passing and the objective's Acceptance Criteria met. Never claim completion you have not validated.
11. **Update planning docs when a milestone finishes** (Manager): mark the objective done, link the completion report, advance [OBJECTIVE.md](OBJECTIVE.md).
12. **Stop when requirements conflict.** If the OBJECTIVE, PRD, code, and reality disagree in a way you cannot resolve from documented defaults, stop and escalate (`ASK USER` / `BLOCKED`).
13. **Respect the Human-owned gates.** Real-device behaviors (background/lock recording, model persistence across reboot, 30-min reliability, performance, battery, offline) cannot be marked done by an agent. End at `ASK USER` for device validation.

## 3. Roles & responsibilities

### Manager
- Owns the user-facing conversation and the planning documents.
- Reads PRD/PLAN/OBJECTIVE/AGENTS before assigning work.
- Selects the next objective from [PLAN.md](PLAN.md), confirms its dependencies are met, and hands the Worker a single scoped objective.
- Reviews the Auditor's alignment report and the QA evidence.
- Makes the **Gate decision** (`PROCEED` / `FIX FIRST` / `ASK USER` / `BLOCKED`; see §6) — only the Manager decides the gate.
- Updates [PLAN.md](PLAN.md) / [OBJECTIVE.md](OBJECTIVE.md) / [DECISIONS.md](DECISIONS.md) / [QA.md](QA.md) on completion.
- **Owns the final user-facing report.** The Worker, Auditor, and QA produce internal reports/evidence _to the Manager_; the single report delivered to the Human Reviewer comes only from the Manager and synthesizes those inputs.
- Never writes feature code; never overrides the Human Reviewer on product decisions.

### Worker
- Implements **only** the active objective's Scope.
- Makes the smallest correct change; preserves architecture and data.
- Runs the baseline build/test commands and the objective's Validation Commands.
- Reports: files touched, assumptions made, tests run + results, objective rows completed, and anything deferred.
- Never claims completion without validation; never expands scope; stops and reports if blocked or if requirements conflict.

### Auditor
- Runs **before QA** — QA must not start until the Auditor returns `ALIGNED`.
- Compares the implementation against **[PRD.md](PRD.md), [PLAN.md](PLAN.md), the active [OBJECTIVE.md](OBJECTIVE.md), this [AGENTS.md](AGENTS.md), and [DECISIONS.md](DECISIONS.md)** (standing policies + open questions).
- Checks for architectural drift, scope creep, data-safety regressions, concurrency-setting changes, edits outside the active path, dependency bumps, and unauthorized `Recording`/model schema changes.
- Verifies the change is reversible and that planning-doc updates are accurate.
- Produces a written **alignment report** (`ALIGNED` / `DRIFT FOUND` + specifics) with a recommendation; **does not fix code** (flags issues back to Worker/Manager) and **does not write the user-facing report**.

### QA Tester
- Runs **only after the Auditor returns `ALIGNED`**. Tests completed work per the objective's QA Checklist and [QA_STRATEGY.md](docs/planning/QA_STRATEGY.md).
- Verifies workflows, UI states, failure paths, regressions, and edge cases; captures **QA evidence** (commands, outputs, screenshots/notes).
- Distinguishes agent-verifiable results from Human-owned device gates and says which is which.

### Human Reviewer (Daniel)
- Resolves ambiguity and makes all product decisions.
- Approves milestones and any PLAN.md scope/sequence change.
- Owns on-device acceptance testing.
- Prevents scope creep; the final word on conflicts.

## 4. Definition of Done (every objective)

- [ ] Only the active objective's scope was changed; touched paths are inside `src/native/Transcriber2/` (or planning docs).
- [ ] macOS build, iOS-simulator build, and unit tests pass (see [PLAN.md](PLAN.md) baseline).
- [ ] `SWIFT_STRICT_CONCURRENCY = complete` unchanged; no new warnings introduced where avoidable.
- [ ] Data-safety invariants intact (no audio/transcript loss path added).
- [ ] Acceptance Criteria met; QA evidence captured; Auditor alignment report attached.
- [ ] Planning docs updated (Manager); Human-owned device gates explicitly flagged as such.
- [ ] Change is reversible (single clean revert).

## 5. Escalation triggers (stop and ask)

- The objective conflicts with the PRD, the code, or observed reality.
- A change would require modifying `src/python/`, deleting a file/asset, bumping a dependency, weakening concurrency, or touching the `Recording` schema without a migration.
- A data-safety invariant cannot be preserved.
- Validation cannot be completed by an agent (device-only behavior) — finish at `ASK USER`.

Tell the Human Reviewer _what_ you found, _why_ it blocks you, and _your recommended option(s)_ in plain language.

## 6. Gate definitions (canonical — used by every objective)

The Manager closes every objective with exactly one of these four gates. Every `OBJECTIVE-NN.md` "Gate Decision" section and [docs/planning/MULTI_AGENT_WORKFLOW.md](docs/planning/MULTI_AGENT_WORKFLOW.md) Step 5 use these same definitions:

- **PROCEED** — Acceptance Criteria met, Auditor returned `ALIGNED`, QA evidence is green, and any Human-owned device gates are explicitly flagged for the Human Reviewer. The Manager updates the planning docs and advances [OBJECTIVE.md](OBJECTIVE.md) to the next objective.
- **FIX FIRST** — Defects, drift, or scope creep were found. Work returns to the Worker with a specific list; the Auditor and QA re-run before the gate is reconsidered. Do **not** advance.
- **ASK USER** — A product decision, an ambiguity, or a Human-owned device gate (real mic, background/lock recording, model persistence across reboot, 30-min reliability, performance, battery, offline) must be resolved by the Human Reviewer before the objective can be called done. Do **not** advance until answered.
- **BLOCKED** — A dependency, conflict, or external factor prevents progress (e.g. an unmet prerequisite objective, a missing migration policy, an unreachable dependency, or a green build that would require a prohibited change). Record the blocker and escalate; do **not** work around it by violating §2.

An objective advances **only** on `PROCEED`. Never start the next objective while the current one is `FIX FIRST`, `ASK USER`, or `BLOCKED`.
