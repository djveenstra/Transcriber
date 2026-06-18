# Transcriber

Transcriber is an on-device transcription app with speaker labeling.

This repository contains two independent versions:

- `src/python/`: the original Python desktop application.
- `src/native/Transcriber2/`: Transcriber 2.0 Beta, a SwiftUI app for iPhone and Mac.
- `src/legacy-ios/`: an older standalone iOS prototype kept for reference.

The native app records audio immediately, supports live transcription on iPhone,
creates a final transcript using a selected on-device model, and applies final
speaker labels after recording.

## Native App

Open `src/native/Transcriber2/Transcriber2.xcodeproj` in Xcode and select the
`Transcriber` scheme. The app targets iOS 26 and macOS 26.

Downloaded speech models, recordings, compiled applications, and local Xcode
build output are intentionally excluded from Git.

## Python App

Install the Python dependencies:

```sh
python3 -m pip install -r src/python/requirements.txt
```

Run the desktop app:

```sh
cd src/python
python3 -m app.main
```

Run its tests:

```sh
cd src/python
python3 -m pytest
```
