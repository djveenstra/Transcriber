# Objective Workflow — Transcriber Mac

Last updated: 2026-07-28

Roles and risk tiers are defined in [AGENTS.md](../../AGENTS.md). This file defines the handoffs for one active objective.

## 1. Activation

The Manager:

1. Confirms Daniel approved starting the objective.
2. Confirms prerequisites in [PLAN.md](../../PLAN.md).
3. Creates a `VX-NN` objective file.
4. Updates [OBJECTIVE.md](../../OBJECTIVE.md) to point to it.
5. Declares risk tier, allowed paths, forbidden paths, private-data permission, preserved behavior, acceptance criteria, and rollback.
6. Reviews the worktree so unrelated user changes are not absorbed.

No Worker begins from a roadmap bullet alone.

## 2. Implementation

The Worker:

- Reads the required governance and active objective.
- Characterizes current behavior before risky refactoring.
- Makes the smallest correct change.
- Does not widen scope to fix adjacent discoveries.
- Runs baseline and objective-specific tests.
- Produces a report with files changed, decisions applied, assumptions, migrations, tests, benchmark evidence, and deferred findings.

The Worker stops at:

- A data-safety conflict.
- An unresolved product/privacy/architecture decision.
- A required out-of-scope path.
- A new dependency/model/runtime not authorized by the objective.
- A deletion whose ownership is unresolved.
- A Human-only gate.

## 3. Audit

Required for High and Critical objectives.

The Auditor checks:

- Diff matches scope and allowed paths.
- PRD, plan, decisions, and objective agree.
- Existing core behavior is preserved.
- Original audio and partial-result invariants hold.
- Storage changes are additive/versioned and tested.
- Strict concurrency remains complete.
- Dependency and model pins changed only when authorized.
- Private data did not enter source, logs, or reports.
- Benchmark claims compare with the correct baseline.
- Removal targets were proven unused/owned elsewhere.
- Rollback is practical.

The Auditor returns:

- `ALIGNED`, or
- `DRIFT FOUND` with actionable findings.

QA does not start on High/Critical work until the audit is aligned.

## 4. QA

QA follows [QA_STRATEGY.md](QA_STRATEGY.md) and the objective checklist.

Evidence separates:

- Automated build/tests.
- Migration and failure-path tests.
- Private benchmark results.
- Manual Mac UI checks.
- Privacy/license/package review.
- Human-owned acceptance.

QA appends results to [QA.md](../../QA.md) and returns PASS, FAIL, or PARTIAL.

## 5. Manager gate

After required evidence, the Manager chooses exactly one:

- **PROCEED** — objective complete; update docs and activate the next approved objective.
- **FIX FIRST** — return a specific defect/drift list to the Worker, then repeat audit and QA as required.
- **ASK USER** — Daniel must decide or perform a Human-owned validation.
- **BLOCKED** — dependency, license, platform, prerequisite, or external condition prevents safe completion.

Only `PROCEED` advances the roadmap.

## 6. Workflow by risk

| Tier | Required path |
|---|---|
| Critical | Manager → Worker → Auditor → QA → Human when applicable → Manager gate |
| High | Manager → Worker → Auditor → QA → Manager gate |
| Normal | Manager/Worker → QA → Manager gate |
| Docs-only | Manager edit → link/consistency/diff validation → report |
| Read-only | Evidence report |
| Git-only | Scoped Git action and verification |

If risk grows, stop and rescope upward.

## 7. Planning updates

On `PROCEED`, the Manager:

- Records completion in the objective file.
- Appends QA evidence.
- Updates the objective row in PLAN.
- Updates risks and decisions when needed.
- Advances OBJECTIVE only if Daniel already approved the next start; otherwise returns it to “no active objective.”

Completed objectives remain factual history. Do not rewrite them to conceal failures, scope changes, or Human gates.

## 8. Milestone review

At each PLAN phase boundary, the Manager summarizes:

- What now works.
- What stayed unchanged.
- Benchmark change from baseline.
- Material risks opened/closed.
- Removals proposed or completed.
- Optional components rejected for lack of benefit.
- Decisions needed before the next phase.

Daniel approves, redirects, pauses, or stops the next phase.
