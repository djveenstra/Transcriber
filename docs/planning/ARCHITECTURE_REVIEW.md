# Architecture Review — Transcriber 2.0 Beta (current state)

_Companion to [EXECUTIVE_REVIEW.md](EXECUTIVE_REVIEW.md). Describes the code as it exists today in `src/native/Transcriber2/`, not the intended product._

---

## 1. Project structure

```
Transcription app/
├── PRD.md                      # Product requirements (intended product)
├── AGENTS.md                   # Agent governance (this planning pass)
├── PLAN.md / OBJECTIVE.md / QA.md / DECISIONS.md
├── docs/                       # READMEs + docs/planning/ (this system)
├── assets/                     # Icons, UI preview PNGs
├── src/
│   ├── native/Transcriber2/    # ★ THE 2.0 BETA APP (active work)
│   │   ├── Transcriber/        # App sources (Swift, ~3,660 LOC)
│   │   ├── ShareToTranscriber/ # Share extension
│   │   ├── TranscriberTests/   # Unit tests (Swift Testing + XCTest, ~750 LOC)
│   │   ├── TranscriberUITests/
│   │   └── Transcriber2.xcodeproj
│   ├── python/                 # Independent Python Transcriber 1.x — DO NOT TOUCH
│   └── legacy-ios/             # Older iOS prototype — reference only
├── dist/                       # Python build artifact (gitignored)
└── XCode App Build/            # Stale default Xcode template (gitignored, reference)
```

**Observation:** Three "iOS-ish" trees coexist (`native/Transcriber2`, `legacy-ios`, `XCode App Build`). Only `native/Transcriber2` is live. This is a navigation hazard for agents — see [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §"Hidden work."

## 2. Frameworks & build

- **UI:** SwiftUI, single shared codebase for iOS + macOS, forced dark mode (`.preferredColorScheme(.dark)`).
- **Persistence:** SwiftData (`@Model`, `modelContainer(for: Recording.self)`).
- **Audio:** AVFoundation (`AVAudioEngine`, `AVAudioFile`, `AVAudioConverter`, `AVAudioSession` on iOS).
- **ML:** WhisperKit + FluidAudio (Parakeet ASR + Sortformer diarization) via SPM, pinned by revision.
- **Targets:** iOS 26 / macOS 26; Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY = complete`; `UIBackgroundModes = audio`.
- **Entitlements:** App Sandbox, audio-input, App Group `group.com.daniel.transcriber2.beta`, network client, user-selected read-only files.

## 3. Storage

- **Structured data:** `Recording` `@Model` in SwiftData. Transcript segments, raw (word-timed) transcription, and speaker-name maps are each **JSON-encoded into `Data` properties** with computed accessors (`segments`, `rawTranscription`, `speakerNames`). Encoding/decoding failures are logged and degrade to empty rather than crashing.
- **Audio files:** `.caf` in `Application Support/Transcriber2Beta/Recordings/`, referenced by filename; `Recording.audioURL` rebuilds the path. Imports are copied in with UUID-prefixed names.
- **Shared inbox:** Share extension writes `<uuid>__<title>.<ext>` into the App Group container's `SharedAudio/`; `SharedAudioInbox` enumerates and filters by audio extension.

**Strength:** Audio is the source of truth and is decoupled from the DB row. **Weakness:** transcript blobs are opaque to SwiftData queries; no schema/migration strategy is documented; orphaned-file cleanup is best-effort.

## 4. State management

- **`TranscriptionSession`** (`@MainActor ObservableObject`) is the central state machine and orchestrator. It owns `state` (`idle/preparing/recording/processing/completed/failed`), live preview state, model state, progress, the recorder, the engines, diarization-retry flags, and all persistence calls. ~857 lines — the de-facto "god object."
- Views hold sessions via `@StateObject` (each screen its own session) and read SwiftData via `@Query`.
- Cross-cutting singletons: `WhisperModelDownloader.shared`, `FinalModelDownloader.shared`, `SharedAudioInbox.shared` (all `@MainActor`).

**Strength:** Single, observable source of UI truth; deterministic state enum. **Weakness:** size and breadth of `TranscriptionSession` make it the highest-bug-density file; multiple independent sessions per screen complicate reasoning about shared model resources.

## 5. Audio pipeline

`AudioRecorder.prepareForRecording()` configures `AVAudioSession` (iOS, `.record/.measurement/.allowBluetoothHFP`) and returns the input format. `start(at:)` installs a tap that (a) writes each buffer to an `AudioFileWriter`, (b) forwards a copied `CapturedAudioChunk` via `onBuffer`, and (c) computes an RMS level on the main actor. `stop()` returns any write error so the session can mark the recording retryable. Buffers reach the live engine through an `AsyncStream` consumer task.

**Strength:** recording is independent of model readiness (record-first); write errors surface instead of silently dropping audio; delivery order preserved. **Weakness:** always uses the default input — **no microphone selection, test, meter, or fallback notice** (PRD §8 gap).

## 6. Transcription pipeline

- **Protocol `TranscriptionEngine` (Actor):** `prepare`, live methods (`beginLive`/`prepareLive`/`append`/`finishLive`), `transcribeFile`, `currentLoadedModelID`, `unload`.
- **`WhisperKitTranscriptionEngine`:** rolling live window (retain 30s / max 45s / discard 15s) with absolute-timestamp offset math; an inference semaphore (`acquireInference`/`releaseInference`) serializes overlapping calls; `transcribeFile` uses VAD chunking and word timestamps. Used for live+final on macOS and as a Whisper option on iOS.
- **`ParakeetEOULiveEngine` (iOS live):** `StreamingEouAsrManager`, queues audio until the model is ready then drains the queue, publishes partial text with token timestamps.
- **`ParakeetFinalTranscriptionEngine` (iOS final):** downloads/loads an `AsrModels` version, transcribes with token-timing → word segmentation.
- **Model selection:** `FinalTranscriptionModelChoice` unifies Parakeet (3) + Whisper (5) on iOS; `WhisperModelChoice` on macOS. Selection persisted in UserDefaults; a migration moves users to a lightweight default.

**Strength:** clean engine abstraction; live/final separation; word-level timing feeds diarization merge. **Weakness:** language hardcoded to English in two places; live/file decoding options are byte-identical (dead abstraction).

## 7. Speaker-label (diarization) pipeline

`FluidDiarizationEngine` (Actor) streams the audio file in 16 kHz mono chunks through Sortformer (`process` per chunk, then `finalizeSession`), reporting progress and honoring `Task.isCancelled` between chunks. `TranscriptionSession.runDiarizationWithFallback` runs **Balanced V2**, and on failure/timeout retries once with **Fast V2** (marked "approximate"). `diarizeWithWatchdog` races the attempt against a `DiarizationProgressGate` actor (120s before first progress, then 30s between updates) and cancels the loser. Results merge with the transcript in `TranscriptMerger` (overlap-based speaker assignment, unknown-fill, short-flip smoothing, consecutive merge).

**Strength:** cancellable, time-bounded, degrades to approximate labels, preserves transcript on total failure (`diarizationNeedsRetry`). **Weakness:** merge is purely temporal (no embeddings); fixed `maximumFlipMs`; no confidence surfaced; no segment-level reassignment UI.

## 8. Model management & persistence

- **Whisper:** `WhisperModelDownloader` downloads via `WhisperKit.download`, records confirmed IDs in a UserDefaults `Set`. `isDownloaded` for Whisper consults that in-session set — **not the on-device files** (documented as a known limitation in code). This conflicts with PRD §12.
- **Parakeet:** readiness is **file-based** (`AsrModels.modelsExist(at:version:)`) — PRD-compliant.
- **States today:** roughly `idle / downloading / ready / failed`. PRD requires `Not downloaded / Downloading / Downloaded / Verifying / Ready / Missing-corrupt / Failed`, plus Repair/Redownload and launch/Settings refresh.

## 9. Persistence (save discipline)

`persistChanges(in:failureMessage:)` wraps `context.save()`, logs failures, and surfaces a user-facing `storageErrorMessage` (shown via `.storageErrorAlert`). The session persists at many checkpoints: `preserveRecording` (before transcription), after transcript completes, after diarization, on cancel, and in `updateSavedRecording`. Save failures no longer pass silently.

**Strength:** matches the "save partial work, explain what's safe" philosophy. **Weakness:** no migration plan; multiple sessions can each insert/update; correctness depends on careful flag bookkeeping spread across one large file.

## 10. Diagnostics

Only **Model Lab** (iOS) captures real metrics: elapsed time, audio duration, "× real time" speed, transcript, and error per model, with a shareable text report. Normal screens show only phase text + a single progress bar + the loaded/selected model name. PRD §13 wants more (load time, processing time, RTF, fallback used, speaker-label status) surfaced calmly on normal screens.

## 11. Sharing / export

`TranscriptExporter` produces TXT (`[ts] Name: text`), SRT (indexed cues), and JSON. Speaker display names resolve through `displayName` (custom name → "Speaker N"). Share uses `UIActivityViewController` (iOS) / `ShareLink` (macOS), with a documented scene-phase workaround for a stuck share sheet. **Weakness:** JSON is built with `JSONSerialization`/`[String: Any]` rather than `Codable` (type-safety smell).

## 12. Navigation & UI architecture

- **Tabs today:** `Record` (RecordingView), `Library`, `Settings`. **PRD requires four tabs: Dashboard, Library, Model Lab, Settings.** There is **no Dashboard**, and **Model Lab is nested inside Settings (iOS-only)**.
- `RecordingView` drives record/import/processing/completion and hosts share + transcript list. `LibraryView` lists recordings + shared-inbox items, with detail views for playback, rename, retry, and share. `SettingsView` covers model selection/download, storage toggle, privacy, about, and the Model Lab link.
- **Theme:** centralized `Theme` enum (midnight-blue palette, speaker colors). Buttons use custom `PrimaryButtonStyle`/`SecondaryButtonStyle`.

**Strength:** consistent theming, clear per-screen responsibilities, graceful empty/failure states (`ContentUnavailableView`). **Weakness:** information architecture diverges from PRD; speaker identity relies partly on color (accessibility concern); no Dynamic Type / VoiceOver work evidenced.

## 13. Testing & verification

- Unit tests (`TranscriberTests`) cover `TranscriptMerger`, transcription-session diarization fallback/watchdog (with fakes), audio file writer, recording persistence, transcript export, model choice, shared inbox, and a WhisperKit engine smoke test. Mix of **Swift Testing** (`import Testing`) and XCTest. ~750 LOC.
- Verification commands (from `docs/README-native.md`): `xcodebuild ... -destination 'platform=macOS'` and `'generic/platform=iOS Simulator'` with `CODE_SIGNING_ALLOWED=NO`.
- **Real-device validation** (iPhone 17 Pro) is required for mic capture, model installs, FluidAudio downloads, and realtime performance, and cannot be automated here.

## 14. Overall strengths

1. Clean actor-based engine abstractions with protocol seams that tests already exploit (fakes injected).
2. Strong data-safety posture: record-first, persist-early, transcript-first, degrade-gracefully, surface-save-errors.
3. Correct, deliberate handling of model-resource contention (semaphore + sequenced loads + documented pauses).
4. Thoughtful diarization robustness (fallback config + watchdog + cancellation).
5. Centralized theme and consistent, calm failure/empty states.

## 15. Overall weaknesses (feed [GAP_ANALYSIS.md](GAP_ANALYSIS.md))

1. Information architecture diverges from PRD (no Dashboard; Model Lab not a tab).
2. Microphone selection/test/meter/fallback entirely absent.
3. Whisper model readiness is in-memory, not file-based; model state set incomplete; no Repair/Redownload.
4. Segment-level speaker reassignment missing (a beta requirement).
5. Diagnostics under-surfaced on normal screens; progress is a single bar, not a phase timeline.
6. Accessibility (Dynamic Type, VoiceOver, contrast, non-color status) not yet addressed.
7. `TranscriptionSession` is oversized; minor tech debt (hardcoded language, JSON via `JSONSerialization`, fragile speaker-color parsing).
8. Mac is behind iOS on Model Lab and some flows.
