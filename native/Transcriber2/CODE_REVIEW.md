# Code Review: Transcriber 2.0

Reviewed by Claude (Sonnet 4.6) on 2026-06-14. This document is structured for Codex to read, evaluate, and act on. Each finding includes the file, line numbers, the problem, and a suggested fix. At the end are architecture-level suggestions for faster transcription and better diarization.

The codebase is well-structured overall. Actor isolation is correct, the inference semaphore pattern is clean, TranscriptMerger handles real-world noise gracefully, and preserving recordings before transcription completes is excellent UX. These findings are improvements on a solid foundation.

---

## Critical

### 1. Silent data loss from swallowed errors

**Files:** `Transcriber/Models.swift:64-65`, `Transcriber/TranscriptionSession.swift:355`

**Problem:** `try?` silently discards JSON encoding/decoding failures and `ModelContext.save()` errors. If `transcriptData` becomes corrupted, the `segments` getter returns `[]` with no indication — the user's transcript vanishes silently. The `save()` calls after transcription completes also fail silently.

**Suggested fix:** At minimum, log encoding/decoding failures so they're visible in Console.app during development. For `ModelContext.save()`, propagate the error or surface it in the UI after the critical transcription-complete save paths (e.g., `updateSavedRecording`, `preserveRecording`). The getters on `Recording` could use `do/catch` with `os.Logger` instead of `try?`.

### 2. Data race in AudioRecorder tap closure

**File:** `Transcriber/AudioRecorder.swift:47-53`

**Problem:** `AudioRecorder` is `@MainActor`, but `installTap` fires on a real-time audio thread. Inside the tap closure, `self?.file?.write(from: buffer)` and `self?.onBuffer?(copied)` access `@MainActor`-isolated properties from a non-main-actor context. This is a data race under Swift 6 strict concurrency.

**Suggested fix:** Move `file` to a non-isolated property protected by a lock or `os.OSAllocatedUnfairLock`, or move the write into a dedicated serial `DispatchQueue`. The `onBuffer` callback is already `@Sendable` so it's safe, but `file` needs explicit synchronization. The `level` update is already dispatched to MainActor correctly.

---

## High

### 3. Unbounded live sample accumulation

**File:** `Transcriber/TranscriptionEngine.swift:53`

**Problem:** `liveSamples` grows for the entire recording duration. At 16kHz mono float32, a 1-hour recording accumulates ~230 MB in this array. Each `publishLiveSnapshot` re-transcribes the entire array from the beginning, making each successive live update slower.

**Suggested fix:** Use a sliding window. Keep only the last N seconds of audio (e.g., 30s) and track a cumulative offset for timestamps. Alternatively, keep finalized segments and only re-transcribe recent unfinalized audio. This will cap memory usage and keep live inference time constant.

### 4. @MainActor singletons initialized via static let

**Files:** `Transcriber/WhisperModels.swift:82`, `Transcriber/SharedAudioInbox.swift:18`, `Transcriber/FinalTranscriptionModels.swift:103`

**Problem:** `static let shared` on `@MainActor` classes means lazy initialization must happen on the main actor. If any code path touches `.shared` from a background context, it will trap or deadlock under strict concurrency.

**Suggested fix:** Either initialize eagerly at app launch (store on the `App` struct and inject via environment), or use `nonisolated` access with internal `@MainActor` dispatch. Another option is making these actors instead of `@MainActor` classes.

### 5. TOCTOU race in uniqueDestination (share extension)

**File:** `ShareToTranscriber/ShareViewController.swift:138-149`

**Problem:** `fileExists` followed by create is a time-of-check-time-of-use race. Two concurrent share extension invocations with the same base name could both see the file as absent, then one overwrites the other.

**Suggested fix:** Append a UUID suffix to every file (like you already do elsewhere in the codebase — e.g., `recording-\(UUID().uuidString).caf`). This eliminates the race entirely and the `while` loop can be removed.

### 6. Hardcoded .black foreground on primary buttons

**File:** `Transcriber/RecordingView.swift:386`

**Problem:** `.foregroundStyle(.black)` doesn't adapt to dark mode. The app forces dark mode via `.preferredColorScheme(.dark)` so it works today, but if that ever changes (or for accessibility high-contrast modes), text becomes invisible on dark accent colors.

**Suggested fix:** Use `.foregroundStyle(.white)` since all accent colors in `Theme` are bright/saturated, or compute contrast dynamically.

---

## Medium

### 7. TranscriptionSession is too large (~560 lines)

**File:** `Transcriber/TranscriptionSession.swift`

**Problem:** This single class manages recording state, persistence, transcription orchestration, diarization retry, model selection, and progress tracking. It's the hardest file to reason about and the most likely place for bugs to hide.

**Suggested fix:** Extract persistence logic (`preserveRecording`, `updateSavedRecording`, `saveCompletedRecording`) into a `RecordingPersistence` helper. The model-selection logic (`selectedFinalModelID`, `prepareSelectedFinalModel`, `transcribeSelectedFinalModel`, `unloadSelectedFinalModel`) could also be a separate coordinator.

### 8. Hardcoded English language

**Files:** `Transcriber/TranscriptionEngine.swift:145`, `Transcriber/ParakeetTranscriptionEngines.swift:151`

**Problem:** `language: "en"` is hardcoded in decoding options and Parakeet's `.english`. Users selecting multilingual Whisper models (like distil-large-v3) get forced into English mode anyway.

**Suggested fix:** Add a language setting in `SettingsView` that defaults to English. Pass it through to the engines. This also future-proofs the app for non-English users.

### 9. Identical live and file decoding options

**File:** `Transcriber/TranscriptionEngine.swift:144-156`

**Problem:** `decodingOptions` and `liveDecodingOptions` are byte-for-byte identical. This is either a copy-paste oversight or a premature abstraction.

**Suggested fix:** Either share a single constant, or differentiate them. Live could benefit from `chunkingStrategy: .none` for lower latency, or different `concurrentWorkerCount` settings.

### 10. Polling-based diarization timeout

**File:** `Transcriber/TranscriptionSession.swift:496-501`

**Problem:** The timeout mechanism uses a `while true` loop with `Task.sleep(for: .seconds(5))`. This wakes every 5 seconds to check if work is done.

**Suggested fix:** Replace with a single `Task.sleep(for: .seconds(120))` as a deadline, then cancel the diarization task if it hasn't finished. Or use `Task` with a timeout wrapper via `withThrowingTaskGroup` and a deadline task.

### 11. Fragile speaker color extraction

**File:** `Transcriber/RecordingView.swift:373-375`

**Problem:** `segment.speaker.filter(\.isNumber)` extracts all digits from the speaker string. `"SPEAKER_10"` would parse as `10`, `"SPEAKER_01"` as `01` → `1`. This could cause unexpected color collisions or shifts.

**Suggested fix:** Parse the speaker index explicitly: split on `_`, take the last component, and convert to `Int`. Handle the `"S1"` format from diarization tests separately.

### 12. JSON export uses JSONSerialization instead of Codable

**File:** `Transcriber/TranscriptExporter.swift:45-50`

**Problem:** The JSON export builds `[String: Any]` dictionaries and uses `JSONSerialization`, while the rest of the codebase uses `Codable`. This loses type safety and the `as [String: Any]` cast is a code smell.

**Suggested fix:** Define a small `Codable` struct (e.g., `ExportedSegment`) with `start`, `end`, `speaker`, `text` fields. Use `JSONEncoder` with `.prettyPrinted`.

---

## Low

### 13. Unused protocol parameter

**File:** `Transcriber/TranscriptionEngine.swift:41`

`_ = audioFormat` in `prepareLive` — if the parameter is unused, remove it from the protocol or use `_` in the signature.

### 14. Artificial 1-second delays after model unload

**Files:** `Transcriber/TranscriptionSession.swift:189`, `Transcriber/TranscriptionSession.swift:366`

`try? await Task.sleep(for: .seconds(1))` after unloading models. If this is for memory pressure, use `autoreleasepool` or measure actual need. If it's a workaround, add a comment explaining why.

### 15. No cancellation support in processFile

**File:** `Transcriber/TranscriptionSession.swift:336`

`processFile` doesn't check `Task.isCancelled`. If the user navigates away during transcription, work continues in the background consuming resources.

### 16. Share sheet scenePhase workaround

**File:** `Transcriber/RecordingView.swift:279-285`

The `onChange(of: scenePhase)` handler that dismisses the share sheet after 300ms appears to be a SwiftUI bug workaround. If so, add a comment explaining what bug it works around, so future readers don't remove it.

### 17. Orphaned audio files on failed deletion

**File:** `Transcriber/LibraryView.swift:74`

`try? FileManager.default.removeItem` — if deletion fails, the audio file is orphaned but the SwiftData record is still deleted. Consider reversing the order (delete file first, then remove the record) or adding periodic cleanup.

### 18. Test coverage is limited to TranscriptMerger

**File:** `TranscriberTests/TranscriptMergerTests.swift`

The existing tests are good, but there is no coverage for: `TranscriptExporter` SRT/JSON output formatting, `ParakeetFinalTranscriptionEngine.convert` token timing logic, `WhisperModelChoice.migrateToLightweightDefaultIfNeeded`, or `SharedAudioInbox` file filtering. These are all pure functions that are straightforward to unit test.

---

## Performance: Speeding Up the Pipeline

### Current bottleneck analysis

The transcription pipeline is sequential: record → unload live model → wait 1s → load final model → transcribe file → unload final model → wait 1s → load diarization model → diarize → merge. Each model load/unload adds 2-10 seconds of dead time, and the 1-second artificial sleeps add more.

### Recommendations

**A. Eliminate the artificial sleeps.** The two `Task.sleep(for: .seconds(1))` calls at lines 189 and 366 of `TranscriptionSession.swift` add 2 seconds of pure waste. If they exist for memory pressure reasons, wrap the unload in `autoreleasepool` instead and verify memory is actually reclaimed. If they exist because WhisperKit needs time to release GPU resources, file a bug or measure the actual required delay.

**B. Pipeline the model loads.** On devices with enough memory (most modern iPhones/Macs), begin loading the diarization model while transcription is still running. Currently `diarizeFile` in `FluidDiarizationEngine` downloads and initializes the Sortformer model on first call. Instead, start `SortformerModels.loadFromHuggingFace` as soon as recording stops, in parallel with the final transcription. The models use different hardware resources (Whisper uses the ANE/GPU, Sortformer uses CPU/GPU differently).

**C. Use a sliding window for live transcription (macOS).** As noted in finding #3, `publishLiveSnapshot` re-transcribes all accumulated audio from the start. This means the 10th live update processes 10x more audio than the 1st. Use a sliding window of ~30 seconds and carry forward finalized segments. This keeps live update latency constant regardless of recording length.

**D. Skip re-transcription when live quality is sufficient.** On iOS, Parakeet EOU provides word-level timestamps during live recording. If the live transcript quality is acceptable (e.g., measured by a confidence threshold), you could skip the full final transcription pass entirely and go straight to diarization. This would cut total processing time roughly in half for clear, single-speaker recordings.

**E. Warm the final model during recording.** On macOS, `prepareSelectedModel` runs on view appear, but the model is unloaded and reloaded after recording stops (`stopRecording` calls `transcriber.unload()` then `processFile` calls `model()` again). If the same model is used for both live and final, skip the unload/reload cycle entirely.

**F. Parallelize the final transcription progress callback.** In `transcribeFile` (TranscriptionEngine.swift:68-88), progress is reported via a closure that hops to MainActor. Each hop is a context switch. Batch progress updates (e.g., only report when progress changes by >2%) to reduce main thread contention during heavy inference.

---

## Diarization: Improving Speaker Identification

### Current approach

The app uses Sortformer (via FluidAudio) with two configurations:
- **Live (iOS only):** `SortformerConfig.fastV2` — lightweight, runs during recording
- **Final:** `SortformerConfig.balancedV2` — stronger, runs on the complete audio file after recording

Speaker labels are then merged with word-level transcription timestamps in `TranscriptMerger`.

### What's working well

- `TranscriptMerger.smoothShortFlips` correctly handles the most common diarization error (brief false speaker changes)
- `fillUnknownSpeakers` uses nearest-neighbor interpolation, which is the right default
- `splitLongSegment` breaks Whisper's long segments at sentence boundaries for better speaker assignment — this is a clever solution to Whisper's tendency to produce paragraph-length segments
- The 200ms minimum diarization segment filter eliminates noise

### Recommendations for improvement

**G. Use speaker embedding similarity for merge decisions.** Currently `TranscriptMerger` assigns speakers based purely on temporal overlap (`overlap` function). When a word falls on a speaker boundary, it gets assigned to whichever speaker segment has more overlap in milliseconds. This is fragile for fast turn-taking. If FluidAudio exposes speaker embeddings, use cosine similarity between the word's audio segment and each speaker's centroid to break ties when temporal overlap is ambiguous (within ~200ms of each other).

**H. Tune `maximumFlipMs` dynamically.** The current 400ms threshold for `smoothShortFlips` is static. In fast-paced conversations (debates, interviews), legitimate speaker turns can be under 400ms ("Yes." "No." "Why?"). In slow monologue-heavy recordings, the threshold could be higher. Consider computing the median turn duration and setting `maximumFlipMs` to something like `min(400, median / 3)`.

**I. Post-merge speaker count validation.** Sortformer supports up to 4 speakers. If the merge produces only 1 unique speaker when the audio clearly has multiple voices, or produces 4 speakers for a single-voice recording, surface this to the user. A simple heuristic: if all diarization segments map to the same speaker but the audio is >60 seconds, suggest re-running diarization. This helps catch cases where Sortformer failed silently.

**J. Re-run diarization with different parameters on failure.** When `diarizationWithTimeout` returns nil (timeout or error), the current behavior is to show a retry button. Instead of using the exact same parameters on retry, try a different configuration — e.g., if `balancedV2` timed out, fall back to `fastV2` which will at least produce approximate labels rather than none. Partial diarization is better than no diarization.

**K. Expose diarization confidence to the user.** If Sortformer provides per-segment confidence scores, surface low-confidence speaker assignments in the UI (e.g., a subtle visual indicator on `TranscriptCard`). This helps users identify segments that may need manual correction via the speaker rename feature.

**L. Consider two-pass diarization for long recordings.** For recordings over 10 minutes, run a fast first pass to identify the number of speakers and their approximate regions, then run the balanced model only on transition regions where speakers change. This could significantly reduce diarization time for long meetings while maintaining accuracy at speaker boundaries.

---

## Summary for Codex

If you're prioritizing fixes, here's the suggested order:

1. **Fix #2** (data race in AudioRecorder) — correctness bug, will crash under strict concurrency
2. **Fix #3** (unbounded liveSamples) — memory issue that worsens with recording length
3. **Fix #1** (silent data loss) — users could lose transcripts with no error shown
4. **Implement E** (skip unnecessary model unload/reload) — easiest performance win
5. **Implement A** (remove artificial sleeps) — 2 seconds of free speedup
6. **Implement B** (pipeline model loads) — biggest performance improvement
7. **Fix #5** (TOCTOU race) — use UUID like the rest of the codebase
8. **Implement J** (fallback diarization config) — better UX for diarization failures
9. **Fix #18** (add tests) — the pure functions are easy wins for coverage
10. Everything else in severity order
