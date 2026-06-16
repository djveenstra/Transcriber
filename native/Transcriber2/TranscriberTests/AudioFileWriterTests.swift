@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Transcriber

struct AudioFileWriterTests {
    private static let sampleRate: Double = 16_000
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    private func makeSilentChunk(frameCount: AVAudioFrameCount = 160) -> CapturedAudioChunk {
        let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        memset(buffer.floatChannelData![0], 0, Int(frameCount) * MemoryLayout<Float>.size)
        return CapturedAudioChunk(copying: buffer)!
    }

    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("writer-test-\(UUID().uuidString).caf")
    }

    @Test func successfulWritesDrainBeforeCloseReturns() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, settings: Self.format.settings)
        for _ in 0..<10 {
            writer.write(makeSilentChunk())
        }
        try writer.close()

        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 10 * 160)
    }

    @Test func closeThrowsFirstWriteError() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, settings: Self.format.settings)
        writer.write(makeSilentChunk())

        let badFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let badBuffer = AVAudioPCMBuffer(pcmFormat: badFormat, frameCapacity: 160)!
        badBuffer.frameLength = 160
        let badChunk = CapturedAudioChunk(copying: badBuffer)!
        writer.write(badChunk)

        writer.write(makeSilentChunk())

        do {
            try writer.close()
            Issue.record("Expected close() to throw, but it did not")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test func closeSucceedsWithNoWrites() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AudioFileWriter(url: url, settings: Self.format.settings)
        try writer.close()

        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 0)
    }
}
