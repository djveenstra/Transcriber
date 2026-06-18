# OBJECTIVE-05 — Microphone Abstraction & Selection Backend

_Phase 2. Depends on OBJ-01. Closes PRD §8 (B7, partial). RISK R11._

## Mission
Introduce an input-discovery and selection service so the app can enumerate available microphones (automatic/default, built-in, Bluetooth/headset, any named platform input) and persist the user's choice — without yet changing recording behavior beyond honoring the selection.

## Scope
- A `MicrophoneService` (or equivalent) that lists available inputs per platform (`AVAudioSession.availableInputs` on iOS; appropriate API on macOS) with stable identifiers + display names.
- Persist the selected input id (UserDefaults), with "Automatic" as default.
- `AudioRecorder.prepareForRecording()` honors the selection when available (sets preferred input on iOS).
- Unit tests for selection persistence + "automatic" default + unknown-id handling.

## Out of Scope
- Test Mic UI + meter (OBJ-06).
- Fallback notice + active-mic display (OBJ-07).
- Any Dashboard/Settings visual polish beyond a basic picker.

## Worker Instructions
1. Build the service as a thin, testable layer; keep AVFoundation specifics behind it so tests can use a fake input list.
2. Add a basic microphone picker to Settings (PRD §8). "Automatic" first.
3. In `prepareForRecording`, if a specific input is selected and present, set it as preferred; otherwise keep current default behavior (no behavior regression).
4. Do not change tap/format/recording logic.

## Auditor Checklist
- [ ] Default ("Automatic") reproduces today's behavior exactly.
- [ ] Selection persisted; unknown/absent id falls through to automatic.
- [ ] No change to audio capture/format/file writing.
- [ ] iOS/macOS branches both compile; concurrency intact.

## QA Checklist
- [ ] Picker lists inputs (sim shows at least default).
- [ ] Selecting/relaunching preserves choice.
- [ ] Recording still works with Automatic and with an explicit selection.
- [ ] Regression: record→transcript unaffected.

## Acceptance Criteria
- Inputs enumerable; selection persists; recorder honors it when available.
- Tests + builds green; no recording regression.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + microphone-service tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Real Bluetooth/headset enumeration is a **device gate** (OBJ-08/20).

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if enumeration + persistence + honoring land green.
- **ASK USER** for guidance only if macOS input selection API requires a product decision.

## Rollback Considerations
Additive service + picker; recorder change is guarded by "selection present." Revert returns to default-input behavior. No data/schema change.
