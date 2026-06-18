# OBJECTIVE-11 — Model Lab as Top-Level Tab + Diagnostics Columns

_Phase 3 (third of three). **Depends on OBJ-03 (model registry)** and assumes the status foundation (OBJ-09) is in place. Closes PRD §6 Model Lab (A6, A7). RISK R14._

> **Sequencing:** Model Lab's new columns read from the model registry/status foundations (OBJ-03) and run after the Dashboard (OBJ-10) so the final tab order is settled in one place.

## Mission
Promote Model Lab to a top-level tab and enrich its comparison with model **load time** and **size/status**, fulfilling PRD §6/§17 Model Lab requirements.

## Scope
- Make Model Lab a top-level tab (currently nested in Settings, iOS-only). Keep a Settings entry point too if desired.
- Add captured **model load time** (distinct from transcription time) and **model size/status** (from the OBJ-03 registry) to each result.
- Keep the existing one-at-a-time execution (memory safety) and report export.

## Out of Scope
- Mac Model Lab implementation (OBJ-18 evaluates feasibility).
- Diagnostics on non-Lab screens (OBJ-15).
- Dashboard / status-model work (OBJ-09, OBJ-10).

## Worker Instructions
1. Add Model Lab to `RootView` tabs (iOS). Coordinate final tab order with OBJ-10/Manager (the Dashboard is the initial tab — see Q-2 in [DECISIONS.md](../../../DECISIONS.md)).
2. In `ModelLabRunner`, time model load separately from transcription; add size/status columns from the OBJ-03 registry.
3. Preserve one-at-a-time runs and the shareable report; extend the report to include load time + size.

## Auditor Checklist
- [ ] One-at-a-time execution preserved (no parallel model loads).
- [ ] Load time measured separately from transcription time.
- [ ] Size/status sourced from the OBJ-03 registry (no new source of truth).
- [ ] Strict concurrency unchanged; both builds green.
- [ ] Checked against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md.

## QA Checklist
- [ ] Model Lab reachable as a tab; compares ≥2 downloaded models on one recording.
- [ ] Results show load time, processing time, speed (RTF), size/status, transcript, failures.
- [ ] Report export includes the new fields.
- [ ] Regression: Settings link still works; runs don't spike memory.

## Acceptance Criteria
- Model Lab is a tab; records load time + processing time + failure + transcript + size/status + report export (PRD §17).
- Tests/builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Real comparative timings are a **device** measurement (Human, OBJ-20).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if tab + columns + report land green.
- **ASK USER** to confirm the final tab order across OBJ-10/11.
- **FIX FIRST** if one-at-a-time execution is broken or registry data isn't reused.
- **BLOCKED** if the OBJ-03 registry is unavailable.

## Rollback Considerations
Tab promotion + additive columns. Revert restores the nested-in-Settings Model Lab. No data/schema change.
