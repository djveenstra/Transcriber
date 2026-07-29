# OBJECTIVE-14 — Phase-Timeline Progress UI
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

_Phase 5. Depends on OBJ-13 (shared state patterns). Closes PRD §13 Progress UI (G1, G2). RISK R17._

## Mission
Replace the single progress bar with a structured, calm phase timeline showing the current phase, rough %/activity, elapsed time, and Cancel/Retry/Details affordances — without gold-plating (per SELF_CRITIQUE §2).

## Scope
- A `ProcessingPhase` model: `savingRecording / preparingModel / transcribing / savingTranscript / identifyingSpeakers / savingSpeakerLabels / exporting` (PRD §13 core phases).
- Drive the model from `TranscriptionSession` state transitions (replace the ad-hoc `processing(String)` payload with structured phases; keep a string for display).
- Progress UI shows: current phase, %/activity, elapsed timer, Cancel, Retry (where relevant), and a Details disclosure.
- Reuse across RecordingView, RecordingDetailView (retry), SharedAudioDetailView.

## Out of Scope
- Diagnostics content inside Details (OBJ-15 fills it).
- Animations/scrubbing/timeline-graphics (explicitly excluded).

## Worker Instructions
1. Introduce `ProcessingPhase` and map current `state = .processing("…")` call sites to it; keep human-readable text derived from the phase.
2. Build a compact phase view bound to the session; add an elapsed-time `TimelineView`.
3. Keep Cancel wired to the existing `cancelProcessing`; surface Retry where the session already supports it.
4. Details disclosure can start minimal (phase + elapsed); OBJ-15 enriches it.

## Auditor Checklist
- [ ] Phase model maps 1:1 to PRD core phases; no state semantics lost.
- [ ] Cancel/Retry behavior unchanged functionally.
- [ ] No new heavy animation; calm per PRD §16.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] During processing, the correct phase + elapsed time show and advance.
- [ ] Cancel still cancels safely (transcript/audio preserved).
- [ ] Retry where relevant still works.
- [ ] Regression: completion + failure states unaffected.

## Acceptance Criteria
- Structured phase timeline with elapsed/%/cancel/retry/details replaces the bare bar.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + phase-mapping tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if phases + elapsed + controls land without behavior regression.
- **FIX FIRST** if any state transition is lost or Cancel/Retry semantics change.

## Rollback Considerations
Refactor of the processing presentation + a phase enum. Revert restores the single bar. No data/schema change; session state semantics preserved either way.

## Completion Report — 2026-06-20

### Worker
- Files touched: `src/native/Transcriber2/Transcriber/ProcessingPhase.swift`, `src/native/Transcriber2/Transcriber/TranscriptionSession.swift`, `src/native/Transcriber2/Transcriber/RecordingView.swift`, `src/native/Transcriber2/Transcriber/LibraryView.swift`, `src/native/Transcriber2/TranscriberTests/ProcessingPhaseTests.swift`, plus planning/QA docs.
- Added `ProcessingPhase` with the PRD core phases: `savingRecording`, `preparingModel`, `transcribing`, `savingTranscript`, `identifyingSpeakers`, `savingSpeakerLabels`, and `exporting`.
- Replaced `TranscriptionSession.State.processing(String)` with `processing(ProcessingPhase)`, added elapsed-time tracking for active processing runs, and mapped existing processing transitions to structured phases.
- Added a reusable `ProcessingTimelineView` with current phase, rough percent/activity, elapsed time, Cancel, optional Retry support, and minimal Details containing phase, elapsed time, and safe static context.
- Reused the progress presentation in `RecordingView`, `RecordingDetailView`, and `SharedAudioDetailView`.
- Cancel and retry behavior stay on existing paths: `cancelProcessing`, `retryTranscription`, `retrySpeakerLabels`, and `retryCurrentSpeakerLabels`. Speaker-label retry continues to use stored `rawTranscription` instead of rerunning transcription.
- Deferred OBJ-15 diagnostics: no model load time, processing time, realtime factor, fallback flag, or failure metric capture was added.

### Auditor
- ALIGNED. The phase model maps to PRD §13 core phases, and shared UI is reused instead of duplicating per-screen progress blocks.
- Cancel/Retry semantics are preserved; new buttons call existing session methods and do not add new retry behavior.
- No OBJ-15 diagnostics capture was started.
- No transcription algorithm, diarization algorithm, SwiftData schema, dependency, project-setting, strict-concurrency, `src/python/`, `src/legacy-ios/`, or `XCode App Build/` changes were made.
- No OBJ-15+ export, accessibility, Mac parity, cancellation-hardening, or acceptance work was started.

### QA
- Focused tests added in `ProcessingPhaseTests`: phase coverage, legacy-message mapping, display copy, elapsed formatting, progress/cancel/retry presentation helpers, and structured processing-state carrying.
- Validation passed: macOS build PASS; iOS simulator build PASS; `TranscriberTests` PASS (118/118); `git diff --check` PASS.
- QA evidence: [QA.md](../../../QA.md#obj-14--phase-timeline-progress-ui--2026-06-20).
- Device gates: none specific to OBJ-14. Real-device visual tap-through of the timeline during processing is useful beta review, but not a blocking Human-owned hardware gate.

### Manager Gate
- Gate recommendation: **PROCEED**.
- OBJ-14 scope is complete in agent-verifiable scope.
- No Human/product decision is needed for OBJ-14.
