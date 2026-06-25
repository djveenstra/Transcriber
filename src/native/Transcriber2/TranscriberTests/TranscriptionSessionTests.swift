import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Transcriber

private struct FakeDiarizationError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct FakeTranscriptionError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor ScriptedTranscriptionEngine: TranscriptionEngine {
    enum Step: Sendable {
        case succeed([TranscriptionSegment])
        case fail(String)
        case waitForUnload
        case waitForRelease([TranscriptionSegment])
    }

    private let steps: [Step]
    private let serializesTranscriptionCalls: Bool
    private var callCount = 0
    private var unloadCount = 0
    private var activeCallCount = 0
    private var maxConcurrentCallCount = 0
    private var transcriptionSlotIsOccupied = false
    private var transcriptionSlotWaiters: [CheckedContinuation<Void, Never>] = []
    private var releasedCalls: Set<Int> = []
    private var callsReleasedByUnload: Set<Int> = []

    init(_ steps: [Step], serializesTranscriptionCalls: Bool = false) {
        self.steps = steps
        self.serializesTranscriptionCalls = serializesTranscriptionCalls
    }

    func prepare() async throws {}
    func beginLive(onSegment: @escaping @Sendable (TranscriptionSegment) -> Void) {}
    func prepareLive(audioFormat: AVAudioFormat) async throws {}
    func append(_ chunk: CapturedAudioChunk) async throws {}
    func finishLive() async throws {}

    func transcribeFile(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
        if serializesTranscriptionCalls {
            await acquireTranscriptionSlot()
        }
        activeCallCount += 1
        maxConcurrentCallCount = max(maxConcurrentCallCount, activeCallCount)
        defer {
            activeCallCount -= 1
            if serializesTranscriptionCalls {
                releaseTranscriptionSlot()
            }
        }
        let call = callCount
        callCount += 1
        let step = steps[min(call, steps.count - 1)]
        progress(0.25)
        switch step {
        case let .succeed(segments):
            progress(1)
            return segments
        case let .fail(message):
            throw FakeTranscriptionError(message: message)
        case .waitForUnload:
            callsReleasedByUnload.insert(call)
            while !releasedCalls.contains(call) {
                try? await Task.sleep(for: .milliseconds(10))
            }
            throw CancellationError()
        case let .waitForRelease(segments):
            while !releasedCalls.contains(call) {
                try? await Task.sleep(for: .milliseconds(10))
            }
            progress(1)
            return segments
        }
    }

    func currentLoadedModelID() -> String? { "fake-model" }

    func unload() async {
        unloadCount += 1
        for call in callsReleasedByUnload {
            releasedCalls.insert(call)
        }
    }

    func release(call: Int) {
        releasedCalls.insert(call)
    }

    func observedCallCount() -> Int { callCount }
    func observedUnloadCount() -> Int { unloadCount }
    func observedMaxConcurrentCallCount() -> Int { maxConcurrentCallCount }

    private func acquireTranscriptionSlot() async {
        if !transcriptionSlotIsOccupied {
            transcriptionSlotIsOccupied = true
            return
        }
        await withCheckedContinuation { continuation in
            transcriptionSlotWaiters.append(continuation)
        }
    }

    private func releaseTranscriptionSlot() {
        if transcriptionSlotWaiters.isEmpty {
            transcriptionSlotIsOccupied = false
        } else {
            transcriptionSlotWaiters.removeFirst().resume()
        }
    }
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
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
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
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
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

@MainActor
struct TranscriptionSessionFailureInjectionTests {
    @Test func cancelDuringRetryTranscriptionPreservesAudioAndRetryStateAndUnloadsModel() async throws {
        let (context, recording) = try makeRecording(
            audioFileName: "cancel-transcription-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        let engine = ScriptedTranscriptionEngine([.waitForUnload])
        let session = makeSession(engine: engine)

        let task = Task {
            await session.retryTranscription(for: recording, in: context)
        }
        try await waitUntil { await engine.observedCallCount() == 1 }
        await session.cancelProcessing()
        await task.value

        #expect(recording.transcriptionNeedsRetry)
        #expect(recording.segments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: recording.audioURL.path))
        #expect(session.currentProcessingPhase == nil)
        #expect(session.state == .failed("Processing was canceled. Your recording is saved and can be retried from the library."))
        #expect(await engine.observedUnloadCount() == 1)
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
    }

    @Test func retryTranscriptionRunsInitialSpeakerLabelsAndPersistsHappyPath() async throws {
        let (context, recording) = try makeRecording(
            audioFileName: "retry-happy-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        let transcript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Fresh transcript")
        ]
        let engine = ScriptedTranscriptionEngine([.succeed(transcript)])
        let session = makeSession(engine: engine)
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_03")
        ]))

        await session.retryTranscription(for: recording, in: context)

        #expect(session.state == .completed)
        #expect(recording.rawTranscription == transcript)
        #expect(recording.segments.map(\.text) == ["Fresh transcript"])
        #expect(recording.segments.map(\.speaker) == ["SPEAKER_03"])
        #expect(!recording.transcriptionNeedsRetry)
        #expect(!recording.diarizationNeedsRetry)
        #expect(session.currentProcessingPhase == nil)
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
    }

    @Test func cancelDuringImportedInitialFinalTranscriptionKeepsCopiedAudioRetryable() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-source-\(UUID().uuidString).caf")
        try writeSilentCAF(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let engine = ScriptedTranscriptionEngine([.waitForUnload])
        let session = makeSession(engine: engine)

        let task = Task {
            await session.importAudio(sourceURL, in: context)
        }
        try await waitUntil {
            let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
            guard recordings.count == 1 else { return false }
            return await engine.observedCallCount() == 1
        }
        let imported = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(imported.transcriptionNeedsRetry)
        #expect(FileManager.default.fileExists(atPath: imported.audioURL.path))

        await session.cancelProcessing()
        await task.value

        #expect(imported.transcriptionNeedsRetry)
        #expect(imported.segments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: imported.audioURL.path))
        #expect(RecordingStatusActivityStore.shared.activity(for: imported) == nil)
        #expect(await engine.observedUnloadCount() == 1)
        try? FileManager.default.removeItem(at: imported.audioURL)
    }

    @Test func cancelDuringInitialPostTranscriptionSpeakerLabelsPreservesTranscriptAndAudio() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("initial-label-cancel-\(UUID().uuidString).caf")
        try writeSilentCAF(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let transcript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Transcript before labels")
        ]
        let session = makeSession(engine: ScriptedTranscriptionEngine([.succeed(transcript)]))
        session.diarizationInitialTimeout = 10
        session.diarizationProgressTimeout = 10
        session.diarizer = FakeDiarizationEngine(.ignoreCancellation)

        let task = Task {
            await session.importAudio(sourceURL, in: context)
        }
        try await waitUntil {
            guard session.currentProcessingPhase == .identifyingSpeakers else { return false }
            return session.canCancelProcessing
        }
        let imported = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(imported.rawTranscription == transcript)
        #expect(imported.segments.map(\.text) == ["Transcript before labels"])

        await session.cancelProcessing()
        await task.value

        #expect(session.state == .completed)
        #expect(session.currentProcessingPhase == nil)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .canceled)
        #expect(imported.rawTranscription == transcript)
        #expect(imported.segments.map(\.text) == ["Transcript before labels"])
        #expect(!imported.transcriptionNeedsRetry)
        #expect(imported.diarizationNeedsRetry)
        #expect(FileManager.default.fileExists(atPath: imported.audioURL.path))
        #expect(RecordingStatusActivityStore.shared.activity(for: imported) == nil)
        try? FileManager.default.removeItem(at: imported.audioURL)
    }

    @Test func currentSpeakerLabelRetryReusesTranscriptAndUpdatesOnlyLabels() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("current-labels-\(UUID().uuidString).caf")
        try writeSilentCAF(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let transcript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Keep this text")
        ]
        let session = makeSession(engine: ScriptedTranscriptionEngine([.succeed(transcript)]))
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))

        await session.importAudio(sourceURL, in: context)
        #expect(session.state == .completed)
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_02")
        ]))

        await session.retryCurrentSpeakerLabels()

        #expect(session.state == .completed)
        #expect(session.rawTranscription == transcript)
        #expect(session.finalSegments.map(\.text) == ["Keep this text"])
        #expect(session.finalSegments.map(\.speaker) == ["SPEAKER_02"])
        #expect(!session.diarizationNeedsRetry)
        if let imported = try context.fetch(FetchDescriptor<Recording>()).first {
            try? FileManager.default.removeItem(at: imported.audioURL)
        }
    }

    @Test func cancelDuringCurrentSpeakerLabelRetryPreservesCurrentTranscriptAndClearsActivity() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("current-label-cancel-\(UUID().uuidString).caf")
        try writeSilentCAF(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let transcript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Current transcript")
        ]
        let session = makeSession(engine: ScriptedTranscriptionEngine([.succeed(transcript)]))
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00")
        ]))
        await session.importAudio(sourceURL, in: context)
        let imported = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        let originalSegments = imported.segments

        session.diarizationInitialTimeout = 10
        session.diarizationProgressTimeout = 10
        session.diarizer = FakeDiarizationEngine(.ignoreCancellation)
        let retryTask = Task {
            await session.retryCurrentSpeakerLabels()
        }
        try await waitUntil {
            session.currentProcessingPhase == .identifyingSpeakers && session.canCancelProcessing
        }
        await session.cancelProcessing()
        await retryTask.value

        #expect(session.state == .completed)
        #expect(session.currentProcessingPhase == nil)
        #expect(session.rawTranscription == transcript)
        #expect(session.finalSegments == originalSegments)
        #expect(session.diarizationNeedsRetry)
        #expect(session.latestDiagnostics?.speakerLabelStatus == .canceled)
        #expect(imported.rawTranscription == transcript)
        #expect(imported.segments == originalSegments)
        #expect(RecordingStatusActivityStore.shared.activity(for: imported) == nil)
        try? FileManager.default.removeItem(at: imported.audioURL)
    }

    @Test func saveFailureShowsStorageAlertAndLaterCancellationRetriesSave() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-failure-\(UUID().uuidString).caf")
        try writeSilentCAF(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        var saveAttempts = 0
        let engine = ScriptedTranscriptionEngine([.waitForUnload])
        let session = makeSession(
            engine: engine,
            persistenceSave: { context in
                saveAttempts += 1
                if saveAttempts == 1 {
                    throw FakeTranscriptionError(message: "forced save failure")
                }
                try context.save()
            }
        )

        let task = Task {
            await session.importAudio(sourceURL, in: context)
        }
        try await waitUntil {
            guard session.storageErrorMessage != nil else { return false }
            return await engine.observedCallCount() == 1
        }
        #expect(session.storageErrorMessage?.contains("could not be saved") == true)

        await session.cancelProcessing()
        await task.value

        #expect(saveAttempts >= 2)
        #expect(session.storageErrorMessage == nil)
        let imported = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(imported.transcriptionNeedsRetry)
        #expect(FileManager.default.fileExists(atPath: imported.audioURL.path))
        try? FileManager.default.removeItem(at: imported.audioURL)
    }

    @Test func modelVerificationFailureLeavesRecordingRetryableAndClearsActivity() async throws {
        let (context, recording) = try makeRecording(
            audioFileName: "verification-failure-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        let session = makeSession(
            engine: ScriptedTranscriptionEngine([.fail("transcriber should not run")]),
            verification: { _ in .failed("forced verification failure") }
        )

        await session.retryTranscription(for: recording, in: context)

        guard case let .failed(message) = session.state else {
            Issue.record("Expected failed state")
            return
        }
        #expect(message.contains("forced verification failure"))
        #expect(recording.transcriptionNeedsRetry)
        #expect(FileManager.default.fileExists(atPath: recording.audioURL.path))
        #expect(session.currentProcessingPhase == nil)
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
    }

    @Test func rapidCancelThenRetryCannotBeOverwrittenByLateOlderAttempt() async throws {
        let (context, recording) = try makeRecording(
            audioFileName: "overlap-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        defer { try? FileManager.default.removeItem(at: recording.audioURL) }
        let oldTranscript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Stale transcript")
        ]
        let newTranscript = [
            TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Newest transcript")
        ]
        let engine = ScriptedTranscriptionEngine([
            .waitForRelease(oldTranscript),
            .succeed(newTranscript),
        ], serializesTranscriptionCalls: true)
        let session = makeSession(engine: engine)
        session.diarizer = FakeDiarizationEngine(.succeed([
            DiarizationSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_01")
        ]))

        let oldTask = Task {
            await session.retryTranscription(for: recording, in: context)
        }
        try await waitUntil { await engine.observedCallCount() == 1 }
        await session.cancelProcessing()

        let retryTask = Task {
            await session.retryTranscription(for: recording, in: context)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.observedCallCount() == 1)
        #expect(await engine.observedMaxConcurrentCallCount() == 1)

        await engine.release(call: 0)
        await retryTask.value
        #expect(recording.segments.map(\.text) == ["Newest transcript"])
        await oldTask.value

        #expect(session.state == .completed)
        #expect(recording.rawTranscription == newTranscript)
        #expect(recording.segments.map(\.text) == ["Newest transcript"])
        #expect(!recording.transcriptionNeedsRetry)
        #expect(session.currentProcessingPhase == nil)
        #expect(await engine.observedMaxConcurrentCallCount() == 1)
        #expect(RecordingStatusActivityStore.shared.activity(for: recording) == nil)
    }

    @Test func supersedingAttemptOnDifferentAudioClearsPriorActivityWithoutClearingNewActivity() async throws {
        let (firstContext, firstRecording) = try makeRecording(
            audioFileName: "superseded-first-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        let (secondContext, secondRecording) = try makeRecording(
            audioFileName: "superseded-second-\(UUID().uuidString).caf",
            transcriptionNeedsRetry: true
        )
        defer {
            try? FileManager.default.removeItem(at: firstRecording.audioURL)
            try? FileManager.default.removeItem(at: secondRecording.audioURL)
        }
        let engine = ScriptedTranscriptionEngine([
            .waitForRelease([TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Old")]),
            .waitForRelease([TranscriptionSegment(startMs: 0, endMs: 1_000, text: "New")]),
        ])
        let session = makeSession(engine: engine)

        let firstTask = Task {
            await session.retryTranscription(for: firstRecording, in: firstContext)
        }
        try await waitUntil {
            RecordingStatusActivityStore.shared.activity(for: firstRecording) == .transcribing
        }

        let secondTask = Task {
            await session.retryTranscription(for: secondRecording, in: secondContext)
        }
        try await waitUntil {
            RecordingStatusActivityStore.shared.activity(for: secondRecording) == .transcribing
        }

        #expect(RecordingStatusActivityStore.shared.activity(for: firstRecording) == nil)
        #expect(RecordingStatusActivityStore.shared.activity(for: secondRecording) == .transcribing)

        await session.cancelProcessing()
        await engine.release(call: 0)
        await engine.release(call: 1)
        await firstTask.value
        await secondTask.value

        #expect(RecordingStatusActivityStore.shared.activity(for: firstRecording) == nil)
        #expect(RecordingStatusActivityStore.shared.activity(for: secondRecording) == nil)
    }

    private func makeSession(
        engine: ScriptedTranscriptionEngine,
        verification: @escaping TranscriptionSession.FinalModelVerification = { _ in .ready },
        persistenceSave: @escaping TranscriptionSession.PersistenceSave = { try $0.save() }
    ) -> TranscriptionSession {
        let session = TranscriptionSession(
            transcriber: engine,
            finalModelVerification: verification,
            persistenceSave: persistenceSave,
            diarizationAttemptGuard: DiarizationAttemptGuard()
        )
        session.diarizationInitialTimeout = 0.2
        session.diarizationProgressTimeout = 0.2
        session.diarizationStageTimeouts = .legacy(initialTimeout: 0.2, progressTimeout: 0.2)
        session.diarizationPollInterval = .milliseconds(10)
        return session
    }

    private func makeRecording(
        audioFileName: String,
        transcriptionNeedsRetry: Bool
    ) throws -> (ModelContext, Recording) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let url = AppStoragePaths.recordingsDirectory.appendingPathComponent(audioFileName)
        try writeSilentCAF(to: url)
        let recording = Recording(
            title: "Failure Injection",
            durationSeconds: 1,
            audioFileName: audioFileName,
            segments: [],
            transcriptionNeedsRetry: transcriptionNeedsRetry
        )
        context.insert(recording)
        try context.save()
        return (context, recording)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            if clock.now >= deadline {
                throw FakeTranscriptionError(message: "Timed out waiting for deterministic test state.")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
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
