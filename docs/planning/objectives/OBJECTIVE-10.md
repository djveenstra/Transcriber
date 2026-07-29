# OBJECTIVE-10 — Dashboard Tab
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

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

## Completion Report — 2026-06-20

### Worker Report
- Added `DashboardView` as the initial tab and kept `Record`, `Library`, and `Settings` reachable.
- Wired Dashboard Record and Import actions into the existing `RecordingView` flows instead of creating a new recording/import job system.
- Dashboard recent work derives each row from OBJ-09 `RecordingStatus` via `recording.recordingStatus(activity:)`; it filters non-complete statuses through a small helper and does not duplicate retry/transcript booleans.
- Model readiness is sourced from `FinalModelDownloader`, `ModelRegistry`, `ModelRegistry.fileSnapshot`, and `ModelStatus`; Dashboard warnings cover missing, downloading, repairing, failed, verifying, and downloaded-not-yet-checked states.
- Microphone status is sourced from `MicrophoneService` and the persisted microphone selection; unavailable saved inputs are shown as Automatic fallback without inventing hardware state.
- Speaker-labeling status is read-only: active speaker-labeling work is detected from `RecordingStatusActivityStore`, otherwise Dashboard truthfully reports Sortformer Balanced V2 and notes that separate speaker-model readiness is not available yet.
- iOS Dashboard opens the existing nested `ModelLabView`; macOS shows a disabled Model Lab action because the current Model Lab view is iOS-only. Model Lab was not promoted to a top-level tab.

### Files Touched
- `src/native/Transcriber2/Transcriber/DashboardView.swift`
- `src/native/Transcriber2/Transcriber/RootView.swift`
- `src/native/Transcriber2/Transcriber/RecordingView.swift`
- `src/native/Transcriber2/Transcriber/LibraryView.swift`
- `src/native/Transcriber2/TranscriberTests/DashboardTests.swift`
- `QA.md`
- `PLAN.md`
- `OBJECTIVE.md`
- `docs/planning/objectives/OBJECTIVE-10.md`

### Tests Added
- `DashboardTests.recentAttentionFiltersAndSortsByRecordingStatus()`
- `DashboardTests.recentAttentionLimitIsAppliedAfterFilteringAndSorting()`
- `DashboardTests.modelWarningsCoverMissingDownloadingRepairingAndFailedStates()`
- `DashboardTests.microphoneSummaryReportsUnavailableSavedInputWithoutInventingActiveHardware()`

### Validation Evidence
- macOS build: PASS.
- iOS simulator build: PASS.
- Focused `DashboardTests`: PASS.
- Full `TranscriberTests`: PASS, 97/97.
- `git diff --check`: PASS.
- Existing AppIntents metadata extraction warning remains unchanged: `No AppIntents.framework dependency found`.

### Auditor Alignment
- ALIGNED. Touched paths are limited to the active native app/tests and planning/QA docs.
- No dependency bump, no `Recording` schema change, no strict-concurrency weakening, no `src/python/`, `src/legacy-ios/`, or `XCode App Build/` edits.
- OBJ-11 Model Lab tab promotion and all listed out-of-scope work were not implemented.

### Gate Recommendation
- PROCEED.

### Deferred Human/Device Checks
- No OBJ-10-specific Human-owned hardware gate. Real iPhone review of Dashboard layout and actions is recommended during normal beta acceptance.
