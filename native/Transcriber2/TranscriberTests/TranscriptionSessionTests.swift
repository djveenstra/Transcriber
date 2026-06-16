import Foundation
import Testing
@testable import Transcriber

private struct FakeDiarizationError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Test double for `DiarizationEngine` used to exercise
/// `TranscriptionSession.runDiarizationWithFallback` / `diarizeWithWatchdog`
/// without needing real Sortformer models.
private actor FakeDiarizationEngine: DiarizationEngine {
    enum Behavior {
        case succeed([DiarizationSegment])
        case fail(String)
        case hang
    }

    private let behavior: Behavior

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [DiarizationSegment] {
        switch behavior {
        case let .succeed(segments):
            return segments
        case let .fail(message):
            throw FakeDiarizationError(message: message)
        case .hang:
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(60))
            }
            throw CancellationError()
        }
    }
}

/// Simulates a diarization engine that does blocking work in chunks and only
/// checks for cancellation between chunks — mirroring the real chunked
/// Sortformer loop. Each chunk takes `chunkDuration` wall time.
private actor ChunkedFakeDiarizationEngine: DiarizationEngine {
    private let chunkCount: Int
    private let chunkDuration: Duration

    init(chunkCount: Int, chunkDuration: Duration) {
        self.chunkCount = chunkCount
        self.chunkDuration = chunkDuration
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [DiarizationSegment] {
        for i in 0..<chunkCount {
            try Task.checkCancellation()
            try await Task.sleep(for: chunkDuration)
            progress(Double(i + 1) / Double(chunkCount))
        }
        return [DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")]
    }
}

@MainActor
struct DiarizationFallbackTests {
    private let url = URL(fileURLWithPath: "/tmp/test.caf")

    @Test func succeedsOnFirstAttemptWithoutFallback() async throws {
        let session = TranscriptionSession()
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))

        let outcome = try #require(await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.fail("fallback should not run"))
        ))

        #expect(outcome.isApproximate == false)
        #expect(outcome.segments.map(\.speaker) == ["SPEAKER_00"])
    }

    @Test func fallsBackToFastV2WhenPrimaryFails() async throws {
        let session = TranscriptionSession()
        session.diarizer = FakeDiarizationEngine(.fail("primary failed"))

        let outcome = try #require(await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.succeed([
                DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
            ]))
        ))

        #expect(outcome.isApproximate == true)
        #expect(outcome.segments.map(\.speaker) == ["SPEAKER_00"])
    }

    @Test func returnsNilAndRecordsFailureDetailWhenBothAttemptsFail() async {
        let session = TranscriptionSession()
        session.diarizer = FakeDiarizationEngine(.fail("primary failed"))

        let outcome = await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.fail("fallback failed"))
        )

        #expect(outcome == nil)
        #expect(session.diarizationFailureDetail == "fallback failed")
    }

    @Test func watchdogTimesOutWhenDiarizationHangsWithoutProgress() async {
        let session = TranscriptionSession()
        let hangingEngine = FakeDiarizationEngine(.hang)

        let segments = await session.diarizeWithWatchdog(
            using: hangingEngine,
            url: url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10)
        )

        #expect(segments == nil)
        #expect(session.diarizationFailureDetail == "Speaker labeling timed out while processing this recording.")
    }

    @Test func runDiarizationWithFallbackTimesOutBothAttemptsAndReturnsNil() async {
        let session = TranscriptionSession()
        session.diarizer = FakeDiarizationEngine(.hang)

        let outcome = await session.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.hang)
        )

        #expect(outcome == nil)
        #expect(session.diarizationFailureDetail == "Speaker labeling timed out while processing this recording.")
    }

    @Test func chunkedPrimaryTimesOutAndFallbackSucceeds() async throws {
        let session = TranscriptionSession()
        // Primary: 100 chunks of 200ms each — won't report progress quickly enough
        // for the 50ms timeout, so the watchdog cancels it between chunks.
        session.diarizer = ChunkedFakeDiarizationEngine(
            chunkCount: 100,
            chunkDuration: .milliseconds(200)
        )

        let outcome = try #require(await session.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.succeed([
                DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
            ]))
        ))

        #expect(outcome.isApproximate == true)
        #expect(outcome.segments.count == 1)
    }

    @Test func chunkedBothTimeOutAndReturnsNil() async {
        let session = TranscriptionSession()
        session.diarizer = ChunkedFakeDiarizationEngine(
            chunkCount: 100,
            chunkDuration: .milliseconds(200)
        )

        let outcome = await session.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: ChunkedFakeDiarizationEngine(
                chunkCount: 100,
                chunkDuration: .milliseconds(200)
            )
        )

        #expect(outcome == nil)
    }
}

struct OrderedLiveAudioTests {
    @Test func asyncStreamConsumerDeliversChunksInCaptureOrder() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let count = 50
        for i in 0..<count {
            continuation.yield(i)
        }
        continuation.finish()

        var received: [Int] = []
        for await value in stream {
            received.append(value)
        }

        #expect(received == Array(0..<count))
    }

    @Test func finishingStreamTerminatesConsumer() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        continuation.yield(1)
        continuation.yield(2)
        continuation.finish()

        let task = Task {
            var values: [Int] = []
            for await v in stream { values.append(v) }
            return values
        }

        let result = await task.value
        #expect(result == [1, 2])
    }

    @Test func cancellingConsumerStopsIteration() async {
        let (stream, _) = AsyncStream.makeStream(of: Int.self)

        let task = Task {
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }
        task.cancel()
        let result = await task.value
        #expect(result == 0)
    }
}

@MainActor
struct LiveSegmentMergingTests {
    @Test func newSegmentReplacesAllOverlappingSegments() {
        let existing = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Hello"),
            TranscriptionSegment(startMs: 1_000, endMs: 2_000, text: "world"),
            TranscriptionSegment(startMs: 5_000, endMs: 6_000, text: "Finalized"),
        ]
        let updated = TranscriptionSegment(startMs: 900, endMs: 2_500, text: "Hello world updated")

        let result = TranscriptionSession.mergingLiveSegment(updated, into: existing)

        #expect(result.map(\.text) == ["Hello world updated", "Finalized"])
    }

    @Test func newSegmentIsInsertedInStartTimeOrder() {
        let existing = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "First"),
            TranscriptionSegment(startMs: 4_000, endMs: 5_000, text: "Third"),
        ]
        let newSegment = TranscriptionSegment(startMs: 2_000, endMs: 3_000, text: "Second")

        let result = TranscriptionSession.mergingLiveSegment(newSegment, into: existing)

        #expect(result.map(\.text) == ["First", "Second", "Third"])
    }

    @Test func nonOverlappingSegmentsAreAllPreserved() {
        let existing = [TranscriptionSegment(startMs: 0, endMs: 1_000, text: "First")]
        let newSegment = TranscriptionSegment(startMs: 1_000, endMs: 2_000, text: "Second")

        let result = TranscriptionSession.mergingLiveSegment(newSegment, into: existing)

        #expect(result.map(\.text) == ["First", "Second"])
    }
}
