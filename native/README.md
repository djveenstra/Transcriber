# Transcriber 2.0 Beta

This directory contains the native SwiftUI version of Transcriber. It is intentionally
isolated from the working Python Transcriber 1.x application in the repository root.

## Open in Xcode

Open `Transcriber2/Transcriber2.xcodeproj`, select the `Transcriber` scheme, and choose
an iPhone running iOS 26 or a Mac running macOS 26.

The first transcription and diarization sessions may download and compile speech-model
assets. Later sessions process locally on the device.

## Current Features

- Shared iOS/macOS SwiftUI app with separate 2.0 storage and bundle identifier
- iPhone live preview using Parakeet EOU
- Selectable on-device Parakeet and Whisper final-transcription models
- Final FluidAudio Sortformer speaker labels
- Audio-file import, recording library, playback, speaker renaming, and sharing
- TXT, SRT, and JSON transcript exporters
- iPhone Model Lab for comparing downloaded transcription models

## Verification

```sh
xcodebuild -project Transcriber2/Transcriber2.xcodeproj -scheme Transcriber \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Transcriber2/Transcriber2.xcodeproj -scheme Transcriber \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Microphone capture, model installation, FluidAudio model downloads, and real-time
performance must be validated on the iPhone 17 Pro.
