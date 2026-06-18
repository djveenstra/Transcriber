# OBJECTIVE-02 — File-Based Model Readiness

_Phase 1. Depends on OBJ-01. Closes part of RISK R3 / PRD §12 (F1, F2)._

## Mission
Make transcription-model readiness reflect **actual on-device files** (and, where practical, loadability), replacing the in-memory/UserDefaults Whisper "downloaded" flag so readiness is honest after force-quit, relaunch, and reboot.

## Scope
- Add a single readiness check usable by both providers: Parakeet already uses `AsrModels.modelsExist(at:version:)`; add an equivalent file-existence check for WhisperKit's on-disk model cache.
- Make `FinalTranscriptionModelChoice.isDownloaded` (and the macOS Whisper path) consult files, not the in-session `downloadedModelIDs` set.
- Keep the UserDefaults set as an optional fast-path hint only, reconciled against files.
- Add unit tests for the readiness logic using a temp directory fixture.

## Out of Scope
- New model states / Repair UI (OBJ-03).
- Launch/Settings refresh wiring and verify-before-process (OBJ-04).
- Changing what/how models download.

## Worker Instructions
1. Investigate WhisperKit's on-disk cache location (its download API; do not bump the dependency). Implement a file-existence/manifest check; if a path isn't reliably discoverable, document the limitation and use the best available signal, noting it for OBJ-04's loadability verify.
2. Route all "is this model present?" queries through one function/type (seed of the model registry that OBJ-03 will formalize).
3. Preserve current behavior when files are present; only change the source of truth.
4. Add tests with a fake cache directory proving present/absent/partial detection.

## Auditor Checklist
- [ ] Readiness now derives from files; UserDefaults is only a hint, reconciled.
- [ ] No download/inference behavior changed.
- [ ] Single source of truth for presence checks (no scattered ad-hoc checks left).
- [ ] Strict concurrency unchanged; both builds green.

## QA Checklist
- [ ] Unit tests for present/absent/partial pass.
- [ ] Manual: with a model downloaded, readiness shows ready; simulate deletion of files → shows not-ready (sim or temp dir test).
- [ ] Regression: download flow still works; Model Lab "downloaded" labels still correct.

## Acceptance Criteria
- Whisper + Parakeet readiness both file-based behind one check.
- Readiness survives a simulated relaunch (no reliance on in-memory set).
- Tests green; builds green.

## Validation Commands
[PLAN.md](../../../PLAN.md) baseline + new readiness tests.

## Definition of Done
Per [AGENTS.md §4](../../../AGENTS.md). Real reboot persistence is a **device gate** validated later in OBJ-04/OBJ-20.

## Gate Decision (see [AGENTS.md §6](../../../AGENTS.md) for definitions)
- **PROCEED** if file-based readiness + tests land green.
- **ASK USER** if WhisperKit's cache path is not reliably discoverable (decide between manifest heuristic vs loadability-only check).
- **FIX FIRST** if any readiness path still depends solely on in-memory state.

## Rollback Considerations
Additive check + redirected source of truth. Revert restores the UserDefaults-based flag. No data/schema change.
