# OBJECTIVE-20 — Beta Acceptance Pass + `TranscriptionSession` Decomposition + Tech Debt

_Phase 8. Final. Depends on all prior objectives. Closes PRD §17 full acceptance. RISK R5, R18, R21._

## Mission
Run the complete PRD §17 acceptance matrix (with the Human Reviewer owning device portions), then pay down the highest-value tech debt without changing behavior: decompose the oversized `TranscriptionSession`, add a language setting, and fix the fragile speaker-color parsing.

## Scope
- **Acceptance:** execute every PRD §17 test (Recording 5/15/30-min + background/lock; Import; Transcription & diarization; Cancellation & failure; Models incl. reboot persistence; Export; Model Lab; Mac). Record results in [QA.md](../../../QA.md).
- **Decomposition (behavior-preserving):** extract persistence (`preserveRecording`/`updateSavedRecording`/`saveCompletedRecording`) and model-selection (`selectedFinalModelID`/`prepare`/`transcribe`/`unload`) into focused coordinators; tests must pass unchanged.
- **Language setting:** add an English-default language setting passed to the engines (removes hardcoded `"en"`/`.english`).
- **Speaker-color fix:** parse the speaker index explicitly (split on `_`) instead of filtering digits.

## Out of Scope
- New features.
- Diarization accuracy research (roadmap).

## Worker Instructions
1. Treat decomposition as pure refactor: move code, keep behavior, keep public observable state identical; run the full test suite before/after to prove parity.
2. Add a `Settings` language picker (default English); thread it through `WhisperKit` decoding options + Parakeet language. Keep English the default so behavior is unchanged unless the user opts in.
3. Replace `segment.speaker.filter(\.isNumber)` color logic with explicit index parsing (handle `SPEAKER_NN` and `S1`).
4. Run the acceptance matrix; hand device portions to the Human Reviewer with the QA.md scripts.

## Auditor Checklist
- [ ] Decomposition changes no observable behavior; tests unchanged + green.
- [ ] Language defaults to English (no silent behavior change for existing users).
- [ ] Speaker-color parsing correct for `SPEAKER_10`, `SPEAKER_01`, `S1`.
- [ ] No scope creep into new features; builds green; concurrency intact.

## QA Checklist
- [ ] Full PRD §17 matrix executed; agent-verifiable items pass; device items handed off.
- [ ] Refactor: every prior test still passes; no UI/flow change.
- [ ] Language picker works; English default unchanged.
- [ ] Speaker colors stable/correct across many speakers.

## Acceptance Criteria
- PRD §17 acceptance recorded as PASS (agent portions) with device portions confirmed by the Human Reviewer.
- `TranscriptionSession` decomposed behavior-identically; language setting + color fix landed.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline (full suite) + device runs per [QA.md](../../../QA.md). **Device gates (Human):** 30-min reliability, reboot model persistence, airplane-mode offline, background/lock, performance, battery.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Beta is acceptance-complete only when the Human Reviewer signs off the device matrix.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** for agent-verifiable acceptance + refactor + fixes.
- **ASK USER** to run/sign off the device acceptance matrix → milestone approval.
- **FIX FIRST** if the refactor changes any behavior or a test regresses.

## Rollback Considerations
Refactor is behavior-preserving and revertible objective-by-objective. Language setting is additive (English default). Color fix is local. No data/schema change.
