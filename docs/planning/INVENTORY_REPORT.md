# Beta 2.1 Preparation — Repository Inventory Report
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

**Date:** 2026-06-28  
**Branch:** codex/project-cleanup  
**Commit:** 5f94870 (Beta 2.0 complete)  
**Tag:** beta-2.0-complete (created and pushed)

> **Superseded note (2026-07-29):** The Python Transcriber 1.x app and Python `dist/` artifacts described in this report were moved out of this repository to the sibling `../Python Transcriber/` folder. This report remains as historical inventory evidence.

---

## Executive Summary

The Transcriber repository contains three distinct app implementations and supporting infrastructure:

1. **Active:** `src/native/Transcriber2/` — the current iOS/macOS Swift app (52 Swift files, ~13.5k lines)
2. **Reference:** `src/legacy-ios/` — older iOS Swift prototype (22 Swift files, no Xcode project)
3. **Independent:** `src/python/` — standalone Python desktop app with PyQt6 GUI (13 source files)
4. **Stale:** `XCode App Build/` — default Xcode template (130 lines, nested .git)

**Key finding:** The apps are architecturally isolated. Swift apps do not reference Python code, and vice versa. Cross-tree modification risk exists but governance docs already flag it as R20.

**Build state:** ~1.6GB of PyInstaller and macOS app artifacts in `dist/` and `native/Builds/`.

---

## Tree-by-Tree Inventory

### 1. `src/native/Transcriber2/` (Active Swift App)

#### Structure
```
src/native/Transcriber2/
├── Transcriber2.xcodeproj/         (Xcode project manifest)
├── Transcriber/                     (Main app target, 26 Swift files)
├── ShareToTranscriber/              (Share extension target, 1 Swift file)
├── TranscriberTests/                (Unit tests, 18 Swift test files)
├── TranscriberUITests/              (UI tests, minimal)
└── tools/                           (Build tools, icon generator)
```

#### Code Metrics
- **Swift files:** 52 total
- **Lines of code:** ~13,513 (includes test code)
- **Breakdown:**
  - Main app: ~28 files
  - Share extension: 1 file
  - Tests: 21 files
  - Tools: 1 file (generate_app_icon.swift)

#### Entry Point
- `Transcriber/Transcriber2App.swift` — SwiftUI app entry point

#### Targets (Xcode)
1. **Transcriber** — main app target (iOS/macOS)
2. **ShareToTranscriber** — iOS share extension
3. **TranscriberTests** — unit test bundle
4. **TranscriberUITests** — UI test bundle

#### Dependencies (Swift Package Manager)
- **FluidAudio** — audio processing (XCRemoteSwiftPackageReference)
- **WhisperKit** — speech-to-text engine (XCRemoteSwiftPackageReference)

#### Key Components (by file)
- **Core transcription:** TranscriptionEngine.swift, TranscriptionSession.swift, FinalTranscriptionModels.swift
- **Diarization:** DiarizationEngine.swift, ProcessingDiagnostics.swift
- **Audio:** AudioRecorder.swift, MicrophoneService.swift, CapturedAudioChunk.swift
- **Models:** ModelRegistry.swift, WhisperModels.swift, TranscriptionModelReadiness.swift
- **UI:** DashboardView.swift, RecordingView.swift, LibraryView.swift, SettingsView.swift
- **Data:** Models.swift, TranscriptionSession.swift
- **Export/Merge:** TranscriptExporter.swift, TranscriptMerger.swift
- **Testing:** Comprehensive test suite with 21 test files

#### Protection Status
**Why protected:** This is the active production codebase. Unvetted edits risk regressions in core transcription, diarization, model download, microphone access, export, and UI logic. Governance docs (AGENTS.md, QA.md) enforce "only work here" for app changes.

---

### 2. `src/python/` (Independent Python Desktop App)

#### Structure
```
src/python/
├── app/                            (Main application, 10 Python files)
│   ├── main.py                     (Entry point, PyQt6 initialization)
│   ├── gui.py                      (PyQt6 GUI)
│   ├── config.py                   (Configuration management)
│   ├── pipeline.py                 (Transcription pipeline, QThread)
│   ├── transcriber.py              (Whisper transcription engine)
│   ├── transcriber_mlx.py          (MLX variant for Apple Silicon)
│   ├── diarizer.py                 (pyannote speaker diarization)
│   ├── merger.py                   (Segment merging)
│   ├── exporter.py                 (Transcript export)
│   └── __init__.py                 (Compatibility patches)
├── tests/                          (2 test files)
│   ├── test_merger.py
│   ├── test_exporter.py
│   └── __init__.py
├── .venv/                          (Python 3.9.6 virtual environment)
├── requirements.txt                (Pinned dependencies)
├── build.sh                        (Deployment script)
└── Transcriber.spec                (PyInstaller configuration)
```

#### Metadata
- **Python version:** 3.9.6 (from Xcode, /Applications/Xcode.app/Contents/Developer/usr/bin/python3)
- **Virtual environment:** .venv (present, 3.9.6)
- **Package manager:** pip

#### Dependencies (from requirements.txt)
```
torch>=2.1.0
torchaudio>=2.1.0
pyannote.audio>=3.1
openai-whisper>=20231117
PyQt6>=6.6
huggingface_hub>=0.20
pyinstaller>=6.5
```

#### PyInstaller Configuration (Transcriber.spec)
- **Entry point:** app/main.py
- **Hidden imports:** pyannote, whisper, torch, torchaudio, sklearn, mlx, mlx_whisper, speechbrain
- **Data files:** speechbrain, torch, torchaudio, pyannote (collected via hooks)
- **Output:** Transcriber.app (macOS bundle)
- **Console:** No (GUI-only)

#### Build System (build.sh)
- Creates `/Applications/Transcriber.app` bundle
- Compiles a native Swift launcher that wraps the Python interpreter
- Sets PATH to ensure ffmpeg (Homebrew) is discoverable
- Copies icon from assets/Transcriber.icns
- Installs to /Applications/

#### External Runtime Requirements
- **ffmpeg** — audio encoding/decoding (via Homebrew, referenced in build.sh and main.py PATH)
- **Hugging Face Hub downloads** — pyannote speaker models (cached locally)
- **PyTorch models** — stored in torch cache
- **Whisper models** — stored in OpenAI cache or via huggingface_hub

#### Entry Point Behavior (main.py)
1. Sets up PATH for ffmpeg (Homebrew critical)
2. Patches huggingface_hub 1.x compatibility (use_auth_token removal)
3. Patches torch 2.6+ weights_only flag for pyannote checkpoints
4. Initializes PyQt6 MainWindow
5. Starts GUI event loop

#### Scope / Non-Scope
- **Not modified during Beta 2.0.** This app predates the Swift app.
- **Governance:** All work must remain in `src/native/Transcriber2/`; Python app edits forbidden.
- **Integration:** No direct integration with Swift app (separate command-line tools or manual export workflows only).

---

### 3. `src/legacy-ios/` (Reference iOS Prototype)

#### Structure
```
src/legacy-ios/
└── TranscriberApp/
    ├── App/
    │   └── TranscriberApp.swift    (App entry point)
    ├── Audio/
    │   └── AudioRecorder.swift
    ├── Diarization/
    │   ├── AgglomerativeClustering.swift
    │   ├── DiarizationPipeline.swift
    │   ├── DiarizationSegment.swift
    │   ├── SpeakerEmbedder.swift
    │   └── VoiceActivityDetector.swift
    ├── Models/
    │   └── ModelManager.swift
    ├── Processing/
    │   ├── SegmentMerger.swift
    │   └── TranscriptExporter.swift
    ├── Storage/
    │   └── Recording.swift
    ├── Transcription/
    │   ├── StreamingTranscriber.swift
    │   ├── TranscriptionSegment.swift
    │   └── WhisperContext.swift
    └── Views/
        ├── Components/
        │   ├── SpeakerBadge.swift
        │   └── WaveformView.swift
        ├── ContentView.swift
        ├── LibraryView.swift
        ├── ModelDownloadView.swift
        ├── RecordingView.swift
        ├── SettingsView.swift
        └── TranscriptView.swift
```

#### Code Metrics
- **Swift files:** 22 total
- **Xcode project:** None (source-only reference)
- **Approximate lines:** 3–5k (not measured; smaller than Transcriber2)

#### Unique Code?
- **Diarization:** Implements custom clustering (AgglomerativeClustering.swift, SpeakerEmbedder.swift) rather than relying on an external package like FluidAudio.
- **Audio recording & storage:** Basic patterns that Transcriber2 evolved from.
- **UI:** Older SwiftUI structure; Transcriber2 has more sophisticated views (Dashboard, Model Lab, Settings refinements).

#### Comparison to Transcriber2
| Area | Legacy iOS | Transcriber2 | Evolution |
|------|-----------|-------------|-----------| 
| **Transcription** | StreamingTranscriber + WhisperContext | TranscriptionEngine + FinalTranscriptionModels | Expanded model management, fallback engines |
| **Diarization** | Custom clustering + embedder | DiarizationEngine + FluidAudio | Delegated to external package |
| **Audio** | Basic AudioRecorder | Microphone service + session management | More robust, handles device selection |
| **Models** | Manual ModelManager | ModelRegistry + readiness checks | Sophisticated download, caching, versioning |
| **Export/Merge** | SegmentMerger, TranscriptExporter | TranscriptMerger, TranscriptExporter | Similar patterns, Transcriber2 more polished |
| **UI** | Basic views | Dashboard, Model Lab, refinements | Transcriber2 significantly more featured |

#### Status
- **Read-only reference.** No governance decision yet on archive vs. keep.
- **UNTANGLING_PLAN.md notes:** "Does `src/legacy-ios/` contain any code NOT already superseded by `src/native/Transcriber2/`?" (U-R5 risk).

---

### 4. `XCode App Build/` (Stale Template)

#### Structure
```
XCode App Build/
└── Transcriber/
    ├── .git/                       (nested git repo)
    ├── Transcriber.xcodeproj/
    ├── Transcriber/                (Swift source)
    │   ├── TranscriberApp.swift    (default template)
    │   ├── ContentView.swift       (SwiftUI default)
    │   ├── Item.swift              (SwiftData default)
    │   └── Assets.xcassets/        (default icon assets)
    ├── TranscriberTests/           (minimal tests)
    └── TranscriberUITests/         (minimal UI tests)
```

#### Metrics
- **Swift files:** 5 (3 source, 2 test)
- **Total lines:** ~130 (mostly boilerplate)
- **Content:** Default Xcode template (SwiftUI + SwiftData)

#### Nested Git Repository
- `.git/` present in `XCode App Build/Transcriber/`
- Config shows local repository, not linked to parent
- **Important:** Do not delete or modify this .git.

#### Transcription Content
- **None.** Pure template code (Item CRUD demo).
- No WhisperKit, no diarization, no audio handling.

#### Status
- **Stale build artifact / template.** Created 2026-06-10 but never used for the active app.
- **Navigation hazard:** Agents might edit this by mistake.
- **Decision pending:** Archive with confirmation, or keep as historical reference?

---

## Cross-Reference Findings

### Swift-to-Python References
- **None found.** Swift app (`src/native/Transcriber2/`) does not import or reference Python app files.

### Python-to-Swift References
- **None found.** Python app (`src/python/`) does not import or reference Swift app files.

### Shared Assets
- **Icon:** `assets/Transcriber.icns` referenced by:
  - `src/python/build.sh` (copies to /Applications/Transcriber.app)
  - Python build system uses this icon
  - Native app may have its own icon in Xcode assets

- **Audio test files:** `test_clip.m4a`, `Kelly Creek Dr.m4a` at repo root
  - Likely used for manual testing or CI
  - No direct code references found

### Legacy iOS References
- **Mentioned in:**
  - DECISIONS.md (governance notes)
  - UNTANGLING_PLAN.md (future cleanup decision)
  - AGENTS.md (listed as read-only reference)
  - QA.md (must not be modified during regression checks)
  - Multiple objective docs (forbidden to edit)
- **Not referenced by active code.**

### Stale Template References
- **Mentioned in:**
  - AGENTS.md (listed as read-only reference)
  - UNTANGLING_PLAN.md (possible archive candidate)
  - QA.md (must not be modified)
  - Objective docs (forbidden to edit)
- **Not referenced by active code.**

---

## Build & Packaging Artifacts

### `dist/` (PyInstaller Output)
- **Total size:** ~1.6 GB
- **Contents:**
  - `dist/Transcriber/` — standalone executable directory (~823 MB)
  - `dist/Transcriber.app/` — macOS app bundle (~829 MB)
  - `dist/Transcriber/_internal/` — bundled dependencies (torch, libtorchaudio, mlx, Qt libraries, Python runtime)
- **Produced by:** `src/python/build.sh` using Transcriber.spec
- **Status:** Build artifact; safe to delete and regenerate

### `native/Builds/` (Xcode Build Artifacts)
- **Contents:** `Transcriber 2.0 Beta.app` (~3 MB directory)
- **Status:** Binary artifact from native build; can be regenerated

---

## Other Notable Items

### Documentation
- **docs/planning/** — 12 governance and planning docs (ARCHITECTURE_REVIEW, QA_STRATEGY, RISK_REGISTER, etc.)
- **Root-level governance:** PLAN.md, OBJECTIVE.md, AGENTS.md, DECISIONS.md, PRD.md, QA.md
- **Objectives tree:** `docs/planning/objectives/` with OBJ-01 through OBJ-20

### Untracked Files
- `docs/planning/UNTANGLING_PLAN.md` — in-progress cleanup plan from prior session

### Configuration
- `.agent_harness/team.config.json` — agent configuration (minimal)
- `.claude/` — Claude Code settings directory
- `.pytest_cache/` — test caching

---

## Potential Cleanup Candidates

### High Confidence (Safe to Archive or Delete)
1. **`native/Builds/Transcriber 2.0 Beta.app`** — binary artifact, can regenerate via Xcode
2. **`dist/`** — PyInstaller artifacts, can regenerate via build.sh
3. **Audio test files** (`test_clip.m4a`, `Kelly Creek Dr.m4a`) — if test coverage migrated to automated tests
4. **`XCode App Build/`** — stale template, no live code
   - **Warning:** Contains nested .git; confirm before deletion

### Medium Confidence (Requires Human Review)
1. **`src/legacy-ios/`** — is it a useful reference?
   - **Question:** Does custom diarization in `Diarization/*.swift` have patterns worth preserving before archiving?
   - **Question:** Any edge-case audio handling not in Transcriber2?
   - **Recommendation:** Compare file-by-file against Transcriber2 first

### Keep
- **`src/native/Transcriber2/`** — active codebase
- **`src/python/`** — independent app, may have separate use cases
- **`assets/`** — icon used by both app builds
- **`docs/planning/`** — governance history
- Root governance docs — part of PLAN

---

## Unknowns & Questions for Human Reviewer

### Decision 1: Legacy iOS Archive
- **Question:** Does `src/legacy-ios/` provide sufficient reference value to justify keeping it?
- **Sub-questions:**
  - Does the custom diarization code contain algorithms or patterns not represented in Transcriber2 + FluidAudio?
  - Is there historical or educational value to preserving it vs. marking it "archived" in DECISIONS.md?
  - If archived, should we keep a copy as a branch tag (e.g., `archive/legacy-ios`) for recovery?

### Decision 2: XCode App Build Cleanup
- **Question:** Should `XCode App Build/` be archived or deleted?
- **Warning:** The nested `.git/` must not be lost unless there's a backup.
- **Sub-question:** Is this needed for any build pipeline or reference?

### Decision 3: Test Audio Files
- **Question:** Are `test_clip.m4a` and `Kelly Creek Dr.m4a` needed?
- **Use:** If they're part of a test suite, they can stay. If ad-hoc, consider archiving to a separate folder.

### Decision 4: Python App Future
- **Question:** Is `src/python/` deprecated in favor of the Swift app, or maintained independently?
- **Implication:** This affects whether to keep it in the repo or archive to a separate project.

### Decision 5: Build Artifacts
- **Question:** Should `dist/` and `native/Builds/` be committed, or generated on-demand?
- **Implication:** If generated on-demand, add to `.gitignore` and document build steps.

---

## Governance & Protection Summary

### Active Path
- **Only work in:** `src/native/Transcriber2/`
- **Source:** AGENTS.md, PLAN.md

### Read-Only Reference (No Edits)
- `src/legacy-ios/`
- `XCode App Build/`
- `src/python/`

### Why Protected
- **Risk R20** (RISK_REGISTER.md): "Agent edits the wrong tree"
- **Enforcement:** `.gitignore`, governance docs, Auditor checks (QA.md)

### Checked in QA Regression Checklists
All regression checklists (QA.md, each objective doc) verify:
- ✓ No `src/python/` changes
- ✓ No `src/legacy-ios/` changes
- ✓ No `XCode App Build/` changes
- ✓ No schema, dependency, or strict-concurrency changes

---

## Summary Table

| Tree | Files | Type | Status | Notes |
|------|-------|------|--------|-------|
| `src/native/Transcriber2/` | 52 Swift | Active app | Protected | 13.5k lines, full test suite, 2 targets + tests |
| `src/python/` | 13 Python | Independent app | Read-only | PyQt6 GUI, Transcriber 1.x, separate build system |
| `src/legacy-ios/` | 22 Swift | Reference | Read-only | Older iOS prototype, custom diarization, no Xcode proj |
| `XCode App Build/` | 5 Swift | Stale template | Read-only | Default Xcode project, nested .git, 130 lines |
| `dist/` | — | Artifacts | Can delete | ~1.6 GB PyInstaller output, regenerable |
| `native/Builds/` | — | Artifacts | Can delete | Xcode build artifacts, regenerable |
| `assets/` | 3 files | Shared | Keep | Icon + UI preview images |
| `docs/planning/` | 12 files | Governance | Keep | Beta 2.0 planning & decisions |

---

## Confidence Levels

- **File counts, line estimates, dependencies:** High (automated scan)
- **Code purpose & relationships:** High (source inspection)
- **Xcode project structure:** High (project.pbxproj inspection)
- **Build systems:** High (build.sh & Transcriber.spec inspection)
- **Unique value of legacy iOS:** Medium (surface-level file comparison; deep code audit needed for archive decision)
- **Runtime requirements:** Medium (requirements.txt & build.sh reviewed; not executed to avoid modifying .venv)

---

## Next Steps (Not Implemented Yet)

Per UNTANGLING_PLAN.md, Beta 2.1 prep will:
1. ✅ **PREP-001 (this task):** Inventory trees and identify cleanup candidates
2. **PREP-002:** Deep-dive comparison of legacy-ios vs. Transcriber2 (if archive is considered)
3. **PREP-003:** Governance update — formalize active path in CLAUDE.md
4. **PREP-004:** Add read-only markers to legacy-ios/ and XCode App Build/ (README files)
5. **PREP-005:** Decide on archive vs. delete for stale trees (with human confirmation)

---

**Report complete. Beta 2.1 prep inventory ready for review.**
