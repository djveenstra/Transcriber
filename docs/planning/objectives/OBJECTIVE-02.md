# OBJECTIVE-02 — File-Based Model Readiness
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

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

## Completion Report — 2026-06-18

**Gate:** PROCEED

**Worker report:**
- Files touched: `src/native/Transcriber2/Transcriber/TranscriptionModelReadiness.swift`, `src/native/Transcriber2/Transcriber/FinalTranscriptionModels.swift`, `src/native/Transcriber2/Transcriber/WhisperModels.swift`, `src/native/Transcriber2/TranscriberTests/TranscriptionModelReadinessTests.swift`, `QA.md`, `PLAN.md`, `OBJECTIVE.md`, and this objective file.
- Assumptions: WhisperKit's default on-disk cache path is reliable for this pinned revision because `HubApi` defaults to `Documents/huggingface`, `WhisperKit.download` uses `models/argmaxinc/whisperkit-coreml`, and the active allowed model IDs match unique remote model folder names. A full model loadability probe is deferred to OBJ-04/OBJ-20 device validation rather than performed during every readiness read.
- Readiness logic before vs after: before, Whisper readiness used `WhisperModelDownloader.downloadedModelIDs` from in-memory/UserDefaults state while Parakeet checked files directly. After, `FinalTranscriptionModelChoice.isDownloaded` routes through `TranscriptionModelReadiness`; Whisper checks required Core ML model files on disk and reconciles stale hints, while Parakeet uses the existing `AsrModels.modelsExist(at:version:)` file check behind the same helper.
- Tests added or updated: added `TranscriptionModelReadinessTests` for complete Whisper compiled-model fixtures, partial/missing fixtures, `.mlpackage` fixtures, and stale remembered downloaded-flag reconciliation.
- Validation commands run: macOS build PASS; iOS-simulator build PASS; focused readiness tests PASS; full `TranscriberTests` bundle PASS per DECISIONS.md D-006.
- Test output: 53/53 unit tests passed; focused readiness test run passed all 4 new tests.
- Objective items completed: single readiness helper added; Whisper + Parakeet readiness routed through one check; UserDefaults hint reconciled against files; temp-directory readiness tests added; no download/inference behavior intentionally changed.
- Deferred/blocked: real force-quit/relaunch/reboot persistence and offline behavior remain Human-owned device gates for later OBJ-04/OBJ-20 validation. No blocker.

**Auditor report:** ALIGNED. Diff is inside `src/native/Transcriber2/` plus planning docs; no `src/python/`, `src/legacy-ios/`, `XCode App Build/`, schema, dependency, strict-concurrency, microphone, navigation, Dashboard, or Repair/Redownload changes. Readiness no longer depends solely on in-memory state.

**QA report:** PASS. Evidence recorded in [QA.md](../../../QA.md#obj-02--file-based-model-readiness--2026-06-18). Device reboot/offline persistence was explicitly not claimed complete.
