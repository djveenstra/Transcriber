# Executive Review — Transcriber 2.0 Beta

_Author: Staff Software Architect (planning pass). Date: 2026-06-18._
_Source of truth for the product: [PRD.md](../../PRD.md). Source of truth for current code: `src/native/Transcriber2/`._

This document is the top-level orientation for everyone working on Transcriber 2.0 Beta — human and agent. Read it first, then [ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md), [GAP_ANALYSIS.md](GAP_ANALYSIS.md), and [RISK_REGISTER.md](RISK_REGISTER.md).

---

## 1. What this application is

Transcriber 2.0 Beta is a **native, on-device audio transcription app** for iPhone (primary) and Mac (secondary companion). It:

1. Records audio immediately and reliably, or imports audio shared from other apps (e.g. Voice Memos).
2. Produces a usable text transcript as fast as possible using an on-device speech model.
3. Applies **speaker labels** (diarization) for 2–4 speakers _after_ the transcript exists.
4. Preserves the original audio by default for playback, retry, and speaker-label repair.
5. Keeps all processing local; the only network use is model downloads and user-initiated sharing.

The app is explicitly a **beta with instrumentation**: it must expose enough diagnostics (model load time, processing speed, failure reasons, fallbacks) to measure and improve model quality, via a dedicated **Model Lab**.

There is also an independent, unchanged **Python Transcriber 1.x** (`src/python/`) and an older iOS prototype (`src/legacy-ios/`). Neither is the subject of this work. The native 2.0 app must never require modifying the Python app.

## 2. Intended users

- **Primary:** Daniel, using the app on his own iPhone (target validation hardware: iPhone 17 Pro). Optimized for real testing in practical situations — meetings (2–4 speakers), interviews, building walkthroughs/site visits, and imported recordings — rather than broad public-release polish.
- **Secondary:** Mac usage for review, playback, import, and sharing; and model benchmarking/diagnostics during beta.

The human in the multi-agent workflow ("Human Reviewer") is also Daniel. He is newer to coding and backends but is learning; planning artifacts and agent reports should be clear and explain _why_, not just _what_.

## 3. Major technical systems

| System | Current implementation | File(s) |
|---|---|---|
| App shell / navigation | SwiftUI `TabView`, dark "midnight-blue" theme | `RootView.swift`, `Transcriber2App.swift` |
| Recording / audio capture | `AVAudioEngine` tap → `.caf` file + live `AsyncStream` | `AudioRecorder.swift`, `CapturedAudioChunk.swift` |
| Live transcription | iOS: Parakeet EOU streaming; macOS: WhisperKit rolling window | `ParakeetTranscriptionEngines.swift`, `TranscriptionEngine.swift` |
| Final transcription | iOS: Parakeet (3 variants) or Whisper; macOS: WhisperKit | `FinalTranscriptionModels.swift`, `TranscriptionEngine.swift` |
| Speaker labeling (diarization) | FluidAudio Sortformer (Balanced V2 → Fast V2 fallback, watchdog timeout) | `DiarizationEngine.swift` |
| Transcript/diarization merge | Overlap-based assignment + smoothing | `TranscriptMerger.swift` |
| Orchestration / state | `TranscriptionSession` (`@MainActor ObservableObject`, ~857 lines) | `TranscriptionSession.swift` |
| Persistence | SwiftData `@Model Recording` (transcript stored as JSON `Data`); audio files in Application Support | `Models.swift` |
| Model management/downloads | WhisperKit + FluidAudio downloaders, per-provider readiness | `WhisperModels.swift`, `FinalTranscriptionModels.swift` |
| Import / share-to-app | Share extension → App Group inbox → `SharedAudioInbox` | `ShareToTranscriber/ShareViewController.swift`, `SharedAudioInbox.swift` |
| Export / sharing | TXT / SRT / JSON + system share sheet | `TranscriptExporter.swift` |
| Model Lab (diagnostics) | iOS-only, nested under Settings | `ModelLabView.swift` |

Dependencies (Swift Package Manager, pinned by revision): **WhisperKit** (argmaxinc) and **FluidAudio** (FluidInference). Targets iOS 26 / macOS 26, Swift strict concurrency = `complete`.

## 4. Primary architectural challenges

1. **Multi-stage, resource-contended ML pipeline on a phone.** Live model → final transcription model → diarization model all compete for ANE/GPU/memory. The code already serializes loads with deliberate pauses and an inference semaphore. Any change here risks memory pressure, contention, or regressions.
2. **"Never lose audio / transcript-first" data-safety guarantees.** The session persists at multiple checkpoints and degrades gracefully (transcript preserved if diarization fails/cancels). This invariant is fragile and central to the product; it must be protected by every change.
3. **Model persistence and honest readiness.** PRD §12 demands readiness be based on actual on-device files, not just a remembered flag. Whisper readiness is currently tracked via an in-session/UserDefaults set — a known gap.
4. **iPhone-first / Mac-second divergence.** Heavy `#if os(iOS)` / `#if os(macOS)` branching across engines and views. Changes must hold for both platforms or be explicitly scoped.
5. **Beta instrumentation without a "lab bench" feel.** Diagnostics must be present but calm; Model Lab carries the heavy detail.
6. **Real-hardware-only validation.** Microphone capture, model installs, FluidAudio downloads, and realtime performance can only be truly validated on an iPhone 17 Pro — outside CI and outside any agent's reach.

## 5. Highest-risk areas (see [RISK_REGISTER.md](RISK_REGISTER.md) for the full register)

- **Data loss** of recordings/transcripts during save, cancel, or crash (Critical).
- **Model persistence** across force-quit/relaunch/reboot, especially the in-memory Whisper readiness flag (Critical).
- **Recording reliability** in background/lock and at the 30-minute target (Critical).
- **Race conditions** in the concurrent live/final/diarization pipeline under strict concurrency (High).
- **Memory pressure** from large recordings and back-to-back model loads (High).
- **Diarization failures** and the transcript-preservation/retry guarantees (High).

## 6. Recommended development strategy

1. **Govern first.** This codebase is mature and mostly sound; the biggest risk is uncontrolled change. Stand up the planning/governance system (PLAN, OBJECTIVE, AGENTS, QA) and a repeatable verification harness before feature work.
2. **Stabilize the invariants before adding surface area.** Sequence data-safety and model-persistence work (the Critical risks) ahead of new UI like the Dashboard.
3. **Many small, reversible milestones.** Favor one-session objectives that each leave the app building, green, and shippable. No rewrites where a refactor will do.
4. **Treat real-device validation as a first-class, human-owned gate.** Agents validate via build + unit tests + simulator; the Human Reviewer owns on-device acceptance (recording, background, model persistence, performance).
5. **Protect the Python app and the user's data absolutely.** Out of bounds for every objective.

The implementation is carried out by a Manager → Worker → Auditor → QA → Human Reviewer loop defined in [MULTI_AGENT_WORKFLOW.md](MULTI_AGENT_WORKFLOW.md) and governed by [AGENTS.md](../../AGENTS.md).
