# OBJECTIVE-17 — Accessibility Pass

_Phase 6. Depends on the UI being largely in place (OBJ-09–15). Closes PRD §15 (J1–J6). RISK R16._

## Mission
Bring the app to Apple's accessibility basics: Dynamic Type, VoiceOver labels/traits (including transcript cards and status dots), contrast in the midnight-blue theme, reachable controls, and status/speaker identity that never relies on color alone.

## Scope
- Dynamic Type: verify text scales; fix any fixed-size truncation on key screens.
- VoiceOver: add accessibility labels/traits to controls, status indicators (the recording dot, model status), and `TranscriptCard` (speaker + timestamp + text read sensibly).
- Contrast audit of `Theme`; fix the flagged `.foregroundStyle(.black)` on primary buttons (use `.white` or computed contrast).
- Non-color status/speaker cues: add text/shape/icon alongside color for speaker identity and recording/status dots.

## Out of Scope
- Full localization (English-first).
- Visual redesign beyond accessibility fixes.

## Worker Instructions
1. Audit each primary screen with Dynamic Type at large sizes (sim accessibility inspector); fix clipping/truncation conservatively.
2. Add `.accessibilityLabel`/`.accessibilityValue`/`.accessibilityAddTraits` where missing; make transcript cards a coherent VoiceOver element.
3. Replace `.foregroundStyle(.black)` per the code-review finding; verify contrast ratios on Theme colors.
4. Add a non-color cue for speaker identity (e.g. speaker initial/shape) and for the recording state (icon/text, not just red dot).

## Auditor Checklist
- [ ] No color-only status/speaker identity remains.
- [ ] Controls + transcript cards have VoiceOver labels/traits.
- [ ] Contrast fixes applied; forced dark mode still coherent.
- [ ] Builds green; concurrency intact; no layout regressions at default sizes.

## QA Checklist
- [ ] Dynamic Type at largest size: key screens readable, no critical truncation.
- [ ] VoiceOver: tab through Record/Library/detail; labels make sense; cards read well.
- [ ] Speaker identity + recording status distinguishable without color.
- [ ] Regression: visual layout intact at default size.

## Acceptance Criteria
- Dynamic Type, VoiceOver, contrast, reachability, and non-color cues meet PRD §15.
- Tests/builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline. Accessibility audited in simulator; final confirmation is a light **device/VoiceOver** check (Human).

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** for agent-verifiable fixes; **ASK USER** for a quick VoiceOver device sanity pass.

## Rollback Considerations
Additive accessibility metadata + small style fixes. Revert removes them with no functional impact.
