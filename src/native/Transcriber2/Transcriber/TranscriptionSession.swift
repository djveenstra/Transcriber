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
    enum State: Equatable {
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

    private let transcriber: any TranscriptionEngine = WhisperKitTranscriptionEngine()
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
    private var liveAudioContinuation: AsyncStream<CapturedAudioChunk>.Continuation?
    private var liveConsumerTask: Task<Void, Never>?
    private var processingWasCancelled = false
    private var processingFinalModelChoice: FinalTranscriptionModelChoice?
    private var modelFallbackNote: String?
    private let statusActivityStore = RecordingStatusActivityStore.shared
    private let diagnosticsStore = ProcessingDiagnosticsStore.shared
    private let diarizationAttemptGuard: DiarizationAttemptGuard
    private var activeDiarizationWorkTask: Task<Void, Never>?
    private var activeDiarizationAttemptID: UUID?
    var diarizationInitialTimeout: TimeInterval = 120
    var diarizationProgressTimeout: TimeInterval = 30
    var diarizationStageTimeouts: DiarizationStageTimeouts? = .production
    var diarizationPollInterval: Duration = .seconds(5)

    init(diarizationAttemptGuard: DiarizationAttemptGuard = .shared) {
        self.diarizationAttemptGuard = diarizationAttemptGuard
    }

    var liveSegments: [TranscriptSegment] {
        TranscriptMerger.merge(transcription: liveTranscription, diarization: liveDiarization)
    }

    var canCancelProcessing: Bool {
        if isIdentifyingSpeakers { return true }
        if case .processing = state { return true }
        return false
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
        latestDiagnostics = nil
        persistenceContext = context

        guard await recorder.requestPermission() else {
            state = .failed("Microphone permission was denied.")
            return
        }

        do {
            let microphoneFormat = try recorder.prepareForRecording()
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

            try recorder.start(at: url)
            state = .recording
            livePreviewState = .loading
            livePreparationTask = Task { [weak self] in
                guard let self else { return }
                do {
#if os(iOS)
                    try await self.liveParakeet.prepare()
                    guard !Task.isCancelled, self.state == .recording else { return }
                    self.livePreviewState = .ready
#else
                    try await self.transcriber.prepareLive(audioFormat: microphoneFormat)
                    guard !Task.isCancelled, self.state == .recording else { return }
                    self.livePreviewState = .ready
                    let loaded = await self.transcriber.currentLoadedModelID()
                    self.modelState = .ready(WhisperModelChoice.choice(for: loaded ?? "").name)
#endif
                } catch {
                    guard !Task.isCancelled, self.state == .recording else { return }
                    self.livePreviewState = .unavailable
                    self.livePreviewNote = "Live preview unavailable: \(error.localizedDescription)"
                }
            }
        } catch {
            recorder.stop()
            recorder.onSystemEvent = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording(in context: ModelContext) async {
        guard state == .recording, let audioURL else { return }
        let writeError = recorder.stop()
        recorder.onSystemEvent = nil
        await stopLiveCaptureTasks()
        setProcessingPhase(.savingRecording, progress: 0.01)
        preserveRecording(in: context)

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
            try await processFile(audioURL)
            updateSavedRecording()
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. Your recording is saved and can be retried from the library.",
                unsavedMessage: "Transcription was canceled."
            )
        } catch {
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript from the library."
            )
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
        }
    }

    func importAudio(_ sourceURL: URL) async {
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
        latestDiagnostics = nil

        let destination = AppStoragePaths.recordingsDirectory
            .appendingPathComponent("import-\(UUID().uuidString).\(sourceURL.pathExtension)")
        do {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            audioURL = destination
            try await processFile(destination)
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. The imported audio remains available for retry.",
                unsavedMessage: "Transcription was canceled. Import the file again when you are ready."
            )
        } catch {
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
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
        do {
            try await processFile(recording.audioURL)
            updateSavedRecording()
        } catch is CancellationError {
            await handleProcessingCancellation(
                savedMessage: "Transcription was canceled. Your recording is saved and can be retried from the library.",
                unsavedMessage: "Transcription was canceled."
            )
        } catch {
            recording.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript again."
            )
            clearProcessingPhase()
            state = .failed(error.localizedDescription)
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
        activeDiarizationWorkTask?.cancel()
        activeDiarizationWorkTask = nil
        activeDiarizationAttemptID = nil
        recorder.onSystemEvent = nil
    }

    func retrySpeakerLabels(for recording: Recording, in context: ModelContext) async {
        guard !recording.rawTranscription.isEmpty else {
            state = .failed("This older transcript does not contain the timing data needed to retry speaker labels.")
            return
        }
        statusActivityStore.set(.speakerLabeling, forAudioFileName: recording.audioFileName)
        defer { statusActivityStore.clear(audioFileName: recording.audioFileName) }
        guard !Task.isCancelled else { return }
        persistenceContext = context
        processingWasCancelled = false
        audioURL = recording.audioURL
        rawTranscription = recording.rawTranscription
        finalSegments = recording.segments
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
            initialTimeout: diarizationInitialTimeout,
            progressTimeout: diarizationProgressTimeout,
            stageTimeouts: diarizationStageTimeouts,
            pollInterval: diarizationPollInterval
        ) {
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            guard !processingWasCancelled, !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled."
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
        } else {
            guard !processingWasCancelled, !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled."
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
        }
    }

    func retryCurrentSpeakerLabels() async {
        guard let audioURL, !rawTranscription.isEmpty, !Task.isCancelled else { return }
        processingWasCancelled = false
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
            initialTimeout: diarizationInitialTimeout,
            progressTimeout: diarizationProgressTimeout,
            stageTimeouts: diarizationStageTimeouts,
            pollInterval: diarizationPollInterval
        ) {
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            guard !processingWasCancelled, !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled. You can retry speaker labels later."
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
            guard !processingWasCancelled, !Task.isCancelled else {
                await handleProcessingCancellation(
                    savedMessage: "Speaker labeling was canceled. Your transcript remains saved.",
                    unsavedMessage: "Speaker labeling was canceled. You can retry speaker labels later."
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
        processingWasCancelled = true
        activeDiarizationWorkTask?.cancel()
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

    private func processFile(_ url: URL) async throws {
        statusActivityStore.set(.transcribing, forAudioFileName: url.lastPathComponent)
        defer { statusActivityStore.clear(audioFileName: url.lastPathComponent) }
        processingWasCancelled = false
        beginDiagnostics(for: url)
        do {
            try Task.checkCancellation()
            setProcessingPhase(.preparingModel, progress: 0.02)
            modelState = .loading
            let modelLoadStarted = Date()
            try await verifySelectedFinalModelBeforeProcessing()
            updateDiagnostics(
                model: activeFinalModelChoice,
                modelLoadTime: Date().timeIntervalSince(modelLoadStarted),
                transcriptionFallbackUsed: modelFallbackNote != nil
            )
            let transcriptionStarted = Date()
            let transcription = try await transcribeSelectedFinalModel(url) { [weak self] value in
                Task { @MainActor in
                    self?.setProcessingPhase(
                        .transcribing,
                        progress: 0.05 + min(max(value, 0), 1) * 0.55
                    )
                }
            }
            updateDiagnostics(
                transcriptionTime: Date().timeIntervalSince(transcriptionStarted),
                speakerLabelStatus: .notStarted
            )
            modelState = .ready(activeFinalModelChoice.name)
            try Task.checkCancellation()
            guard !processingWasCancelled else { throw CancellationError() }
            rawTranscription = transcription
            savedRecording?.rawTranscription = transcription
            savedRecording?.transcriptionNeedsRetry = false
            savedRecording?.finalTranscriptionModelID = selectedFinalModelID

            try Task.checkCancellation()

            // Preserve the finished text before speaker labeling begins.
            setProcessingPhase(.savingTranscript, progress: 0.58)
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
                initialTimeout: diarizationInitialTimeout,
                progressTimeout: diarizationProgressTimeout,
                stageTimeouts: diarizationStageTimeouts,
                pollInterval: diarizationPollInterval
            )
            let diarizationTime = Date().timeIntervalSince(diarizationStarted)
            try Task.checkCancellation()
            guard !processingWasCancelled else { throw CancellationError() }
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
            progress = 1
            clearProcessingPhase()
            diarizationSessionLogger.info("diarization.state_cleared reason=finished")
            state = .completed
        } catch {
            recordDiagnosticsFailure(error.localizedDescription)
            throw error
        }
    }

    private func handleProcessingCancellation(savedMessage: String, unsavedMessage: String) async {
        isIdentifyingSpeakers = false
        progress = 0
        activeDiarizationAttemptID = nil
        activeDiarizationWorkTask = nil
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
        } else {
            updateDiagnostics(
                speakerLabelStatus: .notAvailable,
                failureMessage: unsavedMessage
            )
            state = .failed(unsavedMessage)
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
#if os(iOS)
        await liveParakeet.finish()
#endif
    }

    private func preserveRecording(in context: ModelContext) {
        guard !saved, let audioURL else { return }
        persistenceContext = context
        let recording = RecordingInterruptionRecovery.makeRetryableRecording(
            title: Date.now.formatted(date: .abbreviated, time: .shortened),
            duration: recorder.duration,
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
            failureMessage: "Your recording could not be saved yet. Transcription will continue and we'll try saving it again once it finishes."
        )
    }

    func dismissStorageError() {
        storageErrorMessage = nil
    }

    /// Saves the context, surfacing failures via `storageErrorMessage` instead of
    /// silently discarding them. `failureMessage` should tell the user what remains
    /// safe (e.g. "still visible here") so they know whether to wait or take action.
    private func persistChanges(in context: ModelContext, failureMessage: String) {
        do {
            try context.save()
            storageErrorMessage = nil
        } catch {
            persistenceLogger.error("Failed to save model context: \(error.localizedDescription, privacy: .public)")
            storageErrorMessage = failureMessage
        }
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
            return try await transcriber.transcribeFile(url, progress: progress)
        case .parakeet:
            let engine = finalParakeet ?? ParakeetFinalTranscriptionEngine(model: choice)
            finalParakeet = engine
            return try await engine.transcribeFile(url, progress: progress)
        }
#else
        UserDefaults.standard.set(activeFinalModelChoice.id, forKey: "whisperModel")
        return try await transcriber.transcribeFile(url, progress: progress)
#endif
    }

    private func unloadSelectedFinalModel() async {
#if os(iOS)
        await finalParakeet?.unload()
        finalParakeet = nil
        if FinalTranscriptionModelChoice.choice(for: selectedFinalModelID).provider == .parakeet {
            modelState = .notLoaded
        }
#endif
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
            updateDiagnostics(
                diarizationFallbackUsed: false,
                speakerLabelStatus: .complete
            )
            return DiarizationAttemptOutcome(segments: segments, isApproximate: false)
        }
        if primaryOutcome.preventsFallback {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            updateDiagnostics(
                diarizationFallbackUsed: false,
                speakerLabelStatus: .retryNeeded,
                failureMessage: diarizationFailureDetail
            )
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
            updateDiagnostics(
                diarizationFallbackUsed: true,
                speakerLabelStatus: .approximate
            )
            return DiarizationAttemptOutcome(segments: segments, isApproximate: true)
        }

        diarizer = FluidDiarizationEngine(config: .balancedV2)
        updateDiagnostics(
            diarizationFallbackUsed: false,
            speakerLabelStatus: .retryNeeded,
            failureMessage: diarizationFailureDetail
        )
        return nil
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
        let beginResult = await diarizationAttemptGuard.begin(audioFileName: url.lastPathComponent)
        guard case let .started(attemptID) = beginResult else {
            let message = beginResult.blockedMessage ?? "Speaker labeling cannot start safely yet."
            diarizationFailureDetail = message
            diarizationSessionLogger.error("diarization.result.blocked reason=\(message, privacy: .public)")
            return .blocked(message)
        }

        let progressGate = DiarizationProgressGate(
            timeouts: stageTimeouts ?? DiarizationStageTimeouts.legacy(
                initialTimeout: initialTimeout,
                progressTimeout: progressTimeout
            )
        )
        let resultBox = DiarizationAttemptResultBox()
        activeDiarizationAttemptID = attemptID
        diarizationSessionLogger.info("diarization.attempt.start id=\(attemptID.uuidString, privacy: .public) file=\(url.lastPathComponent, privacy: .private)")

        let workTask = Task {
            do {
                let result = try await diarizer.diarizeFile(
                    url,
                    progress: { [weak self] value in
                        Task { await progressGate.reportProgress() }
                        Task { @MainActor in
                            guard self?.activeDiarizationAttemptID == attemptID,
                                  self?.processingWasCancelled == false else {
                                return
                            }
                            self?.progress = 0.6 + min(max(value, 0), 1) * 0.35
                        }
                    },
                    stage: { [weak self] event in
                        Task {
                            let snapshot = await progressGate.reportStage(event)
                            await MainActor.run {
                                guard self?.activeDiarizationAttemptID == attemptID,
                                      self?.processingWasCancelled == false else {
                                    return
                                }
                                self?.recordDiarizationStage(snapshot)
                            }
                        }
                    }
                )
                await resultBox.complete(.finished(result))
                await diarizationAttemptGuard.finish(attemptID)
                diarizationSessionLogger.info("diarization.result.success id=\(attemptID.uuidString, privacy: .public) segments=\(result.count, privacy: .public)")
            } catch is CancellationError {
                await resultBox.complete(.canceled("Speaker labeling was canceled."))
                await diarizationAttemptGuard.finish(attemptID)
                diarizationSessionLogger.info("diarization.result.canceled id=\(attemptID.uuidString, privacy: .public)")
            } catch {
                let message = error.localizedDescription
                await resultBox.complete(.failed(message))
                await diarizationAttemptGuard.finish(attemptID)
                diarizationSessionLogger.error("diarization.result.failure id=\(attemptID.uuidString, privacy: .public) error=\(message, privacy: .public)")
            }
        }
        activeDiarizationWorkTask = workTask

        while true {
            if let outcome = await resultBox.result {
                activeDiarizationWorkTask = nil
                activeDiarizationAttemptID = nil
                return applyDiarizationOutcome(outcome)
            }

            try? await Task.sleep(for: pollInterval)

            if let outcome = await resultBox.result {
                activeDiarizationWorkTask = nil
                activeDiarizationAttemptID = nil
                return applyDiarizationOutcome(outcome)
            }

            if Task.isCancelled || processingWasCancelled {
                let message = "Speaker labeling was canceled. Your transcript is available and speaker labels can be retried later."
                workTask.cancel()
                activeDiarizationWorkTask = nil
                activeDiarizationAttemptID = nil
                await diarizationAttemptGuard.markAbandoned(attemptID, reason: .canceled)
                diarizationFailureDetail = message
                diarizationSessionLogger.info("diarization.cancel_requested id=\(attemptID.uuidString, privacy: .public)")
                diarizationSessionLogger.info("diarization.state_cleared reason=cancel")
                return .canceled(message)
            }

            if let timeout = await progressGate.timeoutInfo() {
                let message = Self.diarizationTimeoutMessage(timeout)
                workTask.cancel()
                activeDiarizationWorkTask = nil
                activeDiarizationAttemptID = nil
                await diarizationAttemptGuard.markAbandoned(attemptID, reason: .timedOut)
                diarizationFailureDetail = message
                updateDiagnostics(
                    speakerLabelStatus: .retryNeeded,
                    failureMessage: message,
                    diarizationCurrentStage: timeout.stage,
                    diarizationCurrentStageElapsed: timeout.elapsed,
                    diarizationTimedOutStage: timeout.stage,
                    diarizationTimedOutAfter: timeout.elapsed,
                    diarizationStageTimings: timeout.completedTimings
                )
                diarizationSessionLogger.error(
                    "diarization.timeout_fired id=\(attemptID.uuidString, privacy: .public) stage=\(timeout.stage.displayText, privacy: .public) elapsed=\(timeout.elapsed, privacy: .public) limit=\(timeout.limit, privacy: .public)"
                )
                diarizationSessionLogger.info("diarization.state_cleared reason=timeout")
                diarizationSessionLogger.info("diarization.retry_state_set reason=timeout guarded=true")
                return .timedOut(message)
            }
        }
    }

    private func applyDiarizationOutcome(_ outcome: DiarizationRaceOutcome) -> DiarizationRaceOutcome {
        switch outcome {
        case .finished:
            diarizationFailureDetail = nil
        case .failed(let description), .timedOut(let description), .canceled(let description), .blocked(let description):
            diarizationFailureDetail = description
        }
        return outcome
    }

    func hasUnsafeDiarizationAttemptForTesting() async -> Bool {
        await diarizationAttemptGuard.hasUnsafeAttempt
    }

    func clearUnsafeDiarizationAttemptForTesting() async {
        await diarizationAttemptGuard.clearForTesting()
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

    private static func diarizationTimeoutMessage(_ timeout: DiarizationTimeoutInfo) -> String {
        let elapsed = DiagnosticsMetricFormatter.formatSeconds(timeout.elapsed)
        let limit = DiagnosticsMetricFormatter.formatSeconds(timeout.limit)
        return "Speaker labeling timed out during \(timeout.stage.displayText.lowercased()) after \(elapsed) (limit \(limit)). The transcript is available, and Transcriber is guarding against an unsafe overlapping retry while the previous speaker-labeling call finishes."
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
private actor DiarizationProgressGate {
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
