# OBJECTIVE-18 — Mac Companion Parity

_Phase 7. Depends on OBJ-09–16 (features exist to mirror). Closes PRD §4/§17 Mac (K1–K4). RISK R13._

## Mission
Verify and complete the Mac companion experience: open/import, playback, transcript review, and share/export all work; bring Model Lab and model workflows to Mac where feasible; and document any intentional iPhone-first gaps.

## Scope
- Audit each Mac flow (open/import, play, review, share/export) against the iOS feature set delivered so far.
- Make Model Lab available on macOS if feasible (it's currently `#if os(iOS)`); if not feasible, document why.
- Ensure new screens (Dashboard, status badges, diagnostics, progress timeline) render correctly on macOS.

## Out of Scope
- macOS-specific redesign.
- iOS-only hardware features (live Parakeet EOU is iOS).

## Worker Instructions
1. Build + run the macOS target; walk every flow; list gaps vs iOS.
2. For Model Lab on Mac: evaluate lifting the `#if os(iOS)` guard (WhisperKit models work on macOS). If the Parakeet path isn't available on macOS, scope Model Lab to the Whisper models there.
3. Fix layout/availability issues from the new iOS-era screens on macOS.
4. Document intentional gaps in [DECISIONS.md](../../../DECISIONS.md).

## Auditor Checklist
- [ ] No iOS regressions from macOS-enabling changes (`#if` branches correct).
- [ ] Mac flows function; gaps documented intentionally.
- [ ] Builds green on both platforms; concurrency intact.

## QA Checklist
- [ ] macOS: open/import a recording, play, review transcript, share/export.
- [ ] Model Lab on Mac (if enabled) compares Whisper models + report.
- [ ] New screens render correctly on macOS.
- [ ] Regression: iOS unaffected.

## Acceptance Criteria
- Mac supports open/import/play/review/share; Model Lab on Mac where feasible; gaps documented.
- Tests/builds green on both platforms.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline (both destinations). **Device/Mac gate:** Human Reviewer confirms on a real Mac.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Mac hardware confirmation is a Human gate.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** for agent-verifiable parity; **ASK USER** for Mac hardware confirmation and to ratify intentional gaps.

## Rollback Considerations
Mostly `#if` adjustments + layout fixes. Revert restores iOS-only Model Lab and prior macOS behavior. No data/schema change.
