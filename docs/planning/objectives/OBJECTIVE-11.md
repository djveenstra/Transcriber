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
1. Add Model Lab to `RootView` tabs (iOS). Coordinate final tab order with OBJ-10/Manager (the Dashboard is the initial tab — see D-007 in [DECISIONS.md](../../../DECISIONS.md)).
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

## Completion Report — 2026-06-20

### Worker Summary
- Promoted Model Lab to the iOS top-level tab bar with final iOS order: Dashboard, Library, Model Lab, Settings.
- Kept Settings' existing secondary Model Lab entry point.
- Kept Record and Import reachable from Dashboard by opening the existing `RecordingView` flow with the same start/import request IDs; Record was removed from the primary tab bar per PRD §6 and the Human Reviewer OBJ-11 instruction.
- Added separate Model Lab load time and transcription/processing time measurements by preparing each model before starting the timed transcription call.
- Added registry-backed model size/status/detail snapshots to result cards and report export via `ModelRegistry.fileSnapshot`, `ModelRegistry.status`, and `ModelRegistry.formattedSize`.
- Extended result cards and the shareable report with model load time, processing time, speed/realtime factor, model size/status, failure status, error text, and transcript text.
- Preserved one-at-a-time execution: selected models still run through the existing sequential loop, with each engine unloaded before the next run starts.

### Files Touched
- `src/native/Transcriber2/Transcriber/RootView.swift`
- `src/native/Transcriber2/Transcriber/DashboardView.swift`
- `src/native/Transcriber2/Transcriber/ModelLabView.swift`
- `src/native/Transcriber2/TranscriberTests/ModelLabTests.swift`
- `DECISIONS.md`
- `PLAN.md`
- `OBJECTIVE.md`
- `QA.md`
- `docs/planning/objectives/OBJECTIVE-11.md`

### Auditor Alignment
- ALIGNED: Model Lab uses the OBJ-03 `ModelRegistry` for model size/status and does not introduce a second source of truth.
- ALIGNED: Execution remains one model at a time; no parallel model loads or dependency changes were introduced.
- ALIGNED: No `Recording` schema changes, migration changes, dependency bumps, strict-concurrency weakening, export hardening, OBJ-12+ speaker work, progress-timeline work, diagnostics-on-normal-screens work, accessibility work, Mac parity work, or cancellation hardening were started.
- ALIGNED: Touched code paths stayed inside `src/native/Transcriber2/`; planning/QA docs were updated for closeout only.

### QA Evidence
- Focused `ModelLabTests`: PASS.
- macOS build: PASS.
- iOS simulator build: PASS.
- `TranscriberTests`: PASS, 101/101.
- `git diff --check`: PASS.
- Manual/device comparative Model Lab timings remain Human-owned beta measurements; no Human-owned device gate blocks OBJ-11 completion.

### Gate Decision
- Manager recommendation: PROCEED.
