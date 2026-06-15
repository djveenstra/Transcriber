@preconcurrency import AVFoundation
import Foundation

/// An immutable, deep-copied snapshot of an audio buffer.
///
/// `AVAudioPCMBuffer` is not `Sendable` and tap-supplied buffers are only valid for the
/// duration of the tap callback. `CapturedAudioChunk` owns a private copy of the channel
/// data made at initialization time, is never mutated afterward, and is therefore safe to
/// pass across actor and concurrency-domain boundaries.
struct CapturedAudioChunk: @unchecked Sendable {
    nonisolated(unsafe) let buffer: AVAudioPCMBuffer

    nonisolated init?(copying source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameCapacity) else {
            return nil
        }
        copy.frameLength = source.frameLength
        for channel in 0..<Int(source.format.channelCount) {
            guard let sourceData = source.floatChannelData?[channel],
                  let destinationData = copy.floatChannelData?[channel] else {
                continue
            }
            destinationData.update(from: sourceData, count: Int(source.frameLength))
        }
        self.buffer = copy
    }
}

/// Writes captured audio chunks to disk on a dedicated serial queue.
///
/// This decouples file I/O from both the real-time audio render thread (where the tap
/// callback fires) and the `@MainActor`-isolated `AudioRecorder`. `close()` drains any
/// in-flight writes before releasing the underlying file, so no callback can write to a
/// closed file.
final class AudioFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.daniel.transcriber2.audio-file-writer")
    nonisolated(unsafe) private var file: AVAudioFile?

    nonisolated init(url: URL, settings: [String: Any]) throws {
        file = try AVAudioFile(forWriting: url, settings: settings)
    }

    nonisolated func write(_ chunk: CapturedAudioChunk) {
        queue.async { [weak self] in
            try? self?.file?.write(from: chunk.buffer)
        }
    }

    /// Waits for any writes already queued to finish, then releases the file. Safe to call
    /// once recording has stopped; any write enqueued afterward becomes a no-op.
    nonisolated func close() {
        queue.sync {
            file = nil
        }
    }
}
