# Multi-Agent Operating Model — Transcriber 2.0 Beta

_The repeatable loop that turns [PLAN.md](../../PLAN.md) into shipped, validated objectives, month after month. Roles are defined in [AGENTS.md](../../AGENTS.md); this document defines the **timing and handoffs**._

## Roles at a glance

```
Human Reviewer (Daniel)  ── owns product decisions, milestone approval, on-device acceptance
        ▲
        │ approves / resolves ambiguity / accepts device gates
        │
   Manager  ── selects objective, assigns work, decides the Gate, updates planning docs
   ┌────┴───────────────┬──────────────────┐
   ▼                    ▼                  ▼
 Worker  ───────────► Auditor ──────────► QA Tester
 implements           checks alignment    tests behavior
 the scope            (before QA)         (after Auditor OK)
```

## The loop (one objective, start to finish)

### Step 1 — Manager creates work
**When:** the previous objective is `PROCEED` (done) or the Human Reviewer authorizes starting.
**Does:** picks the next objective from [PLAN.md](../../PLAN.md); confirms its dependencies are satisfied; copies its file to the active [OBJECTIVE.md](../../OBJECTIVE.md) (or points to it); restates the Mission, Scope, and Out-of-Scope to the Worker. If dependencies are unmet, the Manager either reorders (with Human approval) or escalates.

### Step 2 — Worker implements
**When:** immediately after assignment.
**Does:** implements only the Scope; makes the smallest correct change; runs the baseline + objective Validation Commands.
**Worker stops when:** (a) the objective is implemented and validated; (b) it hits an escalation trigger ([AGENTS.md §5](../../AGENTS.md)); (c) it cannot validate because the behavior is device-only; or (d) it would have to exceed scope to finish. The Worker never silently expands scope and never claims unvalidated completion.
**Produces:** a Worker report — files touched, assumptions, tests run + results, objective rows completed, deferred items.

### Step 3 — Auditor reviews (before QA)
**When:** as soon as the Worker reports completion.
**Does:** compares the diff against PRD/PLAN/OBJECTIVE/AGENTS; checks for architectural drift, scope creep, data-safety regressions, concurrency-setting changes, edits outside the active path, dependency bumps, and reversibility.
**Produces:** an alignment report with `ALIGNED` / `DRIFT FOUND` and specifics. If drift is found, work returns to the Worker (Manager decides `FIX FIRST`). The Auditor does not edit code.

### Step 4 — QA runs (after Auditor approval)
**When:** only after the Auditor returns `ALIGNED`.
**Does:** executes the objective's QA Checklist + relevant parts of [QA_STRATEGY.md](QA_STRATEGY.md); verifies workflows, UI states, failure injection, regressions, edge cases.
**Produces:** QA evidence (commands/outputs/notes/screenshots), clearly separating agent-verifiable results from **Human-owned device gates**.

### Step 5 — Manager gates
**When:** after QA evidence is in, and only after the Auditor returned `ALIGNED`.
**Decision (one of — canonical definitions live in [AGENTS.md §6](../../AGENTS.md); the summaries below must stay in sync with it):**
- **PROCEED** — Acceptance Criteria met, Auditor aligned, QA green (device gates flagged for the Human). Manager updates planning docs and advances to the next objective.
- **FIX FIRST** — Defects or drift found; return to Worker with a specific list; re-run Auditor + QA.
- **ASK USER** — A product decision, ambiguity, or a Human-owned device gate is required before proceeding.
- **BLOCKED** — A dependency, conflict, or external factor prevents progress; record the blocker and escalate.

### Step 6 — Human Reviewer
**When:** on `ASK USER`/`BLOCKED`, at milestone boundaries, or when device acceptance is required.
**Does:** resolves ambiguity, makes the product call, runs/accepts on-device tests, and approves the milestone.

## When each planning document is updated

| Document | Updated by | When |
|---|---|---|
| [OBJECTIVE.md](../../OBJECTIVE.md) (active) | Manager | At Step 1 (set active) and at `PROCEED` (advance to next) |
| `docs/planning/objectives/OBJECTIVE-NN.md` | Manager | When its Gate is decided — record outcome + completion report link |
| [PLAN.md](../../PLAN.md) | Manager | On completion (mark done), on discovered dependency, on Human-approved scope/sequence change, when a risk materializes |
| [DECISIONS.md](../../DECISIONS.md) | Manager | Whenever a non-obvious architectural/product decision is made (with rationale) |
| [RISK_REGISTER.md](RISK_REGISTER.md) | Manager | When a risk is closed, changes rank, or a new risk appears |
| [QA.md](../../QA.md) | QA Tester / Manager | After each objective's QA — append evidence summary |

**PLAN.md changes that alter scope or sequence require Human Reviewer approval.** Marking an objective done, linking a report, or noting a discovered dependency do not.

**OBJECTIVE advances only when** the current objective is `PROCEED` and its planning-doc updates are written. Never start the next objective while the current one is `FIX FIRST`/`ASK USER`/`BLOCKED`.

## How architectural drift is detected

1. **Auditor diff review** against the documented architecture ([ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md)) — engine protocols intact? state machine intact? persist-then-proceed intact?
2. **Mechanical checks** every objective: touched paths inside the active tree; `SWIFT_STRICT_CONCURRENCY=complete` unchanged; no dependency revision change in `project.pbxproj`; no `Recording` schema change without a migration entry in [DECISIONS.md](../../DECISIONS.md).
3. **Build/test gate** — strict-concurrency build failures are the canonical drift alarm.
4. **Risk-register linkage** — if a change touches a Critical-risk area (R1–R4, R7), the Auditor explicitly confirms the mitigation still holds.

## How scope creep is prevented

1. One objective in flight at a time; the Worker implements only its Scope and Out-of-Scope is explicit in every objective file.
2. The Auditor flags any file touched that the objective didn't call for.
3. Out-of-scope discoveries are logged to the objective's "Notes for the Manager"; the Manager decides whether to create a new objective — never to widen the current one.
4. The Human Reviewer is the backstop on scope at every milestone.

## A sustainable cadence (months of development)

- **Per objective:** Manager assigns → Worker implements + validates → Auditor aligns → QA evidences → Manager gates → docs updated. Keep objectives ≈ one session so the loop stays fast and reversible.
- **Per phase:** at a phase boundary the Manager summarizes outcomes, re-checks the [RISK_REGISTER.md](RISK_REGISTER.md), and seeks Human milestone approval before the next phase.
- **Device-gate rhythm:** batch Human-owned device validations (OBJ-04 model persistence, OBJ-08 background/30-min, OBJ-18 Mac, OBJ-20 acceptance) so the Human Reviewer runs them deliberately rather than ad hoc.
- **Recovery:** any objective can be reverted independently; if a regression surfaces later, revert that objective's commit and re-enter the loop at Step 2.
