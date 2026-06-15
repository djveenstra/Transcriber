# Transcriber

Transcriber is an on-device transcription app with speaker labeling.

This repository contains two independent versions:

- `app/`: the original Python desktop application.
- `native/Transcriber2/`: Transcriber 2.0 Beta, a SwiftUI app for iPhone and Mac.

The native app records audio immediately, supports live transcription on iPhone,
creates a final transcript using a selected on-device model, and applies final
speaker labels after recording.

## Native App

Open `native/Transcriber2/Transcriber2.xcodeproj` in Xcode and select the
`Transcriber` scheme. The app targets iOS 26 and macOS 26.

Downloaded speech models, recordings, compiled applications, and local Xcode
build output are intentionally excluded from Git.

## Python App

Install the Python dependencies:

```sh
python3 -m pip install -r requirements.txt
```

Run the desktop app:

```sh
python3 -m app.main
```

Run its tests:

```sh
python3 -m pytest
```
