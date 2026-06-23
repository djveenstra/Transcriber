import AVFoundation
import Foundation
import SwiftData
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
        case ignoreCancellation
        case stageHang(DiarizationDiagnosticStage)
    }

    private let behavior: Behavior

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func diarizeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void,
        stage: @escaping @Sendable (DiarizationStageEvent) -> Void
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
        case .ignoreCancellation:
            while true {
                try? await Task.sleep(for: .seconds(60))
            }
        case let .stageHang(hangingStage):
            stage(DiarizationStageEvent(.started, hangingStage))
            while true {
                try? await Task.sleep(for: .seconds(60))
            }
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
        progress: @escaping @Sendable (Double) -> Void,
        stage: @escaping @Sendable (DiarizationStageEvent) -> Void
    ) async throws -> [DiarizationSegment] {
        for i in 0..<chunkCount {
            try Task.checkCancellation()
            stage(DiarizationStageEvent(.started, .process, detail: "chunk \(i)"))
            try await Task.sleep(for: chunkDuration)
            stage(DiarizationStageEvent(.ended, .process, detail: "chunk \(i)"))
            progress(Double(i + 1) / Double(chunkCount))
        }
        return [DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")]
    }
}

@MainActor
struct DiarizationFallbackTests {
    private let url = URL(fileURLWithPath: "/tmp/test.caf")

    private func makeSession(attemptGuard: DiarizationAttemptGuard = DiarizationAttemptGuard()) -> TranscriptionSession {
        let session = TranscriptionSession(diarizationAttemptGuard: attemptGuard)
        session.diarizationInitialTimeout = 0.05
        session.diarizationProgressTimeout = 0.05
        session.diarizationStageTimeouts = .legacy(initialTimeout: 0.05, progressTimeout: 0.05)
        session.diarizationPollInterval = .milliseconds(10)
        return session
    }

    @Test func succeedsOnFirstAttemptWithoutFallback() async throws {
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))

        let outcome = try #require(await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.fail("fallback should not run"))
        ))

        #expect(outcome.isApproximate == false)
        #expect(outcome.segments.map(\.speaker) == ["SPEAKER_00"])
        #expect(session.latestDiagnostics?.diarizationFallbackUsed == false)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .complete)
    }

    @Test func fallsBackToFastV2WhenPrimaryFails() async throws {
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.fail("primary failed"))

        let outcome = try #require(await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.succeed([
                DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
            ]))
        ))

        #expect(outcome.isApproximate == true)
        #expect(outcome.segments.map(\.speaker) == ["SPEAKER_00"])
        #expect(session.latestDiagnostics?.diarizationFallbackUsed == true)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .approximate)
    }

    @Test func returnsNilAndRecordsFailureDetailWhenBothAttemptsFail() async {
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.fail("primary failed"))

        let outcome = await session.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.fail("fallback failed"))
        )

        #expect(outcome == nil)
        #expect(session.diarizationFailureDetail == "fallback failed")
        #expect(session.latestDiagnostics?.speakerLabelStatus == .retryNeeded)
        #expect(session.latestDiagnostics?.failureMessage == "fallback failed")
    }

    @Test func watchdogTimesOutWhenDiarizationHangsWithoutProgress() async {
        let session = makeSession()
        let hangingEngine = FakeDiarizationEngine(.stageHang(.modelLoad))

        let outcome = await session.diarizeWithWatchdog(
            using: hangingEngine,
            url: url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10)
        )

        guard case .timedOut(let message) = outcome else {
            Issue.record("Expected timeout, got \(String(describing: outcome))")
            return
        }
        #expect(message.contains("timed out"))
        #expect(message.contains("model/resource loading"))
        #expect(session.diarizationFailureDetail?.contains("timed out") == true)
        #expect(session.latestDiagnostics?.diarizationTimedOutStage == .modelLoad)
        #expect(await session.hasUnsafeDiarizationAttemptForTesting())
    }

    @Test func retryGuardClearsWhenTimedOutAttemptCooperativelyEnds() async throws {
        let attemptGuard = DiarizationAttemptGuard()
        let firstSession = makeSession(attemptGuard: attemptGuard)
        firstSession.diarizer = FakeDiarizationEngine(.hang)

        let timedOut = await firstSession.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.succeed([]))
        )
        #expect(timedOut == nil)

        for _ in 0..<100 {
            if !(await firstSession.hasUnsafeDiarizationAttemptForTesting()) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!(await firstSession.hasUnsafeDiarizationAttemptForTesting()))

        let retrySession = makeSession(attemptGuard: attemptGuard)
        retrySession.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))
        let retry = await retrySession.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.fail("fallback should not run"))
        )
        #expect(retry != nil)
    }

    @Test func timeoutDoesNotStartFallbackWhilePriorAttemptMayStillBeAlive() async {
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.ignoreCancellation)

        let outcome = await session.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.succeed([
                DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_99")
            ]))
        )

        #expect(outcome == nil)
        #expect(session.diarizationFailureDetail?.contains("timed out") == true)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .retryNeeded)
    }

    @Test func unsafePriorAttemptBlocksOverlappingRetry() async {
        let attemptGuard = DiarizationAttemptGuard()
        let firstSession = makeSession(attemptGuard: attemptGuard)
        firstSession.diarizer = FakeDiarizationEngine(.ignoreCancellation)

        let timedOut = await firstSession.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.succeed([]))
        )
        #expect(timedOut == nil)

        let secondSession = makeSession(attemptGuard: attemptGuard)
        secondSession.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))

        let blocked = await secondSession.runDiarizationWithFallback(
            url,
            fallbackEngine: FakeDiarizationEngine(.succeed([]))
        )

        #expect(blocked == nil)
        #expect(secondSession.diarizationFailureDetail?.contains("previous speaker-labeling attempt") == true)
    }

    @Test func chunkedPrimaryTimesOutWithoutStartingFallback() async {
        let session = makeSession()
        // Primary: 100 chunks of 200ms each — won't report progress quickly enough
        // for the 50ms timeout. The app returns control without starting fallback
        // because the primary attempt may still be inside FluidAudio/Core ML.
        session.diarizer = ChunkedFakeDiarizationEngine(
            chunkCount: 100,
            chunkDuration: .milliseconds(200)
        )

        let outcome = await session.runDiarizationWithFallback(
            url,
            initialTimeout: 0.05,
            progressTimeout: 0.05,
            pollInterval: .milliseconds(10),
            fallbackEngine: FakeDiarizationEngine(.succeed([
                DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
            ]))
        )

        #expect(outcome == nil)
        #expect(session.diarizationFailureDetail?.contains("timed out") == true)
    }

    @Test func chunkedBothTimeOutAndReturnsNil() async {
        let session = makeSession()
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

    @Test func retrySpeakerLabelsUsesStoredRawTranscriptionWithoutReplacingTranscriptText() async throws {
        let container = try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let rawTranscription = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Stored transcript")
        ]
        let recording = Recording(
            title: "Needs Labels",
            durationSeconds: 1,
            audioFileName: "needs-labels.caf",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Stored transcript")
            ],
            rawTranscription: rawTranscription,
            diarizationNeedsRetry: true
        )
        context.insert(recording)
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_02")
        ]))

        await session.retrySpeakerLabels(for: recording, in: context)

        #expect(recording.rawTranscription == rawTranscription)
        #expect(recording.segments.map(\.text) == ["Stored transcript"])
        #expect(recording.segments.map(\.speaker) == ["SPEAKER_02"])
        #expect(!recording.transcriptionNeedsRetry)
        #expect(!recording.diarizationNeedsRetry)
        #expect(session.speakerLabelStatusPresentation.kind == .complete)
    }

    @Test func retrySpeakerLabelsTimeoutClearsActivityAndPreservesTranscriptAndAudio() async throws {
        let container = try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let recording = try makeRetryableRecording(audioFileName: "timeout-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        context.insert(recording)

        let originalSegments = recording.segments
        let originalRaw = recording.rawTranscription
        let session = makeSession()
        session.diarizer = FakeDiarizationEngine(.ignoreCancellation)

        await session.retrySpeakerLabels(for: recording, in: context)

        #expect(session.state == .completed)
        #expect(session.currentProcessingPhase == nil)
        #expect(!session.isIdentifyingSpeakers)
        #expect(recording.segments == originalSegments)
        #expect(recording.rawTranscription == originalRaw)
        #expect(recording.diarizationNeedsRetry)
        #expect(session.speakerLabelStatusPresentation.showsRetry)
        #expect(AudioPlaybackFileInspector.duration(for: recording.audioURL) ?? 0 > 0)
    }

    @Test func cancelDuringSpeakerLabelingClearsActivityAndPreservesTranscript() async throws {
        let container = try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let recording = try makeRetryableRecording(audioFileName: "cancel-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        context.insert(recording)

        let originalSegments = recording.segments
        let originalRaw = recording.rawTranscription
        let session = makeSession()
        session.diarizationInitialTimeout = 10
        session.diarizationProgressTimeout = 10
        session.diarizer = FakeDiarizationEngine(.ignoreCancellation)

        let retryTask = Task {
            await session.retrySpeakerLabels(for: recording, in: context)
        }
        for _ in 0..<100 where !session.canCancelProcessing {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.canCancelProcessing)
        await session.cancelProcessing()
        await retryTask.value

        #expect(session.state == .completed)
        #expect(session.currentProcessingPhase == nil)
        #expect(!session.isIdentifyingSpeakers)
        #expect(recording.segments == originalSegments)
        #expect(recording.rawTranscription == originalRaw)
        #expect(recording.diarizationNeedsRetry)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .canceled)
        #expect(session.completionNote?.contains("canceled") == true)
        #expect(AudioPlaybackFileInspector.duration(for: recording.audioURL) ?? 0 > 0)
    }

    private func makeRetryableRecording(audioFileName: String) throws -> Recording {
        let url = AppStoragePaths.recordingsDirectory.appendingPathComponent(audioFileName)
        try writeSilentCAF(to: url)
        return Recording(
            title: "Needs Labels",
            durationSeconds: 1,
            audioFileName: audioFileName,
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Stored transcript")
            ],
            rawTranscription: [
                TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Stored transcript")
            ],
            diarizationNeedsRetry: true
        )
    }

    private func writeSilentCAF(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        try file.write(from: buffer)
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
