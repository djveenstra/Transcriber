# CLAUDE.md — Workspace Registry and Path Guardrails

Last updated: 2026-07-28

Despite the filename, these rules apply to every coding agent and tool operating in this repository.

## 1. Workspace identity

This checkout is the Mac-focused Transcriber workspace:

`/Users/daniel/Library/CloudStorage/OneDrive-Personal/AI Research/Transcription app`

The product code is a native SwiftUI app in `src/native/Transcriber2/`. The accuracy-expansion roadmap strengthens that app in place.

## 2. Registry

| Path | Status | Purpose | Default permission |
|---|---|---|---|
| `src/native/Transcriber2/Transcriber/` | Active | Mac application source | Read/write only within active objective |
| `src/native/Transcriber2/TranscriberTests/` | Active | Unit and integration-style test bundle | Read/write only within active objective |
| `src/native/Transcriber2/TranscriberUITests/` | Active but limited | UI tests | Change only when scoped |
| `src/native/Transcriber2/Transcriber2.xcodeproj/` | Active, high risk | Targets, settings, dependencies | Change only when scoped |
| `src/native/Transcriber2/ShareToTranscriber/` | iOS-origin candidate | Share extension code in Mac-focused checkout | Read; removal/move requires approved objective |
| `src/legacy-ios/` | Reference | Older iOS implementation | Read-only pending archive decision |
| `assets/` | Preserved | Icons and visual references | Read-only unless explicitly scoped |
| `docs/` | Documentation | Product and planning support | Change when objective allows |
| `docs/planning/objectives/OBJECTIVE-01...20` | Historical | Completed Beta 2.0 evidence | Preserve; do not rewrite as new work |
| `VoxBot Expanded PLN.md` | Reference | Accuracy-first design source | Read-only; not governing authority |
| `Voiceprint PLN.md` | Reference | Earlier voiceprint design source | Read-only; not governing authority |
| `test_clip.m4a` | Unresolved | Possible test fixture | Do not use, move, commit, or delete without Daniel |
| `Kelly Creek Dr.m4a` | Private/unresolved | Possible personal recording | Do not inspect beyond metadata, use, move, commit, or delete without Daniel |
| `../iOS Transcriber/` | Separate sibling workspace | iOS product | Out of scope by default |
| `../Python Transcriber/` | Separate sibling workspace | Legacy Python application | Out of scope |

Generated Xcode data, downloaded models, compiled apps, private benchmarks, and application data are not source files and must not be added to the repository.

## 3. Active architecture map

The current Mac baseline includes:

- `Transcriber2App.swift` — app entry and SwiftData container.
- `RootView.swift` — Dashboard, Library, Model Lab, and Settings navigation.
- `Models.swift` — `Recording`, transcript types, status derivation, and storage paths.
- `TranscriptionSession.swift` — UI-facing state machine and current processing orchestrator.
- `TranscriptionEngine.swift` — actor protocol and WhisperKit implementation.
- `ParakeetTranscriptionEngines.swift` — FluidAudio Parakeet engines, currently iOS-gated where applicable.
- `DiarizationEngine.swift` — actor protocol and FluidAudio Sortformer implementation.
- `TranscriptMerger.swift` — current temporal speaker assignment and smoothing.
- `ModelRegistry.swift` / `TranscriptionModelReadiness.swift` — model lifecycle and file-backed readiness.
- `ProcessingPhase.swift` / `ProcessingDiagnostics.swift` — progress and diagnostic presentation.
- `RecordingView.swift`, `LibraryView.swift`, `DashboardView.swift`, `ModelLabView.swift`, and `SettingsView.swift` — working product surfaces.

Do not replace these pieces because a reference plan sketches a different architecture. First add tests and contracts, then extract or replace one responsibility at a time.

## 4. Objective path contract

Every implementation objective must name:

- Target app: `Transcriber Mac`.
- Risk tier.
- Allowed paths.
- Forbidden paths.
- Whether `project.pbxproj`, package pins, entitlements, schema, user data, model caches, or application storage may change.
- Whether private benchmark audio may be accessed.
- Exact removal targets, if any.

If a needed file is outside allowed paths, stop and return to the Manager. Do not “just fix” an adjacent app or reference tree.

## 5. Cross-platform rules

1. Mac behavior is the authority in this checkout.
2. iOS implementation belongs in the sibling workspace.
3. Shared Swift files may still contain `#if os(iOS)` code from before the split.
4. Do not delete iOS-origin code until an objective proves the sibling owns it and the Mac project no longer needs it.
5. Do not make a Mac architecture worse solely to preserve an unconfirmed mobile need; surface the conflict and coordinate it explicitly.

## 6. Dependency and model rules

The current project pins WhisperKit and FluidAudio by revision. Any revision change or new runtime is its own High/Critical objective.

Before adding a model or runtime, verify:

- License and distribution terms.
- Apple Silicon and macOS support.
- App Sandbox and signing implications.
- Download, storage, update, repair, and removal behavior.
- Offline behavior.
- Memory, thermal, timing, and cancellation behavior.
- Normalized result quality and provenance.
- Failure isolation and rollback.
- Benchmark benefit.

Named candidates in the VoxBot reference plan are hypotheses until these checks pass.

## 7. Private data and fixtures

- Never assume a repository audio file is safe test data.
- Do not commit private benchmark audio, voiceprints, embeddings, enrollment samples, or derived speech clips.
- A dataset manifest may reference private files outside Git after Daniel approves them.
- Tests should use generated audio, tiny approved fixtures, fakes, or metadata-only placeholders whenever possible.
- Logs and reports must avoid full private paths and transcript content unless the objective explicitly needs them.

## 8. Removal protocol

For any planned code, target, asset, or reference removal:

1. Resolve exact references with read-only checks.
2. Identify the behavior and owner.
3. Confirm migration or replacement.
4. Preserve unique history when useful.
5. Run baseline validation before and after.
6. Record what was removed and how to recover it.

Deletion of user data, private audio, profiles, or enrollment samples occurs only through tested user-initiated product behavior or an explicitly approved migration procedure.

## 9. Historical planning

The completed Beta 2.0 objective files and older planning analyses explain how the current core was built. Some supporting documents still describe the pre-split iPhone-first state and must be treated as historical unless the active PRD or objective explicitly refreshes them.

Conflict priority is:

Daniel’s explicit current instruction → active `OBJECTIVE.md` → `PRD.md` → `PLAN.md` → approved `DECISIONS.md` → `AGENTS.md` → this registry → supporting and historical references.
