# OBJECTIVE-04 — Default Preload, Status Refresh & Verify-Before-Process

_Phase 1. Depends on OBJ-02, OBJ-03. Closes PRD §12 (F4, F6, F7) and part of C4. RISK R3, R10._

## Mission
Make model readiness self-correcting and pre-flighted: lightweight preload of the default model, status refresh on launch and when Settings opens, and a verify-before-processing step that falls back safely (with a notice) if the selected model isn't usable.

## Scope
- Lightweight default-model preload without heavy onboarding (per PRD §12 F4).
- Refresh model status (file-based, OBJ-02) on app launch and on Settings appear.
- A `verify(model)` that confirms loadability before `processFile`; on failure, fall back to a safer model and surface a notice via the existing completion-note/storage-alert mechanisms.
- Loadability check filled into OBJ-03's verify hook (cheap load probe where practical).

## Out of Scope
- New UI screens (Dashboard etc.).
- Changing the transcription algorithm.

## Worker Instructions
1. Add a launch-time and Settings-appear refresh that re-derives status from files; ensure it's cheap and main-actor-safe (mind the `@MainActor` singletons — RISK R7).
2. Insert verify-before-process in `TranscriptionSession` ahead of transcription; on failure choose a safer fallback model (e.g. lightweight default) and set a user-facing note explaining the fallback.
3. Preload the default model gently (e.g. on first idle), without blocking record/import.
4. Add tests for: verify success path, verify-fail → fallback selection, refresh updates status.

## Auditor Checklist
- [ ] Preload never blocks recording/import (record-first preserved).
- [ ] Fallback path preserves audio + still produces a transcript or a clear retryable failure.
- [ ] No main-actor deadlocks introduced by refresh on launch.
- [ ] Builds green; concurrency intact.

## QA Checklist
- [ ] Launch with no models → status correct; default preloads without blocking UI.
- [ ] Failure injection: make selected model unverifiable → fallback used + notice shown + transcript still produced.
- [ ] Open Settings → status refreshes to match files.
- [ ] Regression: normal record→transcribe→label unaffected.

## Acceptance Criteria
- Status refreshes on launch + Settings open.
- Verify-before-process active with safe fallback + notice.
- Default preload present, non-blocking.
- Tests + builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + verify/fallback/refresh tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). **Device gate:** force-quit/relaunch/**reboot** model persistence is validated by the Human Reviewer here and again in OBJ-20.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** (agent-verifiable parts) then **ASK USER** to run the reboot-persistence device test (PRD §17 Models).
- **FIX FIRST** if fallback can lose the transcript or block recording.

## Rollback Considerations
Additive pre-flight + refresh. Revert removes verify/preload, leaving OBJ-02/03 readiness intact. No data/schema change.
