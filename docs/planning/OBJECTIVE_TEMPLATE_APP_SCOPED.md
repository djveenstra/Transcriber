# VX-NN — Objective Title

Status: Proposed

Risk tier: Normal / High / Critical

Target app: Transcriber Mac

Manager:

Approved to start by Daniel: No

## Mission

One sentence describing the user-visible or safety outcome.

## Why now

- Prerequisite objectives:
- Risk or gap addressed:
- Current code evidence:

## Scope

### Allowed paths

- Exact paths.

### Forbidden paths

- `../iOS Transcriber/`
- `../Python Transcriber/`
- `src/legacy-ios/`
- Add objective-specific exclusions.

### Private-data permission

- None by default.
- List exact approved dataset/fixture access if Daniel authorizes it.

### In scope

- Concrete work.

### Out of scope

- Explicit adjacent work that must not leak into this objective.

### Behavior that must remain unchanged

- Recording/import.
- Existing-record readability.
- Original-audio preservation.
- Add objective-specific regression behavior.

## Technical approach

Describe the smallest intended change and the existing seam it uses. Name any schema, artifact, dependency, model, concurrency, sandbox, or packaging impact.

## Data and migration

- Existing data read path:
- New data/write path:
- Versioning:
- Corruption behavior:
- Rollback compatibility:
- User-data deletion: none unless explicitly approved.

## Implementation tasks

- [ ] Task.
- [ ] Tests written before/with behavior.
- [ ] Failure and cancellation paths.
- [ ] Documentation/evidence.

## Validation

### Baseline

Use [PLAN.md §4](../../PLAN.md#4-standard-validation).

### Objective-specific automated checks

```sh
# Exact commands
```

### Benchmark

- Dataset version:
- Baseline:
- Metrics:
- Pass gate:

### Manual Mac checks

- Steps and expected result.

### Human-owned checks

- None, or exact steps Daniel must perform.

## Acceptance criteria

- [ ] User/data outcome.
- [ ] Baseline green.
- [ ] Existing records readable.
- [ ] Failure/cancel safe.
- [ ] Benchmark gate passed when applicable.
- [ ] Private data absent from Git/logs.
- [ ] Auditor `ALIGNED` when required.
- [ ] QA evidence appended.

## Removal targets

If none, say none.

For each removal:

- Exact target.
- Reference/owner proof.
- Replacement or reason it is superfluous.
- Before/after validation.
- Recovery path.
- Daniel approval if required.

## Rollback

State the mechanical rollback and how data written by this objective remains readable afterward.

## Notes for the Manager

Out-of-scope discoveries only.

---

## Worker report

Pending.

## Auditor report

Pending / not required by tier.

## QA evidence

Pending.

## Gate decision

Pending: `PROCEED` / `FIX FIRST` / `ASK USER` / `BLOCKED`.
