/// Bridging header for whisper.cpp C API.
///
/// This file must be set as the "Objective-C Bridging Header" in Xcode:
/// Build Settings → Swift Compiler - General → Objective-C Bridging Header
///
/// Prerequisites: whisper.cpp must be added to the project as either:
/// 1. A Swift Package: https://github.com/ggerganov/whisper.cpp (use the SPM branch)
/// 2. An XCFramework built with: examples/whisper.swiftui/build-xcframework.sh
/// 3. Source files added directly (whisper.h, whisper.cpp, ggml.h, ggml.c, etc.)

#ifndef WhisperBridge_h
#define WhisperBridge_h

#include "whisper.h"

#endif /* WhisperBridge_h */
