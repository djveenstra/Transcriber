import AVFoundation
import Combine
import FluidAudio
import Foundation
import os
import SwiftData
import SwiftUI

private let persistenceLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Persistence")
nonisolated private let diarizationSessionLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Diarization")

enum RecordingInterruptionRecovery {
    static func makeRetryableRecording(
        title: String,
        duration: TimeInterval,
        audioURL: URL,
        finalTranscriptionModelID: String
    ) -> Recording {
        Recording(
            title: title,
            durationSeconds: duration,
            audioFileName: audioURL.lastPathComponent,
            segments: [],
            transcriptionNeedsRetry: true,
            finalTranscriptionModelID: finalTranscriptionModelID
        )
    }

    static func failureMessage(
        reason: RecordingInterruptionReason,
        writeErrorMessage: String?
    ) -> String {
        var message = "Recording stopped because \(reason.displayMessage). Your captured audio was saved and can be transcribed from the Library."
        if let writeErrorMessage {
            message += " The audio file may be incomplete: \(writeErrorMessage)"
        }
        return message
    }

    static func unavailableSaveContextMessage(reason: RecordingInterruptionReason) -> String {
        "Recording stopped because \(reason.displayMessage). The captured audio file remains on disk, but it could not be added to the Library automatically."
    }
}

@MainActor
final class TranscriptionSession: ObservableObject {
    typealias FinalModelVerification = @Sendable (FinalTranscriptionModelChoice) async -> ModelVerificationSnapshot
    typealias PersistenceSave = (ModelContext) throws -> Void

    enum State: Equatable, Sendable {
        case idle
        case preparing
        case recording
        case processing(ProcessingPhase)
        case completed
        case failed(String)
    }

    enum LivePreviewState: Equatable {
        case inactive
        case loading
        case ready
        case unavailable
    }

    enum ModelState: Equatable {
        case notLoaded
        case loading
        case ready(String)
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var livePreviewState: LivePreviewState = .inactive
    @Published private(set) var liveTranscription: [TranscriptionSegment] = []
    @Published private(set) var liveDiarization: [DiarizationSegment] = []
    @Published private(set) var finalSegments: [TranscriptSegment] = []
    @Published private(set) var rawTranscription: [TranscriptionSegment] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var completionNote: String?
    @Published private(set) var modelState: ModelState = .notLoaded
    @Published private(set) var diarizationNeedsRetry = false
    @Published private(set) var isIdentifyingSpeakers = false
    @Published private(set) var livePreviewNote: String?
    @Published private(set) var diarizationFailureDetail: String?
    @Published private(set) var storageErrorMessage: String?
    @Published private(set) var activeMicrophoneName: String?
    @Published private(set) var microphoneFallbackNotice: String?
    @Published private(set) var currentProcessingPhase: ProcessingPhase?
    @Published private(set) var processingStartedAt: Date?
    @Published private(set) var latestDiagnostics: ProcessingDiagnostics?

    let recorder = AudioRecorder()

    private let transcriber: any TranscriptionEngine
    private let finalModelVerification: FinalModelVerification?
    private let finalTranscriptionRunner: any FinalTranscriptionRunning
    private let persistenceCoordinator: any PersistenceCoordinating
    private let processingJobStore: ProcessingJobStore
    private var activeProcessingJob: ProcessingJobRecordV1?
    private var processingJobErrorMessage: String?
#if os(iOS)
    private let liveParakeet = ParakeetEOULiveEngine()
    private var finalParakeet: ParakeetFinalTranscriptionEngine?
#endif
    // Not private: exposed so unit tests can inject a fake `DiarizationEngine`.
    var diarizer: any DiarizationEngine = FluidDiarizationEngine()
    private var audioURL: URL?
    private var saved = false
    private var savedRecording: Recording?
    private var persistenceContext: ModelContext?
    private var livePreparationTask: Task<Void, Never>?
    private var liveAudioFormat: AVAudioFormat?
    private var liveAudioContinuation: AsyncStream<CapturedAudioChunk>.Continuation?
    private var liveConsumerTask: Task<Void, Never>?
    private var processingWasCancelled = false
    private var processingFinalModelChoice: FinalTranscriptionModelChoice?
    private var modelFallbackNote: String?
    private var dismissalNeedsPersistenceRetry = false
    private let statusActivityStore = RecordingStatusActivityStore.shared
    private let diagnosticsStore = ProcessingDiagnosticsStore.shared
    private let diarizationAttemptCoordinator: any DiarizationAttemptCoordinating
    private var activeDiarizationAttemptID: UUID?
    private var activeProcessingAttemptID: UUID?
    var diarizationInitialTimeout: TimeInterval = 120
    var diarizationProgressTimeout: TimeInterval = 30
    var diarizationStageTimeouts: DiarizationStageTimeouts? = .production
    var diarizationPollInterval: Duration = .seconds(5)

    init(
        transcriber: any TranscriptionEngine = WhisperKitTranscriptionEngine(),
        finalModelVerification: FinalModelVerification? = nil,
        persistenceSave: @escaping PersistenceSave = { try $0.save() },
        diarizationAttemptGuard: DiarizationAttemptGuard = .shared,
        finalTranscriptionRunner: any FinalTranscriptionRunning = FinalTranscriptionRunner(),
        diarizationAttemptCoordinator: (any DiarizationAttemptCoordinating)? = nil,
        processingJobStore: ProcessingJobStore? = nil
    ) {
        self.transcriber = transcriber
        self.finalModelVerification = finalModelVerification
        self.finalTranscriptionRunner = finalTranscriptionRunner
        self.persistenceCoordinator = ClosurePersistenceCoordinator(saveContext: persistenceSave)
        self.processingJobStore = processingJobStore
            ?? ProcessingJobStore(applicationSupportRoot: AppStoragePaths.rootDirectory)
        self.diarizationAttemptCoordinator = diarizationAttemptCoordinator
            ?? DiarizationAttemptCoordinator(attemptGuard: diarizationAttemptGuard)
    }

    var liveSegments: [TranscriptSegment] {
        TranscriptMerger.merge(transcription: liveTranscription, diarization: liveDiarization)
    }

    var canCancelProcessing: Bool {
        if isIdentifyingSpeakers { return true }
        if case .processing = state { return true }
        return false
    }

    var requiresCloseConfirmation: Bool {
        if dismissalNeedsPersistenceRetry { return true }
        return Self.requiresCloseConfirmation(for: state, isIdentifyingSpeakers: isIdentifyingSpeakers)
    }

    var needsDismissalSaveRetry: Bool {
        dismissalNeedsPersistenceRetry
    }

    static func requiresCloseConfirmation(
        for state: State,
        isIdentifyingSpeakers: Bool
    ) -> Bool {
        switch state {
        case .preparing, .recording, .processing:
            true
        case .completed:
            isIdentifyingSpeakers
        case .idle, .failed:
            false
        }
    }

    var selectedModelName: String {
        activeFinalModelChoice.name
    }

    var speakerLabelStatusPresentation: SpeakerLabelStatusPresentation {
        SpeakerLabelStatusPresentation.makeForSession(
            isIdentifyingSpeakers: isIdentifyingSpeakers,
            diarizationNeedsRetry: diarizationNeedsRetry,
            completionNote: completionNote,
            speakerCount: Set(finalSegments.map(\.speaker)).count
        )
    }

    var savedRecordingForEditing: Recording? {
        savedRecording
    }

    func prepareSelectedModel() async {
        guard state == .idle, modelState != .loading else { return }
        modelState = .loading
        do {
            try Task.checkCancellation()
            try await prepareSelectedFinalModel()
            modelState = .ready(selectedModelName)
        } catch {
            modelState = .failed
            livePreviewNote = "The selected model could not be prepared: \(error.localizedDescription)"
        }
    }

    func startRecording(in context: ModelContext? = nil) async {
        guard state == .idle || state == .completed else { return }
        state = .preparing
        finalSegments = []
        liveTranscription = []
        liveDiarization = []
        rawTranscription = []
        livePreviewState = .inactive
        completionNote = nil
        livePreviewNote = nil
        diarizationNeedsRetry = false
        isIdentifyingSpeakers = false
        diarizationFailureDetail = nil
        activeMicrophoneName = nil
        microphoneFallbackNotice = nil
        clearProcessingPhase()
        saved = false
        processingWasCancelled = false
        processingFinalModelChoice = nil
        modelFallbackNote = nil
        dismissalNeedsPersistenceRetry = false
        latestDiagnostics = nil
        persistenceContext = context

        guard await recorder.requestPermission() else {
            state = .failed("Microphone permission was denied.")
            return
        }

        do {
            try Task.checkCancellation()
            let microphoneFormat = try recorder.prepareForRecording()
            liveAudioFormat = microphoneFormat
            activeMicrophoneName = recorder.activeMicrophoneName
            microphoneFallbackNotice = recorder.microphoneFallbackNotice
#if os(iOS)
            let liveQueueURL = AppStoragePaths.rootDirectory
                .appendingPathComponent("live-catchup-\(UUID().uuidString).caf")
            try await liveParakeet.begin(audioFormat: microphoneFormat, queueURL: liveQueueURL) { [weak self] segment in
                Task { @MainActor in
                    guard !segment.text.isEmpty else { return }
                    self?.replaceOverlappingLiveSegment(segment)
                }
            }
#else
            await transcriber.beginLive { [weak self] segment in
                Task { @MainActor in
                    guard !segment.text.isEmpty else { return }
                    self?.replaceOverlappingLiveSegment(segment)
                }
            }
#endif

            let url = AppStoragePaths.recordingsDirectory
                .appendingPathComponent("recording-\(UUID().uuidString).caf")
            audioURL = url

            let (stream, continuation) = AsyncStream.makeStream(of: CapturedAudioChunk.self)
            liveAudioContinuation = continuation
            recorder.onBuffer = { chunk in
                continuation.yield(chunk)
            }
            recorder.onSystemEvent = { [weak self] event in
                Task { @MainActor in
                    await self?.handleRecorderSystemEvent(event)
                }
            }
            liveConsumerTask = Task { [weak self] in
                do {
                    for await chunk in stream {
                        guard let self else { break }
#if os(iOS)
                        try await self.liveParakeet.append(chunk)
#else
                        try await self.transcriber.append(chunk)
#endif
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.livePreviewState = .unavailable
                        self?.livePreviewNote = "Live preview paused: \(error.localizedDescription)"
                    }
                }
            }

            try Task.checkCancellation()
            try recorder.start(at: url)
            state = .recording
            livePreviewState = .loading
            startLivePreparation(audioFormat: microphoneFormat)
        } catch is CancellationError {
            recorder.stop()
            recorder.onSystemEvent = nil
            await stopLiveCaptureTasks()
            state = .idle
        } catch {
            recorder.stop()
            recorder.onSystemEvent = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording(in context: ModelContext) async {
        guard state == .recording, let audioURL else { return }
        let attemptID = beginProcessingAttempt()
        defer { finishProcessingAttempt(attemptID) }
        let writeError = recorder.stop()
        recorder.onSystemEvent = nil
        await stopLiveCaptureTasks()
        setProcessingPhase(.savingRecording, progress: 0.01)
        preserveRecording(in: context)
        if let savedRecording {
            await beginProcessingJob(
                for: savedRecording,
                operation: .fullProcessing,
                attemptID: attemptID
            )
        }

        if let writeError {
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording was saved, but the audio file may be incomplete."
            )
            clearProcessingPhase()
            state = .failed("Recording stopped with a write error: \(writeError.localizedDescription). The audio file may be incomplete.")
            return
        }

        setProcessingPhase(.preparingModel, progress: 0.01)
        do {
#if os(iOS)
#else
            try await transcriber.finishLive()
            await transcriber.unload()
            modelState = .loading
            // Give Core ML a moment to fully release the live model before the final
            // transcription pass loads its own model. Without this pause the two
            // back-to-back loads can contend for the same GPU/ANE resources. Do not
            // remove this delay or parallelize model loading.
            try? await Task.sleep(for: .seconds(1))
#endif
            try await processFile(audioURL, attemptID: attemptID)
            guard isCurrentProcessingAttempt(attemptID) else { return }
            updateSavedRecording()
            await finishProcessingJob(state: .partial)
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. Your recording is saved and can be retried from the library.",
                unsavedMessage: "Transcription was canceled.",
                attemptID: attemptID
            )
        } catch {
            guard isCurrentProcessingAttempt(attemptID) else { return }
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript from the library."
            )
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
            await finishProcessingJob(state: .failed)
        }
    }

    func importAudio(_ sourceURL: URL, in context: ModelContext) async {
        let attemptID = beginProcessingAttempt()
        defer { finishProcessingAttempt(attemptID) }
        setProcessingPhase(.savingRecording, progress: 0.01)
        finalSegments = []
        liveTranscription = []
        liveDiarization = []
        rawTranscription = []
        completionNote = nil
        livePreviewNote = nil
        diarizationNeedsRetry = false
        isIdentifyingSpeakers = false
        diarizationFailureDetail = nil
        activeMicrophoneName = nil
        microphoneFallbackNotice = nil
        processingStartedAt = .now
        saved = false
        processingWasCancelled = false
        processingFinalModelChoice = nil
        modelFallbackNote = nil
        dismissalNeedsPersistenceRetry = false
        latestDiagnostics = nil
        persistenceContext = context

        let destination = AppStoragePaths.recordingsDirectory
            .appendingPathComponent("import-\(UUID().uuidString).\(sourceURL.pathExtension)")
        do {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            audioURL = destination
            preserveRecording(
                in: context,
                failureMessage: "Your imported audio was copied, but its Library entry could not be saved yet. Retry saving before closing."
            )
            if let savedRecording {
                await beginProcessingJob(
                    for: savedRecording,
                    operation: .fullProcessing,
                    attemptID: attemptID
                )
            }
            try await processFile(destination, attemptID: attemptID)
            guard isCurrentProcessingAttempt(attemptID) else { return }
            updateSavedRecording()
            await finishProcessingJob(state: .partial)
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. The imported audio remains available for retry.",
                unsavedMessage: "Transcription was canceled. Import the file again when you are ready.",
                attemptID: attemptID
            )
        } catch {
            guard isCurrentProcessingAttempt(attemptID) else { return }
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your imported audio is safe, but its retry status could not be saved."
            )
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
            await finishProcessingJob(state: .failed)
        }
    }

    @discardableResult
    func saveCompletedRecording(in context: ModelContext) -> Recording? {
        guard let audioURL, state == .completed else { return nil }
        persistenceContext = context
        if saved {
            updateSavedRecording()
            return savedRecording
        }
        let title = Date.now.formatted(date: .abbreviated, time: .shortened)
        let recording = Recording(
                title: title,
                durationSeconds: finalSegments.last.map { Double($0.endMs) / 1_000 } ?? recorder.duration,
                audioFileName: audioURL.lastPathComponent,
                segments: finalSegments,
                rawTranscription: rawTranscription,
                transcriptionNeedsRetry: false,
                diarizationNeedsRetry: diarizationNeedsRetry,
                finalTranscriptionModelID: selectedFinalModelID
        )
        context.insert(recording)
        savedRecording = recording
        saved = true
        persistChanges(
            in: context,
            failureMessage: "Your transcript could not be saved. It remains visible here, but it will be lost if you leave this screen."
        )
        return recording
    }

    func retryTranscription(for recording: Recording, in context: ModelContext) async {
        let attemptID = beginProcessingAttempt()
        defer { finishProcessingAttempt(attemptID) }
        audioURL = recording.audioURL
        savedRecording = recording
        persistenceContext = context
        saved = true
        completionNote = nil
        diarizationFailureDetail = nil
        processingWasCancelled = false
        processingFinalModelChoice = nil
        modelFallbackNote = nil
        latestDiagnostics = nil
        clearProcessingPhase()
        await beginProcessingJob(
            for: recording,
            operation: .transcription,
            attemptID: attemptID
        )
        do {
            try await processFile(recording.audioURL, attemptID: attemptID)
            guard isCurrentProcessingAttempt(attemptID) else { return }
            updateSavedRecording()
            await finishProcessingJob(state: .partial)
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. Your recording is saved and can be retried from the library.",
                unsavedMessage: "Transcription was canceled.",
                attemptID: attemptID
            )
        } catch {
            guard isCurrentProcessingAttempt(attemptID) else { return }
            recording.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript again."
            )
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
            await finishProcessingJob(state: .failed)
        }
    }

    func reset() {
        state = .idle
        liveTranscription = []
        liveDiarization = []
        livePreviewState = .inactive
        finalSegments = []
        rawTranscription = []
        progress = 0
        completionNote = nil
        livePreviewNote = nil
        diarizationNeedsRetry = false
        isIdentifyingSpeakers = false
        diarizationFailureDetail = nil
        audioURL = nil
        activeMicrophoneName = nil
        microphoneFallbackNotice = nil
        saved = false
        savedRecording = nil
        persistenceContext = nil
        storageErrorMessage = nil
        processingJobErrorMessage = nil
        processingWasCancelled = false
        processingFinalModelChoice = nil
        modelFallbackNote = nil
        latestDiagnostics = nil
        clearProcessingPhase()
        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveConsumerTask?.cancel()
        liveConsumerTask = nil
        livePreparationTask?.cancel()
        livePreparationTask = nil
        liveAudioFormat = nil
        diarizationAttemptCoordinator.cancelActiveAttempt()
        activeDiarizationAttemptID = nil
        activeProcessingAttemptID = nil
        activeProcessingJob = nil
        recorder.onSystemEvent = nil
    }

    func retryLivePreview() {
        guard state == .recording, let liveAudioFormat else { return }
        livePreparationTask?.cancel()
        livePreviewState = .loading
        livePreviewNote = nil
        startLivePreparation(audioFormat: liveAudioFormat)
    }

    func prepareForDismissal(in context: ModelContext) async -> Bool {
        if dismissalNeedsPersistenceRetry {
            let saved = persistChanges(
                in: context,
                failureMessage: "Your recording is still on disk, but its Library entry could not be saved. Retry before closing."
            )
            dismissalNeedsPersistenceRetry = !saved
            return saved
        }

        // Import cancellation can race this method and move `.processing` to
        // `.failed` first. Preserve any copied, unsaved audio independently of
        // that presentation state so the Library entry cannot be orphaned.
        if !saved, audioURL != nil, state != .recording, state != .preparing {
            preserveRecording(in: context)
            savedRecording?.transcriptionNeedsRetry = true
            let saved = persistChanges(
                in: context,
                failureMessage: "Your imported audio is still on disk, but its Library entry could not be saved. Retry before closing."
            )
            dismissalNeedsPersistenceRetry = !saved
        }

        switch state {
        case .recording:
            let writeError = recorder.stop()
            recorder.onSystemEvent = nil
            await stopLiveCaptureTasks()
            preserveRecording(in: context)
            savedRecording?.transcriptionNeedsRetry = true
            let saved = persistChanges(
                in: context,
                failureMessage: "Your recording was captured, but its retry status could not be saved."
            )
            dismissalNeedsPersistenceRetry = !saved
            if let writeError {
                storageErrorMessage = "The recording was saved for retry, but the audio file may be incomplete: \(writeError.localizedDescription)"
            }
#if os(macOS)
            await transcriber.unload()
            modelState = .notLoaded
#endif
            state = .idle
        case .processing:
            await cancelProcessing()
        case .completed where isIdentifyingSpeakers:
            await cancelProcessing()
        case .preparing:
            recorder.stop()
            recorder.onSystemEvent = nil
            await stopLiveCaptureTasks()
            state = .idle
        case .idle, .completed, .failed:
            break
        }
        return !dismissalNeedsPersistenceRetry && storageErrorMessage == nil
    }

    func retrySpeakerLabels(for recording: Recording, in context: ModelContext) async {
        guard !recording.rawTranscription.isEmpty else {
            state = .failed("This older transcript does not contain the timing data needed to retry speaker labels.")
            return
        }
        let attemptID = beginProcessingAttempt()
        defer {
            if isCurrentProcessingAttempt(attemptID) {
                statusActivityStore.clear(audioFileName: recording.audioFileName)
            }
            finishProcessingAttempt(attemptID)
        }
        statusActivityStore.set(.speakerLabeling, forAudioFileName: recording.audioFileName)
        guard !Task.isCancelled else { return }
        persistenceContext = context
        processingWasCancelled = false
        audioURL = recording.audioURL
        rawTranscription = recording.rawTranscription
        finalSegments = recording.segments
        await beginProcessingJob(
            for: recording,
            operation: .speakerLabels,
            attemptID: attemptID
        )
        beginDiagnostics(
            for: recording.audioURL,
            model: recording.finalTranscriptionModelID.isEmpty
                ? nil
                : FinalTranscriptionModelChoice.choice(for: recording.finalTranscriptionModelID),
            speakerLabelStatus: .identifying
        )
        setProcessingPhase(.identifyingSpeakers, progress: 0.65)
        let diarizationStarted = Date()
        if let outcome = await runDiarizationWithFallback(
            recording.audioURL,
            processingAttemptID: attemptID,
            initialTimeout: diarizationInitialTimeout,
            progressTimeout: diarizationProgressTimeout,
            stageTimeouts: diarizationStageTimeouts,
            pollInterval: diarizationPollInterval
        ) {
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            guard isCurrentProcessingAttempt(attemptID), !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled.",
                    attemptID: attemptID
                )
                return
            }
            let merged = TranscriptMerger.merge(transcription: recording.rawTranscription, diarization: outcome.segments)
            recording.segments = merged
            recording.diarizationNeedsRetry = false
            finalSegments = merged
            completionNote = outcome.isApproximate ? approximateSpeakerLabelNote() : nil
            diarizationNeedsRetry = false
            updateDiagnostics(
                diarizationTime: diarizationTime,
                diarizationFallbackUsed: outcome.isApproximate,
                speakerLabelStatus: outcome.isApproximate ? .approximate : .complete
            )
            progress = 1
            clearProcessingPhase()
            diarizationSessionLogger.info("diarization.result.success state=complete")
            state = .completed
            persistChanges(
                in: context,
                failureMessage: "The updated speaker labels could not be saved. They remain visible here, but it will be lost if you leave this screen."
            )
            await finishProcessingJob(state: .partial)
        } else {
            guard isCurrentProcessingAttempt(attemptID), !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled.",
                    attemptID: attemptID
                )
                return
            }
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            completionNote = speakerLabelFailureMessage(saved: true)
            recording.diarizationNeedsRetry = true
            diarizationNeedsRetry = true
            diarizationSessionLogger.info("diarization.retry_state_set reason=failure")
            updateDiagnostics(
                diarizationTime: diarizationTime,
                diarizationFallbackUsed: false,
                speakerLabelStatus: .retryNeeded,
                failureMessage: completionNote
            )
            progress = 1
            clearProcessingPhase()
            state = .completed
            persistChanges(
                in: context,
                failureMessage: "Speaker labels still need retry, but that status could not be saved."
            )
            await finishProcessingJob(state: .partial)
        }
    }

    func retryCurrentSpeakerLabels() async {
        guard let audioURL, !rawTranscription.isEmpty, !Task.isCancelled else { return }
        let attemptID = beginProcessingAttempt()
        defer { finishProcessingAttempt(attemptID) }
        if latestDiagnostics == nil {
            beginDiagnostics(
                for: audioURL,
                model: activeFinalModelChoice,
                speakerLabelStatus: .identifying
            )
        } else {
            updateDiagnostics(speakerLabelStatus: .identifying)
        }
        setProcessingPhase(.identifyingSpeakers, progress: 0.6)
        let diarizationStarted = Date()
        if let outcome = await runDiarizationWithFallback(
            audioURL,
            processingAttemptID: attemptID,
            initialTimeout: diarizationInitialTimeout,
            progressTimeout: diarizationProgressTimeout,
            stageTimeouts: diarizationStageTimeouts,
            pollInterval: diarizationPollInterval
        ) {
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            guard isCurrentProcessingAttempt(attemptID), !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled. You can retry speaker labels later.",
                    attemptID: attemptID
                )
                return
            }
            finalSegments = TranscriptMerger.merge(transcription: rawTranscription, diarization: outcome.segments)
            completionNote = outcome.isApproximate ? approximateSpeakerLabelNote() : nil
            diarizationNeedsRetry = false
            updateDiagnostics(
                diarizationTime: diarizationTime,
                diarizationFallbackUsed: outcome.isApproximate,
                speakerLabelStatus: outcome.isApproximate ? .approximate : .complete
            )
        } else {
            guard isCurrentProcessingAttempt(attemptID), !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled. You can retry speaker labels later.",
                    attemptID: attemptID
                )
                return
            }
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            completionNote = speakerLabelFailureMessage(saved: false)
            diarizationNeedsRetry = true
            updateDiagnostics(
                diarizationTime: diarizationTime,
                diarizationFallbackUsed: false,
                speakerLabelStatus: .retryNeeded,
                failureMessage: completionNote
            )
        }
        savedRecording?.segments = finalSegments
        savedRecording?.diarizationNeedsRetry = diarizationNeedsRetry
        progress = 1
        clearProcessingPhase()
        if diarizationNeedsRetry {
            diarizationSessionLogger.info("diarization.retry_state_set reason=failure")
        } else {
            diarizationSessionLogger.info("diarization.result.success state=complete")
        }
        state = .completed
    }

    func cancelProcessing() async {
        guard canCancelProcessing else { return }
        diarizationSessionLogger.info("diarization.cancel_requested")
        await checkpointProcessingJob(
            stage: activeProcessingJob?.stage ?? .queued,
            state: .cancelRequested
        )
        activeProcessingAttemptID = nil
        processingWasCancelled = true
        if let audioURL {
            statusActivityStore.clear(audioFileName: audioURL.lastPathComponent)
        }
        diarizationAttemptCoordinator.cancelActiveAttempt()
        livePreparationTask?.cancel()
        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveConsumerTask?.cancel()
        await liveConsumerTask?.value
        liveConsumerTask = nil
        livePreparationTask = nil
#if os(iOS)
        await liveParakeet.finish()
        await unloadSelectedFinalModel()
#else
        await transcriber.unload()
        modelState = .notLoaded
#endif
        guard activeProcessingAttemptID == nil else { return }
        await handleProcessingCancellation(
            savedMessage: "Processing was canceled. Your recording is saved and can be retried from the library.",
            unsavedMessage: "Processing was canceled."
        )
    }

    private func beginDiagnostics(
        for url: URL,
        model: FinalTranscriptionModelChoice? = nil,
        speakerLabelStatus: SpeakerLabelDiagnosticStatus = .notStarted
    ) {
        var diagnostics = ProcessingDiagnostics(
            audioFileName: url.lastPathComponent,
            finalTranscriptionModelID: model?.id,
            finalTranscriptionModelName: model?.name,
            audioDuration: ProcessingDiagnostics.measuredAudioDuration(for: url),
            speakerLabelStatus: speakerLabelStatus
        )
        if diagnostics.audioDuration == nil, let savedRecording, savedRecording.audioFileName == url.lastPathComponent {
            diagnostics.audioDuration = savedRecording.durationSeconds
        }
        publishDiagnostics(diagnostics)
    }

    private func updateDiagnostics(
        model: FinalTranscriptionModelChoice? = nil,
        modelLoadTime: TimeInterval? = nil,
        transcriptionTime: TimeInterval? = nil,
        diarizationTime: TimeInterval? = nil,
        transcriptionFallbackUsed: Bool? = nil,
        diarizationFallbackUsed: Bool? = nil,
        speakerLabelStatus: SpeakerLabelDiagnosticStatus? = nil,
        failureMessage: String? = nil,
        diarizationCurrentStage: DiarizationDiagnosticStage? = nil,
        diarizationCurrentStageElapsed: TimeInterval? = nil,
        diarizationTimedOutStage: DiarizationDiagnosticStage? = nil,
        diarizationTimedOutAfter: TimeInterval? = nil,
        diarizationStageTimings: [DiarizationStageTiming]? = nil
    ) {
        var diagnostics = latestDiagnostics ?? ProcessingDiagnostics(audioFileName: audioURL?.lastPathComponent)
        if let model {
            diagnostics.finalTranscriptionModelID = model.id
            diagnostics.finalTranscriptionModelName = model.name
        }
        if let modelLoadTime {
            diagnostics.modelLoadTime = modelLoadTime
        }
        if let transcriptionTime {
            diagnostics.transcriptionTime = transcriptionTime
        }
        if let diarizationTime {
            diagnostics.diarizationTime = diarizationTime
        }
        if let transcriptionFallbackUsed {
            diagnostics.transcriptionFallbackUsed = transcriptionFallbackUsed
        }
        if let diarizationFallbackUsed {
            diagnostics.diarizationFallbackUsed = diarizationFallbackUsed
        }
        if let speakerLabelStatus {
            diagnostics.speakerLabelStatus = speakerLabelStatus
        }
        if let failureMessage {
            diagnostics.failureMessage = failureMessage
        }
        if let diarizationCurrentStage {
            diagnostics.diarizationCurrentStage = diarizationCurrentStage
            diagnostics.diarizationCurrentStageElapsed = diarizationCurrentStageElapsed
        }
        if let diarizationTimedOutStage {
            diagnostics.diarizationTimedOutStage = diarizationTimedOutStage
            diagnostics.diarizationTimedOutAfter = diarizationTimedOutAfter
        }
        if let diarizationStageTimings {
            diagnostics.diarizationStageTimings = diarizationStageTimings
        }
        publishDiagnostics(diagnostics)
    }

    private func recordDiarizationStage(_ snapshot: DiarizationStageSnapshot) {
        updateDiagnostics(
            diarizationCurrentStage: snapshot.currentStage,
            diarizationCurrentStageElapsed: snapshot.currentStageElapsed,
            diarizationStageTimings: snapshot.completedTimings
        )
    }

    private func recordDiagnosticsFailure(_ message: String) {
        updateDiagnostics(failureMessage: message)
    }

    private func publishDiagnostics(_ diagnostics: ProcessingDiagnostics) {
        latestDiagnostics = diagnostics
        diagnosticsStore.record(diagnostics)
    }

    private func setProcessingPhase(
        _ phase: ProcessingPhase,
        progress: Double? = nil,
        updateState: Bool = true
    ) {
        if currentProcessingPhase == nil || processingStartedAt == nil {
            processingStartedAt = .now
        }
        currentProcessingPhase = phase
        if let progress {
            self.progress = min(max(progress, 0), 1)
        }
        if updateState {
            state = .processing(phase)
        }
    }

    private func clearProcessingPhase() {
        currentProcessingPhase = nil
        processingStartedAt = nil
    }

    private func processFile(_ url: URL, attemptID: UUID) async throws {
        statusActivityStore.set(.transcribing, forAudioFileName: url.lastPathComponent)
        defer {
            if isCurrentProcessingAttempt(attemptID) {
                statusActivityStore.clear(audioFileName: url.lastPathComponent)
            }
        }
        processingWasCancelled = false
        beginDiagnostics(for: url)
        do {
            try requireCurrentProcessingAttempt(attemptID)
            try Task.checkCancellation()
            setProcessingPhase(.preparingModel, progress: 0.02)
            await checkpointProcessingJob(stage: .preparingModel, state: .running)
            modelState = .loading
            let modelLoadStarted = Date()
            try await verifySelectedFinalModelBeforeProcessing()
            try requireCurrentProcessingAttempt(attemptID)
            updateDiagnostics(
                model: activeFinalModelChoice,
                modelLoadTime: Date().timeIntervalSince(modelLoadStarted),
                transcriptionFallbackUsed: modelFallbackNote != nil
            )
            let transcriptionStarted = Date()
            await checkpointProcessingJob(stage: .transcribing, state: .running)
            let transcription = try await transcribeSelectedFinalModel(url) { [weak self] value in
                Task { @MainActor in
                    guard self?.isCurrentProcessingAttempt(attemptID) == true else { return }
                    self?.setProcessingPhase(
                        .transcribing,
                        progress: 0.05 + min(max(value, 0), 1) * 0.55
                    )
                }
            }
            try requireCurrentProcessingAttempt(attemptID)
            updateDiagnostics(
                transcriptionTime: Date().timeIntervalSince(transcriptionStarted),
                speakerLabelStatus: .notStarted
            )
            modelState = .ready(activeFinalModelChoice.name)
            try Task.checkCancellation()
            rawTranscription = transcription
            savedRecording?.rawTranscription = transcription
            savedRecording?.transcriptionNeedsRetry = false
            savedRecording?.finalTranscriptionModelID = selectedFinalModelID

            try Task.checkCancellation()

            // Preserve the finished text before speaker labeling begins.
            setProcessingPhase(.savingTranscript, progress: 0.58)
            await checkpointProcessingJob(stage: .savingTranscript, state: .running)
            finalSegments = TranscriptMerger.merge(transcription: transcription, diarization: [])
            savedRecording?.segments = finalSegments
            if let persistenceContext {
                persistChanges(
                    in: persistenceContext,
                    failureMessage: "Your transcript finished but could not be saved yet. It remains visible here, but it will be lost if you leave this screen."
                )
            }
            progress = 0.6
#if os(iOS)
            isIdentifyingSpeakers = true
            setProcessingPhase(.identifyingSpeakers, progress: 0.6, updateState: false)
            state = .completed
#else
            setProcessingPhase(.identifyingSpeakers, progress: 0.6)
#endif
            await checkpointProcessingJob(stage: .identifyingSpeakers, state: .running)
            updateDiagnostics(speakerLabelStatus: .identifying)
            statusActivityStore.set(.speakerLabeling, forAudioFileName: url.lastPathComponent)
#if os(macOS)
            await transcriber.unload()
            modelState = .notLoaded
            // Give Core ML a moment to fully release the transcription model before the
            // diarization model loads. Without this pause the two back-to-back loads can
            // contend for the same GPU/ANE resources. Do not remove this delay or
            // parallelize model loading.
            try? await Task.sleep(for: .seconds(1))
#else
            await unloadSelectedFinalModel()
#endif

            try Task.checkCancellation()
            guard !processingWasCancelled else { throw CancellationError() }
            let diarizationStarted = Date()
            let outcome = await runDiarizationWithFallback(
                url,
                processingAttemptID: attemptID,
                initialTimeout: diarizationInitialTimeout,
                progressTimeout: diarizationProgressTimeout,
                stageTimeouts: diarizationStageTimeouts,
                pollInterval: diarizationPollInterval
            )
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            try requireCurrentProcessingAttempt(attemptID)
            try Task.checkCancellation()
            if let outcome {
                finalSegments = TranscriptMerger.merge(
                    transcription: transcription,
                    diarization: outcome.segments
                )
                diarizationNeedsRetry = false
                completionNote = combinedCompletionNote(outcome.isApproximate ? approximateSpeakerLabelNote() : nil)
                updateDiagnostics(
                    diarizationTime: diarizationTime,
                    diarizationFallbackUsed: outcome.isApproximate,
                    speakerLabelStatus: outcome.isApproximate ? .approximate : .complete
                )
            } else {
                let failureMessage = speakerLabelFailureMessage(saved: false)
                completionNote = combinedCompletionNote(failureMessage)
                diarizationNeedsRetry = true
                diarizationSessionLogger.info("diarization.retry_state_set reason=failure")
                updateDiagnostics(
                    diarizationTime: diarizationTime,
                    diarizationFallbackUsed: false,
                    speakerLabelStatus: .retryNeeded,
                    failureMessage: failureMessage
                )
            }
#if os(iOS)
            isIdentifyingSpeakers = false
#else
#endif
            setProcessingPhase(.savingSpeakerLabels, progress: 0.98, updateState: !isIdentifyingSpeakers)
            await checkpointProcessingJob(stage: .savingSpeakerLabels, state: .running)
            progress = 1
            clearProcessingPhase()
            diarizationSessionLogger.info("diarization.state_cleared reason=finished")
            state = .completed
        } catch {
            if isCurrentProcessingAttempt(attemptID) {
                recordDiagnosticsFailure(error.localizedDescription)
            }
            throw error
        }
    }

    private func handleProcessingCancellation(
        savedMessage: String,
        unsavedMessage: String,
        attemptID: UUID? = nil
    ) async {
        if let attemptID, !isCurrentProcessingAttempt(attemptID) {
            return
        }
        isIdentifyingSpeakers = false
        progress = 0
        activeDiarizationAttemptID = nil
        clearProcessingPhase()
        if let audioURL {
            statusActivityStore.clear(audioFileName: audioURL.lastPathComponent)
        }
        diarizationSessionLogger.info("diarization.state_cleared reason=cancel")
        livePreviewState = .inactive
        if !rawTranscription.isEmpty {
            diarizationSessionLogger.info("diarization.retry_state_set reason=cancel")
            updateDiagnostics(
                speakerLabelStatus: .canceled,
                failureMessage: "Speaker labeling was canceled. Your transcript is available and speaker labels can be retried later."
            )
            if finalSegments.isEmpty {
                finalSegments = TranscriptMerger.merge(transcription: rawTranscription, diarization: [])
            }
            diarizationNeedsRetry = true
            completionNote = combinedCompletionNote(
                "Speaker labeling was canceled. Your transcript is available and speaker labels can be retried later."
            )
            savedRecording?.segments = finalSegments
            savedRecording?.rawTranscription = rawTranscription
            savedRecording?.transcriptionNeedsRetry = false
            savedRecording?.diarizationNeedsRetry = true
            state = .completed
            if let persistenceContext {
                persistChanges(
                    in: persistenceContext,
                    failureMessage: "Your transcript is visible here, but the cancellation status could not be saved."
                )
            }
            await finishProcessingJob(state: .partial)
        } else if saved {
            updateDiagnostics(
                speakerLabelStatus: .notAvailable,
                failureMessage: savedMessage
            )
            savedRecording?.transcriptionNeedsRetry = true
            state = .failed(savedMessage)
            if let persistenceContext {
                persistChanges(
                    in: persistenceContext,
                    failureMessage: "Your recording is saved, but the retry status could not be updated."
                )
            }
            await finishProcessingJob(state: .failed)
        } else {
            updateDiagnostics(
                speakerLabelStatus: .notAvailable,
                failureMessage: unsavedMessage
            )
            state = .failed(unsavedMessage)
            await finishProcessingJob(state: .failed)
        }
    }

    private func handleRecorderSystemEvent(_ event: AudioRecorderSystemEvent) async {
        switch event {
        case let .routeChanged(activeMicrophoneName, notice):
            guard state == .recording else { return }
            self.activeMicrophoneName = activeMicrophoneName
            microphoneFallbackNotice = notice
        case let .stoppedBySystem(reason, writeErrorMessage):
            await handleSystemStoppedRecording(
                reason: reason,
                writeErrorMessage: writeErrorMessage
            )
        }
    }

    private func handleSystemStoppedRecording(
        reason: RecordingInterruptionReason,
        writeErrorMessage: String?
    ) async {
        guard state == .recording, audioURL != nil else { return }
        recorder.onSystemEvent = nil
        await stopLiveCaptureTasks()

        guard let persistenceContext else {
            state = .failed(RecordingInterruptionRecovery.unavailableSaveContextMessage(reason: reason))
            return
        }

        preserveRecording(in: persistenceContext)
        savedRecording?.transcriptionNeedsRetry = true
        persistChanges(
            in: persistenceContext,
            failureMessage: "Your recording was captured, but the retry status could not be saved."
        )
        state = .failed(RecordingInterruptionRecovery.failureMessage(
            reason: reason,
            writeErrorMessage: writeErrorMessage
        ))
    }

    private func stopLiveCaptureTasks() async {
        livePreparationTask?.cancel()
        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveConsumerTask?.cancel()
        await liveConsumerTask?.value
        liveConsumerTask = nil
        livePreparationTask = nil
        liveAudioFormat = nil
#if os(iOS)
        await liveParakeet.finish()
#endif
    }

    private func startLivePreparation(audioFormat: AVAudioFormat) {
        livePreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
#if os(iOS)
                try await self.liveParakeet.prepare()
                guard !Task.isCancelled, self.state == .recording else { return }
                self.livePreviewState = .ready
#else
                await LaunchModelReadiness.shared.waitForLivePreviewAttempt()
                try Task.checkCancellation()
                try await self.transcriber.prepareLive(audioFormat: audioFormat)
                guard !Task.isCancelled, self.state == .recording else { return }
                self.livePreviewState = .ready
                let loaded = await self.transcriber.currentLoadedModelID()
                self.modelState = .ready(WhisperModelChoice.choice(for: loaded ?? "").name)
#endif
            } catch {
                guard !Task.isCancelled, self.state == .recording else { return }
                self.livePreviewState = .unavailable
                self.livePreviewNote = "Live preview could not finish preparing: \(error.localizedDescription)"
            }
        }
    }

    private func preserveRecording(
        in context: ModelContext,
        failureMessage: String = "Your recording could not be saved yet. Transcription will continue and we'll try saving it again once it finishes."
    ) {
        guard !saved, let audioURL else { return }
        persistenceContext = context
        let recording = RecordingInterruptionRecovery.makeRetryableRecording(
            title: Date.now.formatted(date: .abbreviated, time: .shortened),
            duration: ProcessingDiagnostics.measuredAudioDuration(for: audioURL) ?? recorder.duration,
            audioURL: audioURL,
            finalTranscriptionModelID: selectedFinalModelID
        )
        context.insert(recording)
        savedRecording = recording
        saved = true
        // If this fails, processing continues and later saves (in
        // updateSavedRecording/processFile) retry persisting this same recording.
        persistChanges(
            in: context,
            failureMessage: failureMessage
        )
    }

    func dismissStorageError() {
        storageErrorMessage = nil
        processingJobErrorMessage = nil
    }

    /// Saves the context, surfacing failures via `storageErrorMessage` instead of
    /// silently discarding them. `failureMessage` should tell the user what remains
    /// safe (e.g. "still visible here") so they know whether to wait or take action.
    @discardableResult
    private func persistChanges(in context: ModelContext, failureMessage: String) -> Bool {
        do {
            try persistenceCoordinator.save(context)
            storageErrorMessage = processingJobErrorMessage
            return true
        } catch {
            persistenceLogger.error("Failed to save model context: \(error.localizedDescription, privacy: .public)")
            storageErrorMessage = failureMessage
            return false
        }
    }

    private func beginProcessingJob(
        for recording: Recording,
        operation: ProcessingJobOperation,
        attemptID: UUID
    ) async {
        guard let context = persistenceContext,
              let durableAttemptID = try? ArtifactStoreID(
                rawValue: attemptID.uuidString.lowercased()
              ) else {
            activeProcessingJob = nil
            return
        }
        do {
            let identity = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
                try persistenceCoordinator.save(context)
            } reload: {
                let freshContext = ModelContext(context.container)
                guard let reloaded = freshContext.model(
                    for: recording.persistentModelID
                ) as? Recording else {
                    return (nil, nil)
                }
                return (reloaded.processingRecordID, reloaded.sourceAudioID)
            }
            let now = Date.now
            let job = ProcessingJobRecordV1(
                jobSchemaVersion: ProcessingJobRecordV1.schemaVersion,
                jobID: ArtifactStoreID(),
                pipelineRunID: ArtifactStoreID(),
                attemptID: durableAttemptID,
                recordingID: identity.recordingID,
                sourceAudioID: identity.sourceAudioID,
                requestedOperation: operation,
                inputManifestGeneration: nil,
                inputCorrectionVersion: nil,
                stage: .queued,
                state: .queued,
                createdAt: now,
                updatedAt: now,
                startedAt: nil,
                finishedAt: nil,
                publishedOutputReferences: []
            )
            activeProcessingJob = try await processingJobStore.start(
                job,
                stage: .savingRecording
            )
        } catch {
            activeProcessingJob = nil
            recordProcessingJobFailure(error)
            persistenceLogger.error(
                "Processing job was not started: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @discardableResult
    private func checkpointProcessingJob(
        stage: ProcessingJobStage,
        state: ProcessingJobState
    ) async -> Bool {
        guard let activeProcessingJob else { return false }
        do {
            self.activeProcessingJob = try await processingJobStore.checkpoint(
                jobID: activeProcessingJob.jobID,
                recordingID: activeProcessingJob.recordingID,
                expectedAttemptID: activeProcessingJob.attemptID,
                expectedInputManifestGeneration: activeProcessingJob.inputManifestGeneration,
                expectedCorrectionVersion: activeProcessingJob.inputCorrectionVersion,
                stage: stage,
                state: state
            )
            return true
        } catch {
            recordProcessingJobFailure(error)
            persistenceLogger.error(
                "Processing job checkpoint failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func finishProcessingJob(state: ProcessingJobState) async {
        guard activeProcessingJob != nil else { return }
        if await checkpointProcessingJob(stage: .finished, state: state) {
            self.activeProcessingJob = nil
            return
        }
        if await checkpointProcessingJob(
            stage: activeProcessingJob?.stage ?? .finished,
            state: .interrupted
        ) {
            if let activeProcessingJob, let savedRecording {
                ProcessingJobCompatibilityProjection.apply(
                    activeProcessingJob,
                    to: savedRecording
                )
            }
            self.activeProcessingJob = nil
        }
    }

    private func recordProcessingJobFailure(_: Error) {
        let message =
            "Processing status could not be saved. Your audio and last transcript remain safe; reopen the app before retrying processing."
        processingJobErrorMessage = message
        storageErrorMessage = message
    }

    private func updateSavedRecording() {
        savedRecording?.segments = finalSegments
        savedRecording?.rawTranscription = rawTranscription
        savedRecording?.transcriptionNeedsRetry = state != .completed
        savedRecording?.diarizationNeedsRetry = diarizationNeedsRetry
        savedRecording?.finalTranscriptionModelID = selectedFinalModelID
        guard let persistenceContext else { return }
        persistChanges(
            in: persistenceContext,
            failureMessage: "Your transcript could not be saved. It remains visible here, but it will be lost if you leave this screen."
        )
    }

    private var selectedFinalModelID: String {
        activeFinalModelChoice.id
    }

    private var activeFinalModelChoice: FinalTranscriptionModelChoice {
        processingFinalModelChoice ?? userSelectedFinalModelChoice
    }

    private var userSelectedFinalModelChoice: FinalTranscriptionModelChoice {
#if os(iOS)
        FinalTranscriptionModelChoice.choice(for: FinalTranscriptionModelChoice.selectedID())
#else
        let id = WhisperModelChoice.allowedID(UserDefaults.standard.string(forKey: "whisperModel"))
        return FinalTranscriptionModelChoice.choice(for: id)
#endif
    }

    private func prepareSelectedFinalModel() async throws {
#if os(iOS)
        let choice = userSelectedFinalModelChoice
        switch choice.provider {
        case .whisper:
            UserDefaults.standard.set(choice.id, forKey: "whisperModel")
            try await transcriber.prepare()
        case .parakeet:
            let engine = ParakeetFinalTranscriptionEngine(model: choice)
            finalParakeet = engine
            try await engine.prepare()
        }
#else
        try await transcriber.prepare()
#endif
    }

    private func verifySelectedFinalModelBeforeProcessing() async throws {
        let selected = userSelectedFinalModelChoice
        let fallback = FinalTranscriptionModelChoice.choice(for: FinalTranscriptionModelChoice.defaultID)
        let result = try await FinalModelPreflight.resolveModel(
            selected: selected,
            fallback: fallback
        ) { [weak self] model in
            guard let self else { return .failed("The transcription session ended before the model could be checked.") }
            if let finalModelVerification = self.finalModelVerification {
                return await finalModelVerification(model)
            }
            return await self.verifyFinalModelLoadability(
                model,
                allowDownload: model.id == fallback.id
            )
        }
        processingFinalModelChoice = result.choice
        modelFallbackNote = result.notice
        completionNote = result.notice
        modelState = .ready(result.choice.name)
    }

    private func verifyFinalModelLoadability(
        _ choice: FinalTranscriptionModelChoice,
        allowDownload: Bool
    ) async -> ModelVerificationSnapshot {
        let descriptor = ModelRegistry.descriptor(for: choice)
        let file = ModelRegistry.fileSnapshot(for: descriptor, includeSize: false)
        if !file.isPresent {
            guard allowDownload else { return .missingOrCorrupt }
            await FinalModelDownloader.shared.download(choice)
            let refreshed = ModelRegistry.fileSnapshot(for: descriptor, includeSize: false)
            guard refreshed.isPresent else { return .missingOrCorrupt }
        }

        do {
            try await loadFinalModel(choice)
            ModelRegistry.rememberDownloaded(choice.id)
            return .ready
        } catch {
            await unloadFinalModel(choice)
            return .failed(error.localizedDescription)
        }
    }

    private func loadFinalModel(_ choice: FinalTranscriptionModelChoice) async throws {
#if os(iOS)
        switch choice.provider {
        case .whisper:
            UserDefaults.standard.set(choice.id, forKey: "whisperModel")
            try await transcriber.prepare()
        case .parakeet:
            let engine = ParakeetFinalTranscriptionEngine(model: choice)
            try await engine.prepare()
            finalParakeet = engine
        }
#else
        UserDefaults.standard.set(choice.id, forKey: "whisperModel")
        try await transcriber.prepare()
#endif
    }

    private func unloadFinalModel(_ choice: FinalTranscriptionModelChoice) async {
#if os(iOS)
        switch choice.provider {
        case .whisper:
            await transcriber.unload()
        case .parakeet:
            await finalParakeet?.unload()
            finalParakeet = nil
        }
#else
        await transcriber.unload()
#endif
    }

    private func transcribeSelectedFinalModel(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
#if os(iOS)
        let choice = activeFinalModelChoice
        switch choice.provider {
        case .whisper:
            UserDefaults.standard.set(choice.id, forKey: "whisperModel")
            return try await finalTranscriptionRunner.transcribe(
                using: transcriber,
                audioURL: url,
                progress: progress
            )
        case .parakeet:
            let engine = finalParakeet ?? ParakeetFinalTranscriptionEngine(model: choice)
            finalParakeet = engine
            return try await engine.transcribeFile(url, progress: progress)
        }
#else
        UserDefaults.standard.set(activeFinalModelChoice.id, forKey: "whisperModel")
        return try await finalTranscriptionRunner.transcribe(
            using: transcriber,
            audioURL: url,
            progress: progress
        )
#endif
    }

    private func unloadSelectedFinalModel() async {
#if os(iOS)
        await transcriber.unload()
        await finalParakeet?.unload()
        finalParakeet = nil
        modelState = .notLoaded
#endif
    }

    private func beginProcessingAttempt() -> UUID {
        if activeProcessingAttemptID != nil, let audioURL {
            statusActivityStore.clear(audioFileName: audioURL.lastPathComponent)
        }
        let attemptID = UUID()
        activeProcessingAttemptID = attemptID
        processingWasCancelled = false
        return attemptID
    }

    private func finishProcessingAttempt(_ attemptID: UUID) {
        guard activeProcessingAttemptID == attemptID else { return }
        activeProcessingAttemptID = nil
    }

    private func isCurrentProcessingAttempt(_ attemptID: UUID) -> Bool {
        activeProcessingAttemptID == attemptID && !processingWasCancelled
    }

    private func requireCurrentProcessingAttempt(_ attemptID: UUID) throws {
        guard isCurrentProcessingAttempt(attemptID) else {
            throw CancellationError()
        }
    }

    /// Runs diarization with Balanced V2, automatically retrying once with the faster
    /// (less accurate) Fast V2 config only after a normal failure. A timeout/cancel
    /// can mean FluidAudio/Core ML is still running underneath, so starting fallback
    /// immediately would create the unsafe overlap this objective is guarding.
    ///
    /// The timeout/poll parameters and `fallbackEngine` default to production values
    /// and are only overridden by tests to keep the watchdog race fast and deterministic.
    func runDiarizationWithFallback(
        _ url: URL,
        processingAttemptID: UUID? = nil,
        initialTimeout: TimeInterval = 120,
        progressTimeout: TimeInterval = 30,
        stageTimeouts: DiarizationStageTimeouts? = nil,
        pollInterval: Duration = .seconds(5),
        fallbackEngine: any DiarizationEngine = FluidDiarizationEngine(config: .fastV2)
    ) async -> DiarizationAttemptOutcome? {
        diarizationFailureDetail = nil
        let primaryOutcome = await diarizeWithWatchdog(
            using: diarizer,
            url: url,
            initialTimeout: initialTimeout,
            progressTimeout: progressTimeout,
            stageTimeouts: stageTimeouts,
            pollInterval: pollInterval
        )
        if case let .finished(segments) = primaryOutcome {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            if canPublishProcessingResult(processingAttemptID) {
                updateDiagnostics(
                    diarizationFallbackUsed: false,
                    speakerLabelStatus: .complete
                )
            }
            return DiarizationAttemptOutcome(segments: segments, isApproximate: false)
        }
        if primaryOutcome.preventsFallback {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            if canPublishProcessingResult(processingAttemptID) {
                updateDiagnostics(
                    diarizationFallbackUsed: false,
                    speakerLabelStatus: .retryNeeded,
                    failureMessage: diarizationFailureDetail
                )
            }
            return nil
        }

        diarizationFailureDetail = nil
        let fallbackOutcome = await diarizeWithWatchdog(
            using: fallbackEngine,
            url: url,
            initialTimeout: initialTimeout,
            progressTimeout: progressTimeout,
            stageTimeouts: stageTimeouts,
            pollInterval: pollInterval
        )
        if case let .finished(segments) = fallbackOutcome {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            if canPublishProcessingResult(processingAttemptID) {
                updateDiagnostics(
                    diarizationFallbackUsed: true,
                    speakerLabelStatus: .approximate
                )
            }
            return DiarizationAttemptOutcome(segments: segments, isApproximate: true)
        }

        diarizer = FluidDiarizationEngine(config: .balancedV2)
        if canPublishProcessingResult(processingAttemptID) {
            updateDiagnostics(
                diarizationFallbackUsed: false,
                speakerLabelStatus: .retryNeeded,
                failureMessage: diarizationFailureDetail
            )
        }
        return nil
    }

    private func canPublishProcessingResult(_ attemptID: UUID?) -> Bool {
        guard let attemptID else { return true }
        return isCurrentProcessingAttempt(attemptID)
    }

    /// Runs diarization beside an unstructured watchdog. This intentionally avoids
    /// `withTaskGroup`: leaving a structured task group waits for every child to
    /// finish, so a FluidAudio/Core ML call that ignores cancellation can still hold
    /// the UI hostage after the watchdog has technically "won."
    func diarizeWithWatchdog(
        using diarizer: any DiarizationEngine,
        url: URL,
        initialTimeout: TimeInterval = 120,
        progressTimeout: TimeInterval = 30,
        stageTimeouts: DiarizationStageTimeouts? = nil,
        pollInterval: Duration = .seconds(5)
    ) async -> DiarizationRaceOutcome {
        let execution = await diarizationAttemptCoordinator.run(
            using: diarizer,
            url: url,
            initialTimeout: initialTimeout,
            progressTimeout: progressTimeout,
            stageTimeouts: stageTimeouts,
            pollInterval: pollInterval,
            onAttemptStarted: { [weak self] attemptID in
                await MainActor.run {
                    self?.activeDiarizationAttemptID = attemptID
                }
            },
            onProgress: { [weak self] attemptID, value in
                Task { @MainActor in
                    guard self?.activeDiarizationAttemptID == attemptID,
                          self?.processingWasCancelled == false else {
                        return
                    }
                    self?.progress = 0.6 + min(max(value, 0), 1) * 0.35
                }
            },
            onStage: { [weak self] attemptID, snapshot in
                Task { @MainActor in
                    guard self?.activeDiarizationAttemptID == attemptID,
                          self?.processingWasCancelled == false else {
                        return
                    }
                    self?.recordDiarizationStage(snapshot)
                }
            }
        )
        activeDiarizationAttemptID = nil
        diarizationFailureDetail = execution.outcome.failureDescription
        if let timeout = execution.timeout {
            let message = execution.outcome.failureDescription
                ?? "Speaker labeling timed out."
            updateDiagnostics(
                speakerLabelStatus: .retryNeeded,
                failureMessage: message,
                diarizationCurrentStage: timeout.stage,
                diarizationCurrentStageElapsed: timeout.elapsed,
                diarizationTimedOutStage: timeout.stage,
                diarizationTimedOutAfter: timeout.elapsed,
                diarizationStageTimings: timeout.completedTimings
            )
        }
        return execution.outcome
    }

    func hasUnsafeDiarizationAttemptForTesting() async -> Bool {
        await diarizationAttemptCoordinator.hasUnsafeAttempt
    }

    func clearUnsafeDiarizationAttemptForTesting() async {
        await diarizationAttemptCoordinator.clearForTesting()
    }

    private func approximateSpeakerLabelNote() -> String {
        "Speaker labels are approximate because the detailed pass took too long; a faster pass was used instead."
    }

    private func speakerLabelFailureMessage(saved: Bool) -> String {
        let base = saved
            ? "Speaker labeling could not finish. Your transcript remains saved."
            : "The transcript finished, but speaker labeling could not finish. You can retry speaker labels later."
        guard let diarizationFailureDetail, !diarizationFailureDetail.isEmpty else { return base }
        return "\(base) \(diarizationFailureDetail)"
    }

    private func combinedCompletionNote(_ note: String?) -> String? {
        let parts = [modelFallbackNote, note].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private func replaceOverlappingLiveSegment(_ newSegment: TranscriptionSegment) {
        livePreviewState = .ready
        liveTranscription = Self.mergingLiveSegment(newSegment, into: liveTranscription)
    }

    /// Drops any segment in `existing` whose time range overlaps `newSegment` at all,
    /// appends `newSegment`, and returns the result sorted by start time. This lets
    /// re-transcribed portions of the rolling window replace stale text while
    /// finalized segments before the window (which never overlap) are preserved.
    static func mergingLiveSegment(
        _ newSegment: TranscriptionSegment,
        into existing: [TranscriptionSegment]
    ) -> [TranscriptionSegment] {
        var result = existing.filter { current in
            !(current.startMs < newSegment.endMs && current.endMs > newSegment.startMs)
        }
        result.append(newSegment)
        result.sort { $0.startMs < $1.startMs }
        return result
    }
}

/// The result of a single diarization attempt, including whether it used the
/// faster (less accurate) fallback config.
/// Not private: exposed so unit tests can inspect outcomes returned by
/// `runDiarizationWithFallback`.
nonisolated struct DiarizationAttemptOutcome {
    let segments: [DiarizationSegment]
    let isApproximate: Bool
}

/// The outcome of racing a diarization attempt against its watchdog.
nonisolated enum DiarizationRaceOutcome: Equatable, Sendable {
    case finished([DiarizationSegment])
    case failed(String)
    case timedOut(String)
    case canceled(String)
    case blocked(String)

    var preventsFallback: Bool {
        switch self {
        case .timedOut, .canceled, .blocked:
            true
        case .finished, .failed:
            false
        }
    }

    var failureDescription: String? {
        switch self {
        case .finished:
            nil
        case let .failed(description),
             let .timedOut(description),
             let .canceled(description),
             let .blocked(description):
            description
        }
    }
}

nonisolated struct DiarizationStageTimeouts: Equatable, Sendable {
    var starting: TimeInterval
    var audioInspection: TimeInterval
    var conversionPrep: TimeInterval
    var modelLoad: TimeInterval
    var process: TimeInterval
    var finalize: TimeInterval

    static let production = DiarizationStageTimeouts(
        starting: 30,
        audioInspection: 15,
        conversionPrep: 20,
        modelLoad: 300,
        process: 90,
        finalize: 60
    )

    static func legacy(initialTimeout: TimeInterval, progressTimeout: TimeInterval) -> DiarizationStageTimeouts {
        DiarizationStageTimeouts(
            starting: initialTimeout,
            audioInspection: initialTimeout,
            conversionPrep: initialTimeout,
            modelLoad: initialTimeout,
            process: progressTimeout,
            finalize: progressTimeout
        )
    }

    func limit(for stage: DiarizationDiagnosticStage) -> TimeInterval? {
        switch stage {
        case .starting:
            starting
        case .audioInspection:
            audioInspection
        case .conversionPrep:
            conversionPrep
        case .modelLoad:
            modelLoad
        case .process:
            process
        case .finalize:
            finalize
        case .finished:
            nil
        }
    }
}

nonisolated struct DiarizationStageSnapshot: Equatable, Sendable {
    let currentStage: DiarizationDiagnosticStage
    let currentStageElapsed: TimeInterval
    let completedTimings: [DiarizationStageTiming]
}

nonisolated struct DiarizationTimeoutInfo: Equatable, Sendable {
    let stage: DiarizationDiagnosticStage
    let elapsed: TimeInterval
    let limit: TimeInterval
    let completedTimings: [DiarizationStageTiming]
}

actor DiarizationAttemptResultBox {
    private(set) var result: DiarizationRaceOutcome?

    func complete(_ result: DiarizationRaceOutcome) {
        guard self.result == nil else { return }
        self.result = result
    }
}

actor DiarizationAttemptGuard {
    enum BeginResult: Equatable, Sendable {
        case started(UUID)
        case blocked(String)

        var blockedMessage: String? {
            if case let .blocked(message) = self { return message }
            return nil
        }
    }

    enum AbandonedReason: String, Sendable {
        case timedOut
        case canceled
    }

    struct Attempt: Sendable {
        let id: UUID
        let audioFileName: String
        let startedAt: Date
        var abandonedReason: AbandonedReason?
    }

    static let shared = DiarizationAttemptGuard()

    private var activeAttempt: Attempt?
    private var abandonedAttempt: Attempt?

    var hasUnsafeAttempt: Bool {
        activeAttempt != nil || abandonedAttempt != nil
    }

    func begin(audioFileName: String) -> BeginResult {
        if activeAttempt != nil {
            return .blocked("Speaker labeling is already running. Wait for it to finish before retrying.")
        }
        if abandonedAttempt != nil {
            return .blocked("A previous speaker-labeling attempt is still cleaning up. Wait a moment and try again; if it remains unavailable, close and reopen Transcriber before retrying speaker labels.")
        }
        let attempt = Attempt(id: UUID(), audioFileName: audioFileName, startedAt: .now)
        activeAttempt = attempt
        return .started(attempt.id)
    }

    func finish(_ id: UUID) {
        if activeAttempt?.id == id {
            activeAttempt = nil
        }
        if abandonedAttempt?.id == id {
            abandonedAttempt = nil
        }
    }

    func markAbandoned(_ id: UUID, reason: AbandonedReason) {
        guard var attempt = activeAttempt, attempt.id == id else { return }
        attempt.abandonedReason = reason
        activeAttempt = nil
        abandonedAttempt = attempt
    }

    func clearForTesting() {
        activeAttempt = nil
        abandonedAttempt = nil
    }
}

/// Tracks elapsed time for the diarization watchdog by stage. The model-load
/// stage intentionally has a longer production limit because first-run Core ML
/// compilation can take much longer than steady-state processing.
actor DiarizationProgressGate {
    private let startedAt = Date.now
    private var lastProgressAt: Date?
    private var currentStage = DiarizationDiagnosticStage.starting
    private var currentStageStartedAt = Date.now
    private var completedTimings: [DiarizationStageTiming] = []
    private let timeouts: DiarizationStageTimeouts

    init(timeouts: DiarizationStageTimeouts) {
        self.timeouts = timeouts
    }

    func reportProgress() {
        lastProgressAt = .now
    }

    func reportStage(_ event: DiarizationStageEvent) -> DiarizationStageSnapshot {
        let now = Date.now
        switch event.kind {
        case .started:
            if currentStage != event.stage {
                currentStage = event.stage
                currentStageStartedAt = now
                if event.stage != .process {
                    lastProgressAt = nil
                }
            }
        case .ended:
            let duration = max(0, now.timeIntervalSince(currentStageStartedAt))
            recordCompletedTiming(stage: event.stage, duration: duration)
            if event.stage == .process {
                lastProgressAt = now
            }
        }
        return snapshot(at: now)
    }

    func timeoutInfo() -> DiarizationTimeoutInfo? {
        let now = Date.now
        let baseDate: Date
        if currentStage == .process, let lastProgressAt {
            baseDate = lastProgressAt
        } else if currentStage == .starting {
            baseDate = startedAt
        } else {
            baseDate = currentStageStartedAt
        }
        let elapsed = now.timeIntervalSince(baseDate)
        guard let limit = timeouts.limit(for: currentStage), elapsed >= limit else {
            return nil
        }
        return DiarizationTimeoutInfo(
            stage: currentStage,
            elapsed: elapsed,
            limit: limit,
            completedTimings: completedTimings
        )
    }

    private func snapshot(at date: Date) -> DiarizationStageSnapshot {
        DiarizationStageSnapshot(
            currentStage: currentStage,
            currentStageElapsed: max(0, date.timeIntervalSince(currentStageStartedAt)),
            completedTimings: completedTimings
        )
    }

    private func recordCompletedTiming(stage: DiarizationDiagnosticStage, duration: TimeInterval) {
        guard let index = completedTimings.firstIndex(where: { $0.stage == stage }) else {
            completedTimings.append(DiarizationStageTiming(stage: stage, duration: duration))
            return
        }
        let existing = completedTimings[index]
        completedTimings[index] = DiarizationStageTiming(
            stage: stage,
            duration: existing.duration + duration
        )
    }
}

extension View {
    /// Presents `session.storageErrorMessage` as an alert and clears it on dismissal.
    func storageErrorAlert(_ session: TranscriptionSession) -> some View {
        alert(
            "Storage Issue",
            isPresented: Binding(
                get: { session.storageErrorMessage != nil },
                set: { isPresented in if !isPresented { session.dismissStorageError() } }
            ),
            actions: {
                Button("OK", role: .cancel) { session.dismissStorageError() }
            },
            message: {
                Text(session.storageErrorMessage ?? "")
            }
        )
    }
}
