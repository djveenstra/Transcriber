# Transcriber iOS App
> **Workspace note (2026-07-28):** This checkout is now the Mac-focused Transcriber workspace. Existing Beta 2.0 and iPhone-first material below is retained as historical pre-split context; iOS follow-up belongs in the sibling `../iOS Transcriber/` workspace.

A native iOS app that records memos and produces speaker-labeled transcripts entirely on-device.
No server, no subscription, no internet required after initial model download.

## Requirements

- Xcode 15.0+
- iOS 17.0+ deployment target
- iPhone with A14 Bionic or later (iPhone 12+)
- ~350 MB free space for ML models (downloaded on first launch)

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode → File → New → Project
2. Choose: iOS → App
3. Product Name: `TranscriberApp`
4. Interface: SwiftUI
5. Storage: SwiftData
6. Language: Swift
7. Save to this directory

### 2. Add Source Files

Copy all files from `TranscriberApp/` into the Xcode project:
- Drag the folders (App, Audio, Transcription, Diarization, Processing, Storage, Views) into the project navigator
- Ensure "Copy items if needed" is checked
- Add to target: TranscriberApp

### 3. Integrate whisper.cpp

**Option A: Swift Package Manager (Recommended)**
1. In Xcode: File → Add Package Dependencies
2. URL: `https://github.com/ggerganov/whisper.cpp`
3. Branch: `master`
4. Add the `whisper` library to your target

**Option B: XCFramework**
1. Clone whisper.cpp: `git clone https://github.com/ggerganov/whisper.cpp`
2. Run: `cd whisper.cpp && examples/whisper.swiftui/build-xcframework.sh`
3. Drag the resulting `whisper.xcframework` into your project

### 4. Add ZIPFoundation

1. File → Add Package Dependencies
2. URL: `https://github.com/weichsel/ZIPFoundation.git`
3. Version: from 0.9.0
4. This is used for extracting downloaded model archives

### 5. Configure Project Settings

**Info.plist entries** (add via target → Info tab):
- `NSMicrophoneUsageDescription`: "Transcriber needs microphone access to record and transcribe your memos."
- `UIBackgroundModes` → `audio` (for keeping recording alive when screen locks)

**Build Settings:**
- Deployment Target: iOS 17.0
- `OTHER_LDFLAGS`: `-lc++` (for whisper.cpp C++ linking)
- Architectures: arm64 only

**Bridging Header:**
- Set `TranscriberApp/Transcription/WhisperBridge.h` as the Objective-C Bridging Header
- (Only needed if using whisper.cpp as source files or XCFramework, not SPM)

### 6. Build & Run

1. Select your iPhone as the build target (or Simulator for UI work)
2. Build (Cmd+B)
3. Run (Cmd+R)
4. On first launch, tap "Download Models" — requires Wi-Fi for the ~350 MB download
5. After download completes, you can record and transcribe offline forever

## Architecture

```
Record (AVAudioEngine)
    ↓ real-time audio buffers
Streaming Whisper (whisper.cpp + CoreML)
    ↓ live text segments

    [Recording stops]

Saved WAV file
    ↓
Voice Activity Detection (Silero VAD CoreML)
    ↓ speech regions
Speaker Embedding (WeSpeaker CoreML)
    ↓ 256-dim vectors per segment
Agglomerative Clustering
    ↓ speaker labels
Segment Merger
    ↓
Final transcript with speaker labels
```

## Performance Expectations (iPhone 17 Pro / A19 Pro)

| Audio Length | Transcription | Diarization | Total Wait After Stop |
|--------------|---------------|-------------|----------------------|
| 5 min        | Real-time     | ~5 sec      | ~5 sec               |
| 30 min       | Real-time     | ~30 sec     | ~30 sec              |
| 60 min       | Real-time     | ~60 sec     | ~60 sec              |

Transcription happens in real-time during recording, so the only wait is for diarization after you stop.

## Memory Budget

| Component           | Peak RAM  |
|--------------------|-----------|
| Whisper Base model | ~500 MB   |
| Silero VAD         | ~10 MB    |
| WeSpeaker          | ~100 MB   |
| Audio buffer (60m) | ~115 MB   |
| Clustering         | ~50 MB    |
| **Total peak**     | **~775 MB** |

Well within the iOS ~2 GB app memory limit.

## Models (No Authentication Required)

All models are publicly available:
- **Whisper Base**: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
- **Silero VAD**: https://huggingface.co/FluidInference/silero-vad-coreml
- **Speaker Diarization**: https://huggingface.co/FluidInference/speaker-diarization-coreml

No HuggingFace token or account needed (unlike the Mac version).

## File Structure

```
src/legacy-ios/
└── TranscriberApp/
    ├── App/TranscriberApp.swift
    ├── Models/ModelManager.swift
    ├── Audio/AudioRecorder.swift
    ├── Transcription/
    │   ├── WhisperBridge.h
    │   ├── WhisperContext.swift
    │   ├── StreamingTranscriber.swift
    │   └── TranscriptionSegment.swift
    ├── Diarization/
    │   ├── VoiceActivityDetector.swift
    │   ├── SpeakerEmbedder.swift
    │   ├── AgglomerativeClustering.swift
    │   ├── DiarizationPipeline.swift
    │   └── DiarizationSegment.swift
    ├── Processing/
    │   ├── SegmentMerger.swift
    │   └── TranscriptExporter.swift
    ├── Storage/Recording.swift
    └── Views/
        ├── ContentView.swift
        ├── RecordingView.swift
        ├── LibraryView.swift
        ├── TranscriptView.swift
        ├── SettingsView.swift
        ├── ModelDownloadView.swift
        └── Components/
            ├── WaveformView.swift
            └── SpeakerBadge.swift
```
