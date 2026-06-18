# OBJECTIVE-10 — Dashboard Tab

_Phase 3 (second of three). **Depends on OBJ-09 (`RecordingStatus`)**, OBJ-02/03 (model status), OBJ-07 (mic status). Closes PRD §6 Dashboard (A1, A2). RISK R14._

> **Sequencing:** the canonical `RecordingStatus` is delivered in OBJ-09 and must be gated `PROCEED` before this objective starts. This objective **consumes** that status model; it does not define it.

## Mission
Add the PRD's Dashboard home screen: a calm status-plus-recent-work surface with prominent primary actions.

## Scope
- New `Dashboard` tab, set as the app's initial tab.
- Shows: active microphone status, selected transcription model + readiness, speaker-labeling engine status, recent recordings needing attention (failed/needs-transcription/needs-labels via OBJ-09 `RecordingStatus`), and friendly warnings when required models are missing/downloading/failed/repairing.
- Prominent actions: Record, Import, Open Model Lab; jump to recent incomplete/failed jobs.
- Reuse existing components (status pills, model status, `TranscriptCard`-style rows) — no new design language.

## Out of Scope
- Building the status enum itself (OBJ-09) — consume it.
- Model Lab tab promotion (OBJ-11).
- Library/Settings restructuring beyond adding the tab.

## Worker Instructions
1. Add `DashboardView`; place it first in `RootView`'s `TabView`. Keep `Record`, `Library`, `Settings`; Model Lab becomes a tab in OBJ-11 (coordinate final tab order with the Manager — see open question Q-2 in [DECISIONS.md](../../../DECISIONS.md)).
2. Pull mic status (OBJ-07), model readiness (OBJ-02/03), and diarization-engine status into a small read-only view-model.
3. "Recent needing attention" queries SwiftData for recordings whose `RecordingStatus` (OBJ-09) is not `complete`.
4. Wire actions to existing flows (RecordingView, importer, Model Lab).

## Auditor Checklist
- [ ] No duplication of model/mic/status logic — consumes existing sources (incl. OBJ-09 `RecordingStatus`).
- [ ] Initial tab is Dashboard; existing tabs still reachable and functional.
- [ ] Warnings reflect real model state (missing/downloading/failed/repairing).
- [ ] Strict concurrency unchanged; both builds green.
- [ ] Checked against PRD.md, PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md.

## QA Checklist
- [ ] Dashboard shows accurate mic/model/diarization status.
- [ ] Recent-attention list shows recordings needing transcription/labels; tapping jumps correctly.
- [ ] Record/Import/Model Lab actions work from Dashboard.
- [ ] Missing-model warning appears when a required model isn't ready.
- [ ] Regression: all other tabs unaffected.

## Acceptance Criteria
- Dashboard matches PRD §6 required content + actions; calm, reuses theme.
- Tests/builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **ASK USER** first to confirm tab layout (Record tab vs Dashboard-action — open question Q-2 in [DECISIONS.md](../../../DECISIONS.md)).
- **PROCEED** once layout is confirmed and OBJ-09 `RecordingStatus` exists, and the Dashboard renders accurate status.
- **FIX FIRST** if status/warnings are inaccurate or other tabs regress.
- **BLOCKED** if OBJ-09 is not yet gated `PROCEED`.

## Rollback Considerations
Additive view + tab. Revert removes the Dashboard and restores the prior initial tab. No data/schema change.
