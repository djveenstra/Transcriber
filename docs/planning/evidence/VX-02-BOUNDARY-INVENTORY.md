# VX-02 Mac/iOS Boundary and Removal Inventory

Inventory version: `vx02-boundary-v1`

Captured: 2026-07-29

Scope: read-only ownership and removal-candidate inspection

## 1. Workspace boundary

### Mac workspace

- Product authority: this repository’s current PRD, PLAN, and decisions.
- Active product path: `src/native/Transcriber2/`.
- Current branch: `codex/voxbot-accuracy-phase-0`.
- Worktree: dirty before Phase 0; preserved.

### iOS sibling

- Location: sibling `iOS Transcriber` workspace.
- Its governance identifies it as the iOS product workspace and points to `src/native/Transcriber2/` as its active app.
- It is currently a folder without a Git repository at its root.
- Its `src/native/Transcriber2/` tree contains 71 non-`.DS_Store` files.
- `diff -qr` against the Mac workspace’s `src/native/Transcriber2/` returned exit 0: the two native trees were byte-identical at inspection time.
- The sibling also retains the same 24-file `src/legacy-ios/` reference tree.

Conclusion: every iOS behavior currently present in the Mac native tree is present in the sibling at this snapshot. This proves copied ownership, not durable backup or permission to remove Mac files. A future structural removal must first put the sibling under a Human-approved backup/version-control boundary and validate its iOS build.

## 2. Active Xcode targets and share extension

The shared Xcode project contains four native targets:

| Target | Current platforms | Mac relevance | Classification |
|---|---|---|---|
| `Transcriber` | iPhone, iPhone Simulator, macOS | Active Mac product and copied iOS product | Retain now; future Mac-only project narrowing is a separate High-risk objective |
| `ShareToTranscriber` | iPhone and iPhone Simulator only | Not built for macOS; embedded with an iOS platform filter | Remove later from the Mac workspace only, after sibling backup/build proof and project-level rollback |
| `TranscriberTests` | iOS, macOS, and inherited extra platforms | Current Mac unit baseline plus shared-origin tests | Retain; later platform cleanup must be scoped and measured |
| `TranscriberUITests` | iOS, macOS, and inherited extra platforms | Active but limited Mac UI-test source | Retain; no evidence supports removal |

The iOS share-extension unit is:

- `ShareToTranscriber/ShareViewController.swift`
- `ShareToTranscriber/ShareToTranscriber.entitlements`
- `ShareToTranscriber-Info.plist`
- the `ShareToTranscriber` target, product, build configurations, dependency, and iOS-only embed phase in `project.pbxproj`

The controller accepts audio/file share items and writes them into the application-group inbox. The target and its files are byte-identical in the iOS sibling.

Future classification: **remove later from the Mac workspace**, not “move”—the sibling already has the files. This must be one scoped project objective with:

1. sibling backup/version-control proof;
2. sibling iOS Simulator build before the Mac change;
3. Mac build/tests before and after;
4. exact Xcode project reference removal;
5. a diff proving only the Mac workspace changed;
6. rollback by restoring the project/file set.

### App-group inbox is not automatically removable

The main app’s `Transcriber.entitlements`, `SharedAudioInbox.swift`, and Library shared-inbox UI are compiled for Mac and iOS. Removing the iOS extension does not prove these Mac paths are unused or undesirable. They are **unresolved/retain** until a future objective tests Mac behavior and Daniel decides whether the Mac should keep app-group/shared-inbox compatibility.

## 3. Platform-conditional production code

Eleven production Swift files contain iOS branches:

| File | iOS-specific responsibility | Classification |
|---|---|---|
| `ParakeetTranscriptionEngines.swift` | Entire file: Parakeet EOU live preview and Parakeet final engine | Remove later from Mac workspace only as part of project narrowing |
| `TranscriptionSession.swift` | Live Parakeet lifecycle, iOS queueing, iOS final-model selection/load/transcribe/unload, iOS cancellation cleanup | Remove later only as one characterized orchestration change; High risk |
| `FinalTranscriptionModels.swift` | iOS selection persistence; shared model catalog/downloader logic remains relevant | Retain file; later remove only proven iOS branches |
| `ModelLabView.swift` | iOS Parakeet choices, phone-memory copy, Parakeet runner | Retain file; later remove only proven iOS branches |
| `SettingsView.swift` | iOS model picker, Parakeet/live labels, iOS selection status | Retain file; later remove only proven iOS branches |
| `DashboardView.swift` | iOS final-model preference key | Retain file; later remove branch when Mac project is Mac-only |
| `AudioRecorder.swift` | `AVAudioSession`, iOS interruption/route/media-reset handling, background task | Retain file; later remove only iOS branches after Mac recording characterization |
| `MicrophoneService.swift` | iOS input discovery/preferred routes, Bluetooth refresh notifications/retries | Retain file; later remove only iOS branches after Mac microphone characterization |
| `LibraryView.swift` | iOS title behavior and playback `AVAudioSession` activation/deactivation | Retain file; later remove only iOS branches after playback regression tests |
| `RecordingView.swift` | iOS title/copy, Parakeet status text, UIKit share sheet | Retain file; later remove only iOS branches after Mac UI/export checks |
| `DashboardView.swift` | iOS selected-model storage | Retain file; included above |

There are 57 `#if`/`#elseif os(iOS)` occurrences across ten unique production files plus the whole-file Parakeet guard. Three production files contain Mac-specific branches: `RecordingView.swift`, `Transcriber2App.swift`, and `TranscriptionSession.swift`. `ModelLabTests.swift` contains a Mac-specific test branch.

Classification: **retain now**. The iOS blocks are owned by the sibling, but piecemeal deletion while the Mac Xcode target still supports iOS would break the shared project. A future High-risk “Mac project narrowing” objective should:

1. characterize Mac recording, microphone, playback, session, settings, dashboard, Model Lab, export, and cancellation behavior;
2. narrow the Mac project’s supported platforms;
3. remove only unreachable iOS branches and iOS-only files from this checkout;
4. preserve shared data types and Mac branches;
5. run Mac build/full tests and the sibling iOS build;
6. audit the large `TranscriptionSession` diff and dependency/resource behavior.

## 4. Legacy and stale trees

| Item | Evidence | Classification | Human decision |
|---|---|---|---|
| `src/legacy-ios/` | 24 tracked files; no active-project references; contains unique custom clustering, VAD, speaker embedding, and Whisper bridge reference code; identical copy exists in sibling | Archive or remove later only after durable preservation; unresolved | Keep in Mac, move ownership to versioned iOS sibling, archive in a tag/package, or delete after preservation |
| `XCode App Build/` | Ignored by outer Git; default SwiftData template; nested Git repo on clean `main`, commit `f4abfad` | Archive/remove later; unresolved | Preserve nested repo as archive, keep marked in place, or remove after verified archive |
| `native/Builds/Transcriber 2.0 Beta.app` | Ignored generated/signed application bundle; not source | Remove later only after Daniel confirms it is not the only desired install/archive artifact | Keep as local artifact or delete after regeneration/archive proof |
| `.DS_Store` files | Finder metadata, not product source | Remove later mechanically and keep ignored; low value | May be included in an approved cleanup objective |

`src/legacy-ios/` is not superfluous solely because the active app uses WhisperKit and FluidAudio. Its unique implementation is historical/reference value. The sibling copy helps establish ownership, but the sibling’s lack of root Git history means it is not yet a sufficient recovery mechanism.

## 5. Assets and research material

| Item | Current evidence | Classification |
|---|---|---|
| `assets/Transcriber.icns` | Tracked; historical docs and the external Python build refer to it | Retain |
| `assets/OLED_1.png` | Tracked visual reference; no active Swift reference found | Retain until Daniel decides whether historical visual references should be archived |
| `assets/actual_oled_ui_preview.png` | Tracked visual reference; no active Swift reference found | Retain until Daniel decides whether historical visual references should be archived |
| `Voiceprint-downloads/` | Ignored research area; not production source; contains a README | Retain as ignored research material; never fold into application code during cleanup |

No asset or research content was opened for semantic reuse or changed.

## 6. Governance and historical documentation

- Root governance files differ between the Mac and iOS workspaces, as they should after the split.
- The License is identical.
- Mac historical Beta 2.0 objectives and supporting analyses retain evidence and links used by QA.
- Duplicate names across workspaces are not redundant files within one product: each workspace needs its own authority and history.

Classification:

- Current Mac governance: **retain**.
- Sibling governance: **owned by sibling; do not modify from Mac objectives**.
- Historical Mac objectives/evidence: **retain** unless a later docs-only archive design preserves links and append-only evidence.
- Stale pre-split descriptions: correct through small superseding notes, not deletion or historical rewriting.

No broad “deduplicate governance” objective is recommended.

## 7. Root audio

Both root `.m4a` files are untracked and ignored:

- `test_clip.m4a`
- `Kelly Creek Dr.m4a`

No content, checksum, codec, duration, extended metadata, or transcript was inspected.

Classification: **unresolved**. Daniel must identify each file as private personal audio, an approved fixture, or disposable local material and choose keep, relocate outside the repository, approve for a private benchmark, or delete. No default cleanup action is safe.

## 8. Proposed future mechanical objectives

These are proposals, not activated roadmap changes or removal permission.

### VX-02R-A — Establish durable iOS ownership

- Put the sibling under a Human-approved backup/version-control boundary.
- Capture its current 71-file native-tree equality and run the iOS Simulator build.
- No Mac deletion.

### VX-02R-B — Remove the iOS share-extension target from the Mac workspace

- High risk because it edits `project.pbxproj`, target dependencies, entitlements/plist references, and app-extension files.
- Preserve `Transcriber.entitlements`, `SharedAudioInbox`, and shared-inbox UI unless separately proven and approved.

### VX-02R-C — Narrow the Mac project and remove iOS-only branches

- High risk because it touches audio, microphone, transcription orchestration, model lifecycle, playback, UI, and project settings.
- Split into smaller characterized objectives if the diff cannot remain reviewable.

### VX-02R-D — Archive reference/stale trees

- Treat `src/legacy-ios/` and `XCode App Build/` as separate decisions.
- Preserve the legacy implementation and nested Git history before any working-tree removal.

### VX-02R-E — Local artifact and root-audio disposition

- Separate generated build artifact cleanup from private-audio decisions.
- Each root audio file receives an explicit Human classification; no bulk deletion.

None of these proposals is part of Phase 1 and none is authorized by VX-02.

## 9. Gate findings

Agent-verifiable inventory: PASS.

Required Human choices:

1. Whether to establish the iOS sibling as a versioned/backup-owned workspace before Mac structural cleanup.
2. Whether the Mac should later remove the iOS share extension.
3. Whether the Mac should later narrow its Xcode project and remove iOS-only branches.
4. Whether the Mac app should retain app-group/shared-inbox compatibility.
5. The preservation/disposition of `src/legacy-ios/`.
6. The preservation/disposition of the nested-Git Xcode template.
7. The preservation/disposition of the ignored built Mac app.
8. The purpose and disposition of each root audio file.
9. Whether tracked visual-reference PNGs remain useful.

Per PLAN, the VX-02 Manager gate is `ASK USER`. No removal, move, archive, or cross-workspace modification occurred.
