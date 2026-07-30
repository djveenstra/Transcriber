import Foundation
import OSLog

nonisolated private let diarizationAttemptLogger = Logger(
    subsystem: "com.daniel.transcriber2",
    category: "Diarization"
)

/// Runs one diarization engine call beside the existing watchdog and
/// unsafe-overlap guard. Fallback selection and UI publication remain in
/// `TranscriptionSession`.
protocol DiarizationAttemptCoordinating: Actor {
    func run(
        using diarizer: any DiarizationEngine,
        url: URL,
        initialTimeout: TimeInterval,
        progressTimeout: TimeInterval,
        stageTimeouts: DiarizationStageTimeouts?,
        pollInterval: Duration,
        onAttemptStarted: @escaping @Sendable (UUID) async -> Void,
        onProgress: @escaping @Sendable (UUID, Double) -> Void,
        onStage: @escaping @Sendable (UUID, DiarizationStageSnapshot) -> Void
    ) async -> DiarizationAttemptExecution

    nonisolated func cancelActiveAttempt()
    var hasUnsafeAttempt: Bool { get async }
    func clearForTesting() async
}

struct DiarizationAttemptExecution: Sendable {
    let outcome: DiarizationRaceOutcome
    let timeout: DiarizationTimeoutInfo?
}

actor DiarizationAttemptCoordinator: DiarizationAttemptCoordinating {
    private let attemptGuard: DiarizationAttemptGuard
    nonisolated private let cancellation = DiarizationCancellationHandle()

    init(attemptGuard: DiarizationAttemptGuard = .shared) {
        self.attemptGuard = attemptGuard
    }

    func run(
        using diarizer: any DiarizationEngine,
        url: URL,
        initialTimeout: TimeInterval,
        progressTimeout: TimeInterval,
        stageTimeouts: DiarizationStageTimeouts?,
        pollInterval: Duration,
        onAttemptStarted: @escaping @Sendable (UUID) async -> Void,
        onProgress: @escaping @Sendable (UUID, Double) -> Void,
        onStage: @escaping @Sendable (UUID, DiarizationStageSnapshot) -> Void
    ) async -> DiarizationAttemptExecution {
        let beginResult = await attemptGuard.begin(audioFileName: url.lastPathComponent)
        guard case let .started(attemptID) = beginResult else {
            let message = beginResult.blockedMessage ?? "Speaker labeling cannot start safely yet."
            diarizationAttemptLogger.error("diarization.result.blocked reason=\(message, privacy: .public)")
            return DiarizationAttemptExecution(outcome: .blocked(message), timeout: nil)
        }
        cancellation.prepareForAttempt(attemptID)

        let progressGate = DiarizationProgressGate(
            timeouts: stageTimeouts ?? DiarizationStageTimeouts.legacy(
                initialTimeout: initialTimeout,
                progressTimeout: progressTimeout
            )
        )
        let resultBox = DiarizationAttemptResultBox()
        await onAttemptStarted(attemptID)
        diarizationAttemptLogger.info(
            "diarization.attempt.start id=\(attemptID.uuidString, privacy: .public) file=\(url.lastPathComponent, privacy: .private)"
        )

        let workTask = Task {
            do {
                let result = try await diarizer.diarizeFile(
                    url,
                    progress: { value in
                        Task { await progressGate.reportProgress() }
                        onProgress(attemptID, value)
                    },
                    stage: { event in
                        Task {
                            let snapshot = await progressGate.reportStage(event)
                            onStage(attemptID, snapshot)
                        }
                    }
                )
                await resultBox.complete(.finished(result))
                await attemptGuard.finish(attemptID)
                diarizationAttemptLogger.info(
                    "diarization.result.success id=\(attemptID.uuidString, privacy: .public) segments=\(result.count, privacy: .public)"
                )
            } catch is CancellationError {
                await resultBox.complete(.canceled("Speaker labeling was canceled."))
                await attemptGuard.finish(attemptID)
                diarizationAttemptLogger.info(
                    "diarization.result.canceled id=\(attemptID.uuidString, privacy: .public)"
                )
            } catch {
                let message = error.localizedDescription
                await resultBox.complete(.failed(message))
                await attemptGuard.finish(attemptID)
                diarizationAttemptLogger.error(
                    "diarization.result.failure id=\(attemptID.uuidString, privacy: .public) error=\(message, privacy: .public)"
                )
            }
        }
        cancellation.install(workTask, attemptID: attemptID)

        while true {
            if let outcome = await resultBox.result {
                cancellation.clear(attemptID)
                return DiarizationAttemptExecution(outcome: outcome, timeout: nil)
            }

            try? await Task.sleep(for: pollInterval)

            if let outcome = await resultBox.result {
                cancellation.clear(attemptID)
                return DiarizationAttemptExecution(outcome: outcome, timeout: nil)
            }

            if Task.isCancelled || cancellation.isRequested(for: attemptID) {
                let message = "Speaker labeling was canceled. Your transcript is available and speaker labels can be retried later."
                workTask.cancel()
                cancellation.clear(attemptID)
                await attemptGuard.markAbandoned(attemptID, reason: .canceled)
                diarizationAttemptLogger.info(
                    "diarization.cancel_requested id=\(attemptID.uuidString, privacy: .public)"
                )
                diarizationAttemptLogger.info("diarization.state_cleared reason=cancel")
                return DiarizationAttemptExecution(outcome: .canceled(message), timeout: nil)
            }

            if let timeout = await progressGate.timeoutInfo() {
                let message = Self.timeoutMessage(timeout)
                workTask.cancel()
                cancellation.clear(attemptID)
                await attemptGuard.markAbandoned(attemptID, reason: .timedOut)
                diarizationAttemptLogger.error(
                    "diarization.timeout_fired id=\(attemptID.uuidString, privacy: .public) stage=\(timeout.stage.displayText, privacy: .public) elapsed=\(timeout.elapsed, privacy: .public) limit=\(timeout.limit, privacy: .public)"
                )
                diarizationAttemptLogger.info("diarization.state_cleared reason=timeout")
                diarizationAttemptLogger.info("diarization.retry_state_set reason=timeout guarded=true")
                return DiarizationAttemptExecution(outcome: .timedOut(message), timeout: timeout)
            }
        }
    }

    nonisolated func cancelActiveAttempt() {
        cancellation.cancel()
    }

    var hasUnsafeAttempt: Bool {
        get async {
            await attemptGuard.hasUnsafeAttempt
        }
    }

    func clearForTesting() async {
        await attemptGuard.clearForTesting()
    }

    private static func timeoutMessage(_ timeout: DiarizationTimeoutInfo) -> String {
        let elapsed = DiagnosticsMetricFormatter.formatSeconds(timeout.elapsed)
        let limit = DiagnosticsMetricFormatter.formatSeconds(timeout.limit)
        return "Speaker labeling timed out during \(timeout.stage.displayText.lowercased()) after \(elapsed) (limit \(limit)). The transcript is available, and Transcriber is guarding against an unsafe overlapping retry while the previous speaker-labeling call finishes."
    }
}

nonisolated private final class DiarizationCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptID: UUID?
    private var workTask: Task<Void, Never>?
    private var requested = false

    func prepareForAttempt(_ attemptID: UUID) {
        lock.withLock {
            self.attemptID = attemptID
            requested = false
            workTask = nil
        }
    }

    func install(_ task: Task<Void, Never>, attemptID: UUID) {
        let shouldCancel = lock.withLock {
            guard self.attemptID == attemptID else { return true }
            workTask = task
            return requested
        }
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        let task = lock.withLock {
            requested = true
            return workTask
        }
        task?.cancel()
    }

    func clear(_ attemptID: UUID) {
        lock.withLock {
            guard self.attemptID == attemptID else { return }
            workTask = nil
        }
    }

    func isRequested(for attemptID: UUID) -> Bool {
        lock.withLock {
            self.attemptID == attemptID && requested
        }
    }
}
