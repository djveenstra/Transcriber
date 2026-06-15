import Foundation

/// Feeds audio to WhisperContext in ~30-second chunks for near-real-time transcription.
/// Accumulates audio samples and transcribes when a chunk is ready.
///
/// Strategy:
/// - Accumulate audio buffers from AudioRecorder
/// - Every 30 seconds of audio (480,000 samples at 16kHz), run whisper transcription
/// - Emit new segments as they're produced
/// - Keep a sliding overlap of 1 second between chunks for continuity
///
/// Runs on a background actor to avoid blocking the main thread.
actor StreamingTranscriber {
    private var whisperContext: WhisperContext?
    private var sampleBuffer: [Float] = []
    private var totalSamplesProcessed: Int = 0

    private let chunkDuration: Double = 30.0    // seconds per chunk
    private let sampleRate: Int = 16000
    private let overlapDuration: Double = 1.0   // seconds of overlap between chunks

    /// Callback when new segments are produced. Called on the actor's executor.
    var onNewSegments: (([TranscriptionSegment]) -> Void)?

    /// Total audio duration received so far (seconds)
    var totalDuration: Double {
        Double(totalSamplesProcessed + sampleBuffer.count) / Double(sampleRate)
    }

    // MARK: - Public API

    /// Load the Whisper model. Must call before appendSamples.
    func loadModel(modelPath: String, coreMLPath: String? = nil) throws {
        whisperContext = try WhisperContext(modelPath: modelPath, coreMLEncoderPath: coreMLPath)
    }

    /// Append new audio samples from the recorder.
    /// Automatically triggers transcription when enough audio has accumulated.
    func appendSamples(_ samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)

        let chunkSamples = Int(chunkDuration * Double(sampleRate))
        if sampleBuffer.count >= chunkSamples {
            processChunk()
        }
    }

    /// Process any remaining audio in the buffer (call when recording stops).
    func flush() {
        guard !sampleBuffer.isEmpty else { return }

        let rawSegments = whisperContext?.transcribe(samples: sampleBuffer) ?? []
        let offsetMs = totalSamplesProcessed * 1000 / sampleRate

        let segments = rawSegments.map { seg in
            TranscriptionSegment(
                startMs: seg.startMs + offsetMs,
                endMs: seg.endMs + offsetMs,
                text: seg.text
            )
        }

        if !segments.isEmpty {
            onNewSegments?(segments)
        }

        totalSamplesProcessed += sampleBuffer.count
        sampleBuffer = []
    }

    /// Reset state for a new recording.
    func reset() {
        sampleBuffer = []
        totalSamplesProcessed = 0
    }

    // MARK: - Private

    private func processChunk() {
        let chunkSamples = Int(chunkDuration * Double(sampleRate))
        let chunk = Array(sampleBuffer.prefix(chunkSamples))

        // Transcribe chunk
        let rawSegments = whisperContext?.transcribe(samples: chunk) ?? []

        // Convert to absolute timestamps
        let offsetMs = totalSamplesProcessed * 1000 / sampleRate
        let segments = rawSegments.map { seg in
            TranscriptionSegment(
                startMs: seg.startMs + offsetMs,
                endMs: seg.endMs + offsetMs,
                text: seg.text
            )
        }

        // Advance buffer (keep overlap for continuity)
        let overlapSamples = Int(overlapDuration * Double(sampleRate))
        let advance = chunkSamples - overlapSamples
        totalSamplesProcessed += advance
        sampleBuffer = Array(sampleBuffer.dropFirst(advance))

        // Emit segments
        if !segments.isEmpty {
            onNewSegments?(segments)
        }
    }
}
