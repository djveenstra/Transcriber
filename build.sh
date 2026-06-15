#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="/Users/daniel/Documents/whisper-transcriber/.venv"
APP_DEST="/Applications/Transcriber.app"

echo "Building Transcriber.app..."

rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS"
mkdir -p "$APP_DEST/Contents/Resources"

# Info.plist
cat > "$APP_DEST/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Transcriber</string>
    <key>CFBundleDisplayName</key>
    <string>Transcriber</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.transcriber</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Transcriber</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>Transcriber</string>
</dict>
</plist>
PLIST

# Compile a native launcher binary (shell scripts don't launch reliably as .app on modern macOS)
LAUNCHER_SRC="$(mktemp /tmp/launcher_XXXX.swift)"
cat > "$LAUNCHER_SRC" << SWIFT
import Foundation

let task = Process()
task.executableURL = URL(fileURLWithPath: "$VENV/bin/python")
task.arguments = ["-m", "app.main"]
task.currentDirectoryURL = URL(fileURLWithPath: "$SCRIPT_DIR")

// Ensure Homebrew ffmpeg is findable in .app context
var env = ProcessInfo.processInfo.environment
let extraPath = "/opt/homebrew/bin:/usr/local/bin"
env["PATH"] = extraPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
task.environment = env

try! task.run()
task.waitUntilExit()
SWIFT

# Copy icon
if [ -f "$SCRIPT_DIR/Transcriber.icns" ]; then
    cp "$SCRIPT_DIR/Transcriber.icns" "$APP_DEST/Contents/Resources/Transcriber.icns"
fi

echo "Compiling launcher..."
swiftc "$LAUNCHER_SRC" -o "$APP_DEST/Contents/MacOS/Transcriber"
rm "$LAUNCHER_SRC"

echo "Done! Transcriber.app installed to /Applications."
echo "Launch with: open /Applications/Transcriber.app"
