# PRD Gap Analysis — Transcriber 2.0 Beta

_Each PRD feature is rated **Complete**, **Partial**, **Missing**, or **Unknown** (cannot be confirmed without on-device validation). Complexity is **S / M / L**. "Verified by" notes the code evidence. The 20-objective roadmap closes every Partial/Missing item._

Legend — Status: ✅ Complete · 🟡 Partial · ❌ Missing · ❓ Unknown.

---

## A. App structure & navigation (PRD §6)

| # | Feature | Status | Cx | Evidence / Notes |
|---|---|---|---|---|
| A1 | Four tabs: Dashboard, Library, Model Lab, Settings | 🟡 | M | `RootView.swift` has 3 tabs (Record, Library, Settings). No Dashboard; Model Lab nested in Settings. |
| A2 | **Dashboard** home (mic status, model readiness, diarization status, recent attention, Record/Import/Model Lab actions, missing-model warnings) | ❌ | L | No Dashboard exists. App opens to RecordingView. |
| A3 | **Library** chronological list | ✅ | – | `LibraryView.swift`, `@Query` reverse by `createdAt`. |
| A4 | Library per-item: date title, duration, **status badge**, final model used, speaker-label status | 🟡 | M | Only "Needs transcription" + date shown. No duration, full status badge, model used, or speaker status. |
| A5 | Library detail: playback, transcript, rename, **segment reassignment**, share, retry transcription, retry labels, delete | 🟡 | L | All present except **segment-level speaker reassignment** (only rename). |
| A6 | **Model Lab** top-level tab | 🟡 | M | Exists but iOS-only and nested under Settings. |
| A7 | Model Lab: pick recording/import, run models one-at-a-time, compare, capture load/transcribe time + failure + size/status + speed, export report | 🟡 | M | Runs one-at-a-time, captures elapsed/speed/transcript/error + report export. Missing: explicit **model load time**, **model size/status** columns. |
| A8 | Settings: mic selection+test, model selection+downloads, storage status + repair/redownload, storage policy, privacy, diagnostics, about | 🟡 | L | Has model selection/download, storage toggle, privacy, about. Missing mic section, repair/redownload, model storage status, diagnostics section. |

## B. Recording & microphone (PRD §7 Record flow, §8)

| # | Feature | Status | Cx | Evidence / Notes |
|---|---|---|---|---|
| B1 | Record starts immediately, independent of model readiness | ✅ | – | `startRecording()` starts recorder before/independent of live model prep. |
| B2 | Live preview starts when model ready, never blocks recording | ✅ | – | Live prep is a separate task; recording proceeds regardless. |
| B3 | Stop → save immediately → final transcription → transcript appears → diarization → labels replace | ✅ | – | `stopRecording` → `processFile`; transcript shown before diarization. |
| B4 | Recording continues in background/lock | ❓ | M | `UIBackgroundModes=audio` set; **must be validated on device**. |
| B5 | Reliable up to 30 minutes | ❓ | M | Sliding live window bounds memory; **30-min E2E must be validated on device**. |
| B6 | Original audio kept by default | ✅ | – | Audio written to Recordings dir; `keepAudioFiles` defaults true. |
| B7 | **Microphone selection** (auto, built-in, Bluetooth/headset, named inputs) | ❌ | L | No selection UI or backend; always default input. |
| B8 | **Test Mic** + live input meter | ❌ | M | Not present. (RMS `level` exists during recording but no test screen.) |
| B9 | Clear active-mic display during recording | ❌ | S | Status header shows model, not active microphone. |
| B10 | Mic fallback when selected unavailable + user notice | ❌ | M | No selection ⇒ no fallback/notice logic. |

## C. Transcription (PRD §9)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| C1 | Fast, reliable default model | ✅ | – | Default `openai_whisper-base.en`; lightweight migration. |
| C2 | Final quality prioritized over live | ✅ | – | Separate final pass; UI says so. |
| C3 | Curated model picker w/ plain-language descriptions | 🟡 | S | Picker + detail text present. Missing explicit **speed/accuracy/size/readiness** per row. |
| C4 | Model failure → save audio+partial, safer fallback, notify, offer retry/repair/redownload | 🟡 | M | Audio/partial saved; transcript-fail marks retry. No automatic safer-model fallback or repair/redownload. |

## D. Diarization / speaker labels (PRD §10, §11 editing)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| D1 | Apply labels after transcription | ✅ | – | `runDiarizationWithFallback` post-transcript. |
| D2 | Optimize 2–4 speakers | ✅ | – | Sortformer; merge smoothing. |
| D3 | Preserve transcript if labeling fails | ✅ | – | `diarizationNeedsRetry`; transcript kept. |
| D4 | Retry labels without re-transcribing | ✅ | – | `retrySpeakerLabels` / `retryCurrentSpeakerLabels` reuse `rawTranscription`. |
| D5 | Rename speakers | ✅ | – | `SpeakerRenameView`. |
| D6 | **Reassign a transcript segment to a different speaker** | ❌ | M | Not implemented (beta-required). |
| D7 | Show approximate/failed/canceled/retryable states | 🟡 | S | Approximate + failed + retry notes exist; surface consistently across all screens. |
| D8 | Single-speaker recording doesn't fail workflow | ✅ | – | Merge handles single speaker / empty diarization. |

## E. Transcript display, playback, sharing (PRD §11)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| E1 | Speaker cards: name, color, timestamp, text, grouping | ✅ | – | `TranscriptCard`. |
| E2 | Basic play/pause of original audio | ✅ | – | `AudioPlaybackController`, detail playback. |
| E3 | Export TXT / SRT / JSON | ✅ | – | `TranscriptExporter`. |
| E4 | Exports include speaker names when available | ✅ | – | `displayName` used in all formats. Add explicit test coverage. |
| E5 | System share sheet | ✅ | – | `UIActivityViewController` / `ShareLink`. |

## F. Model downloads & persistence (PRD §12)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| F1 | Models survive force-quit / relaunch / reboot | 🟡 | M | Files persist on disk; **Whisper readiness flag is in-memory/UserDefaults, not file-based** — readiness can be wrong after relaunch. |
| F2 | Readiness from actual files (+ loadability where practical) | 🟡 | M | Parakeet file-based ✅; Whisper not ❌. |
| F3 | Full state set: Not downloaded/Downloading/Downloaded/Verifying/Ready/Missing-corrupt/Failed | 🟡 | M | ~idle/downloading/ready/failed only. |
| F4 | Preload default model w/o heavy onboarding | 🟡 | S | macOS prepares on appear; iOS relies on first use. No explicit lightweight preload. |
| F5 | Show download size/progress when known | 🟡 | S | Progress shown; size only for Parakeet v3 (hardcoded 461 MB). |
| F6 | Refresh status on launch and when Settings opens | 🟡 | S | Some `onAppear` refresh; not a full file-based re-check. |
| F7 | Verify selected model before processing | 🟡 | M | Loads on demand; no explicit pre-flight verify/repair. |
| F8 | Missing/corrupt → Repair/Redownload | ❌ | M | No repair/redownload affordance. |
| F9 | Fully offline after download | ✅ | – | On-device inference; network only for downloads/share. |

## G. Progress, diagnostics, failure (PRD §13)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| G1 | Detailed **phase timeline** (not a spinner): phase, %/activity, elapsed, cancel, retry, details | 🟡 | M | Single progress bar + phase string + cancel. No timeline, elapsed, or details drill-down. |
| G2 | Core phases named | 🟡 | S | Phase strings exist ("Transcribing", "Identifying speakers", etc.); not a structured phase model. |
| G3 | Diagnostics on normal screens (model, readiness, load time, processing time, RTF, failure, fallback, speaker status), calm | 🟡 | M | Only Model Lab has metrics; normal screens minimal. |
| G4 | Failure states explain safe/failed/retryable/fallback | ✅ | – | Completion notes + storage alerts do this well. |
| G5 | Save partial work whenever possible | ✅ | – | Core invariant honored. |

## H. Import / share-to-app (PRD §7)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| H1 | Share audio from Voice Memos/other apps | ✅ | – | Share extension → App Group inbox. |
| H2 | Import from Files | ✅ | – | `fileImporter` in RecordingView/Model Lab. |
| H3 | Imported item appears in Library/recent | ✅ | – | `SharedAudioInbox` section in Library. |
| H4 | Imported audio transcribes via same pipeline | ✅ | – | `importAudio` → `processFile`. |

## I. Storage & privacy (PRD §14)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| I1 | Audio kept by default | ✅ | – | Toggle defaults on. |
| I2 | Separate storage from Python app | ✅ | – | `Transcriber2Beta` dir + distinct bundle/App Group. |
| I3 | Delete recordings | ✅ | – | `LibraryView.delete`; keeps row if file delete fails. |
| I4 | Storage management: model sizes + cache cleanup | ❌ | M | Not implemented (PRD marks "future" but model storage status is in §6 Settings). |
| I5 | On-device processing; downloads need network; share user-initiated; no cloud sync | ✅ | – | Matches design. |

## J. Accessibility (PRD §15)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| J1 | Dynamic Type | ❓ | M | Uses semantic fonts (good sign) but unverified end-to-end. |
| J2 | VoiceOver labels for controls + transcript cards | 🟡 | M | Many `Label`s help; no explicit accessibility labels/traits on cards/status dots. |
| J3 | Sufficient contrast in midnight-blue theme | ❓ | S | Needs audit; `.foregroundStyle(.black)` on buttons is a flagged risk. |
| J4 | Reachable controls | ❓ | S | Needs device check. |
| J5 | Clear text status for progress/failure | ✅ | – | Status text throughout. |
| J6 | Don't rely on color alone for speaker/status | ❌ | M | Speaker identity and recording dot are color-coded without text/shape alternatives. |

## K. Mac companion (PRD §4, §17)

| # | Feature | Status | Cx | Notes |
|---|---|---|---|---|
| K1 | Open/import recording | ✅ | – | `fileImporter`; macOS uses WhisperKit live+final. |
| K2 | Playback | ✅ | – | Shared playback controllers. |
| K3 | Share/export transcript | ✅ | – | `ShareLink`. |
| K4 | Basic model workflows | 🟡 | M | Whisper download/select on Mac; no Model Lab on Mac. |

---

## Hidden / unstated work (not explicit in PRD but required to ship safely)

1. **Repo hygiene for agents.** Three iOS-ish trees (`native/Transcriber2`, `legacy-ios`, stale `XCode App Build/`) invite edits to the wrong target. Needs a clear "active path" convention and possibly archiving the stale template (with confirmation — never delete unasked).
2. **SwiftData schema/migration plan.** Transcript blobs and `Recording` fields will evolve (status enum, model metadata, reassignment). A migration story is needed before changing the model, or beta data is at risk.
3. **A structured status model.** Many features (Library badges, Dashboard, progress timeline) need a single canonical `RecordingStatus` / phase enum rather than the current scattered booleans (`transcriptionNeedsRetry`, `diarizationNeedsRetry`).
4. **Model registry/metadata** (size, provider, expected speed/accuracy, on-disk path) to power the picker, Settings storage status, repair/redownload, and Model Lab columns.
5. **Diagnostics data model.** Capturing load time / processing time / RTF / fallback during the real pipeline (not just Model Lab) requires threading metrics through `TranscriptionSession`.
6. **Microphone abstraction.** An input-discovery/selection/fallback service the recorder consumes.
7. **Test seams for UI flows.** UI tests are skeletal; acceptance criteria need either UI tests or documented manual scripts (see [QA_STRATEGY.md](QA_STRATEGY.md)).
8. **On-device validation ownership.** Background recording, model persistence across reboot, and performance are Human-Reviewer-owned gates; the plan must not let agents "claim done" on these.

## Dependencies between gaps (sequencing implications)

- A canonical **status/phase model** (hidden #3) underpins **A4 Library badges**, **A2 Dashboard**, and **G1 progress timeline** → build it before those UIs.
- A **model registry** (hidden #4) underpins **F1–F8**, **C3 picker detail**, **A7/A8 Model Lab & Settings storage**.
- **Microphone abstraction** (hidden #6) underpins **B7–B10**.
- **Diagnostics data model** (hidden #5) underpins **G3** and richer **A7**.
- **SwiftData migration plan** (hidden #2) must precede any change to `Recording` (status enum, reassignment storage).

These dependencies are encoded in [PLAN.md](../../PLAN.md) phase ordering and the [OBJECTIVE roadmap](objectives/).
