import Foundation

/// Thin Swift wrapper around the whisper.cpp C API.
/// Manages the whisper_context pointer and provides Swift-friendly transcription methods.
///
/// Prerequisites:
/// - whisper.cpp must be integrated as a Swift Package or XCFramework
/// - A bridging header must expose the whisper C API functions
///
/// Key whisper.cpp functions used:
/// - whisper_init_from_file_with_params() — load model
/// - whisper_full() — run full transcription on audio buffer
/// - whisper_full_default_params() — get default parameters
/// - whisper_full_n_segments() — get number of result segments
/// - whisper_full_get_segment_t0/t1() — get segment timestamps (in centiseconds)
/// - whisper_full_get_segment_text() — get segment text
/// - whisper_free() — release context

class WhisperContext {
    private var context: OpaquePointer?  // whisper_context*

    /// Initialize with path to GGML model file.
    /// - Parameters:
    ///   - modelPath: Path to ggml-base.bin (or other model)
    ///   - coreMLEncoderPath: Optional path to CoreML encoder for Neural Engine acceleration
    /// - Throws: WhisperError if model fails to load
    init(modelPath: String, coreMLEncoderPath: String? = nil) throws {
        // Create context parameters
        var contextParams = whisper_context_default_params()

        // Enable CoreML if encoder path provided
        if coreMLEncoderPath != nil {
            contextParams.use_gpu = true
            // CoreML encoder is automatically detected if placed alongside the model
            // The path convention is: model.bin → model-encoder.mlmodelc
        }

        // Initialize whisper context
        context = whisper_init_from_file_with_params(modelPath, contextParams)

        guard context != nil else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
    }

    /// Transcribe a buffer of 16kHz mono Float32 audio samples.
    /// - Parameter samples: Audio samples at 16000 Hz sample rate
    /// - Returns: Array of transcription segments with timestamps
    func transcribe(samples: [Float]) -> [TranscriptionSegment] {
        guard let ctx = context else { return [] }

        // Set up transcription parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4                  // Good balance for iPhone
        params.language = "en".withCString { strdup($0) }  // English
        params.translate = false              // Don't translate
        params.no_context = true              // Don't use previous context for streaming
        params.single_segment = false         // Allow multiple segments
        params.print_special = false          // Don't print special tokens
        params.print_progress = false         // Don't print progress
        params.print_realtime = false         // Don't print in real-time
        params.print_timestamps = false       // Don't print timestamps to console

        // Run transcription
        let result = samples.withUnsafeBufferPointer { bufferPtr in
            whisper_full(ctx, params, bufferPtr.baseAddress, Int32(samples.count))
        }

        guard result == 0 else { return [] }

        // Extract segments
        let numSegments = whisper_full_n_segments(ctx)
        var segments: [TranscriptionSegment] = []

        for i in 0..<numSegments {
            let startCs = whisper_full_get_segment_t0(ctx, i)  // centiseconds
            let endCs = whisper_full_get_segment_t1(ctx, i)    // centiseconds
            let textPtr = whisper_full_get_segment_text(ctx, i)

            let text = textPtr.map { String(cString: $0) } ?? ""
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedText.isEmpty {
                segments.append(TranscriptionSegment(
                    startMs: Int(startCs) * 10,   // Convert centiseconds to milliseconds
                    endMs: Int(endCs) * 10,
                    text: trimmedText
                ))
            }
        }

        return segments
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    enum WhisperError: LocalizedError {
        case modelLoadFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let path):
                return "Failed to load Whisper model at: \(path)"
            }
        }
    }
}
