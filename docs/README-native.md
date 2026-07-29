# Native Transcriber Mac App

The active SwiftUI application is `src/native/Transcriber2/`.

## Current capabilities

- Native Dashboard, Library, Model Lab, and Settings.
- Microphone recording and file import.
- Preserved application-owned original audio.
- WhisperKit live/final transcription on Mac.
- FluidAudio Sortformer speaker labeling.
- Transcript-first persistence, retry, cancellation, timeout, and fallback behavior.
- Playback, speaker rename/reassignment, and TXT/SRT/JSON export.
- File-backed model readiness, repair/redownload, diagnostics, and tests.

## Build and test

```sh
xcodebuild -project "src/native/Transcriber2/Transcriber2.xcodeproj" \
  -scheme Transcriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild test \
  -project "src/native/Transcriber2/Transcriber2.xcodeproj" \
  -scheme Transcriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:TranscriberTests
```

## Important boundary

This checkout is Mac-focused. iOS work belongs in `../iOS Transcriber/`. Shared Swift files may still contain iOS-origin branches; remove them only through an approved ownership/removal objective.

Downloaded models, application data, private benchmark audio, voiceprints, and local build output do not belong in Git.
