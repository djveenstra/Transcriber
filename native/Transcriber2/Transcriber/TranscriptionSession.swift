import AVFoundation
import Combine
import FluidAudio
import Foundation
import os
import SwiftData
import SwiftUI

private let persistenceLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Persistence")

@MainActor
final class TranscriptionSession: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case processing(String)
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
    private weak var savedRecording: Recording?
    private var persistenceContext: ModelContext?
    private var livePreparationTask: Task<Void, Never>?
    private var liveAudioContinuation: AsyncStream<CapturedAudioChunk>.Continuation?
    private var liveConsumerTask: Task<Void, Never>?

    var liveSegments: [TranscriptSegment] {
        TranscriptMerger.merge(transcription: liveTranscription, diarization: liveDiarization)
    }

    var selectedModelName: String {
#if os(iOS)
        return FinalTranscriptionModelChoice.choice(for: FinalTranscriptionModelChoice.selectedID()).name
#else
        let id = WhisperModelChoice.allowedID(UserDefaults.standard.string(forKey: "whisperModel"))
        return WhisperModelChoice.choice(for: id).name
#endif
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

    func startRecording() async {
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
        saved = false

        guard await recorder.requestPermission() else {
            state = .failed("Microphone permission was denied.")
            return
        }

        do {
            let microphoneFormat = try recorder.prepareForRecording()
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
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording(in context: ModelContext) async {
        guard state == .recording, let audioURL else { return }
        let writeError = recorder.stop()
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
        preserveRecording(in: context)

        if let writeError {
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording was saved, but the audio file may be incomplete."
            )
            state = .failed("Recording stopped with a write error: \(writeError.localizedDescription). The audio file may be incomplete.")
            return
        }

        state = .processing("Finalizing live transcript")
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
        } catch {
            savedRecording?.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript from the library."
            )
            state = .failed(error.localizedDescription)
        }
    }

    func importAudio(_ sourceURL: URL) async {
        state = .processing("Importing audio")
        finalSegments = []
        liveTranscription = []
        liveDiarization = []
        rawTranscription = []
        completionNote = nil
        livePreviewNote = nil
        diarizationNeedsRetry = false
        isIdentifyingSpeakers = false
        diarizationFailureDetail = nil
        saved = false

        let destination = AppStoragePaths.recordingsDirectory
            .appendingPathComponent("import-\(UUID().uuidString).\(sourceURL.pathExtension)")
        do {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            audioURL = destination
            try await processFile(destination)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func saveCompletedRecording(in context: ModelContext) {
        guard let audioURL, state == .completed else { return }
        persistenceContext = context
        if saved {
            updateSavedRecording()
            return
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
    }

    func retryTranscription(for recording: Recording, in context: ModelContext) async {
        audioURL = recording.audioURL
        savedRecording = recording
        persistenceContext = context
        saved = true
        completionNote = nil
        diarizationFailureDetail = nil
        do {
            try await processFile(recording.audioURL)
            updateSavedRecording()
        } catch {
            recording.transcriptionNeedsRetry = true
            persistChanges(
                in: context,
                failureMessage: "Your recording is safe, but we couldn't save its status. You can retry the transcript again."
            )
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
        saved = false
        savedRecording = nil
        persistenceContext = nil
        storageErrorMessage = nil
        liveAudioContinuation?.finish()
        liveAudioContinuation = nil
        liveConsumerTask?.cancel()
        liveConsumerTask = nil
        livePreparationTask?.cancel()
        livePreparationTask = nil
    }

    func retrySpeakerLabels(for recording: Recording, in context: ModelContext) async {
        guard !recording.rawTranscription.isEmpty else {
            state = .failed("This older transcript does not contain the timing data needed to retry speaker labels.")
            return
        }
        guard !Task.isCancelled else { return }
        persistenceContext = context
        audioURL = recording.audioURL
        rawTranscription = recording.rawTranscription
        finalSegments = recording.segments
        state = .processing("Identifying speakers")
        progress = 0.65
        if let outcome = await runDiarizationWithFallback(recording.audioURL) {
            let merged = TranscriptMerger.merge(transcription: recording.rawTranscription, diarization: outcome.segments)
            recording.segments = merged
            recording.diarizationNeedsRetry = false
            finalSegments = merged
            completionNote = outcome.isApproximate ? approximateSpeakerLabelNote() : nil
            diarizationNeedsRetry = false
            progress = 1
            state = .completed
            persistChanges(
                in: context,
                failureMessage: "The updated speaker labels could not be saved. They remain visible here, but it will be lost if you leave this screen."
            )
        } else {
            completionNote = speakerLabelFailureMessage(saved: true)
            progress = 1
            state = .completed
        }
    }

    func retryCurrentSpeakerLabels() async {
        guard let audioURL, !rawTranscription.isEmpty, !Task.isCancelled else { return }
        state = .processing("Identifying speakers")
        progress = 0.6
        if let outcome = await runDiarizationWithFallback(audioURL) {
            finalSegments = TranscriptMerger.merge(transcription: rawTranscription, diarization: outcome.segments)
            completionNote = outcome.isApproximate ? approximateSpeakerLabelNote() : nil
            diarizationNeedsRetry = false
        } else {
            completionNote = speakerLabelFailureMessage(saved: false)
            diarizationNeedsRetry = true
        }
        savedRecording?.segments = finalSegments
        savedRecording?.diarizationNeedsRetry = diarizationNeedsRetry
        progress = 1
        state = .completed
    }

    private func processFile(_ url: URL) async throws {
        try Task.checkCancellation()
        state = .processing("Preparing transcription")
        progress = 0.02
        modelState = .loading
        let transcription = try await transcribeSelectedFinalModel(url) { [weak self] value in
            Task { @MainActor in
                self?.state = .processing("Transcribing")
                self?.progress = 0.05 + min(max(value, 0), 1) * 0.55
            }
        }
        modelState = .ready(selectedModelName)
        rawTranscription = transcription
        savedRecording?.rawTranscription = transcription
        savedRecording?.transcriptionNeedsRetry = false
        savedRecording?.finalTranscriptionModelID = selectedFinalModelID

        try Task.checkCancellation()

        // Preserve the finished text before speaker labeling begins.
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
        state = .completed
#else
        state = .processing("Identifying speakers")
#endif
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
        let outcome = await runDiarizationWithFallback(url)
        if let outcome {
            finalSegments = TranscriptMerger.merge(
                transcription: transcription,
                diarization: outcome.segments
            )
            diarizationNeedsRetry = false
            completionNote = outcome.isApproximate ? approximateSpeakerLabelNote() : nil
        } else {
            completionNote = speakerLabelFailureMessage(saved: false)
            diarizationNeedsRetry = true
        }
#if os(iOS)
        isIdentifyingSpeakers = false
#else
        state = .processing("Saving")
#endif
        progress = 0.98
        progress = 1
        state = .completed
    }

    private func preserveRecording(in context: ModelContext) {
        guard !saved, let audioURL else { return }
        persistenceContext = context
        let recording = Recording(
            title: Date.now.formatted(date: .abbreviated, time: .shortened),
            durationSeconds: recorder.duration,
            audioFileName: audioURL.lastPathComponent,
            segments: [],
            transcriptionNeedsRetry: true,
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
#if os(iOS)
        FinalTranscriptionModelChoice.selectedID()
#else
        WhisperModelChoice.allowedID(UserDefaults.standard.string(forKey: "whisperModel"))
#endif
    }

    private func prepareSelectedFinalModel() async throws {
#if os(iOS)
        let choice = FinalTranscriptionModelChoice.choice(for: selectedFinalModelID)
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

    private func transcribeSelectedFinalModel(
        _ url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionSegment] {
#if os(iOS)
        let choice = FinalTranscriptionModelChoice.choice(for: selectedFinalModelID)
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
    /// (less accurate) Fast V2 config if Balanced V2 fails or times out. Returns `nil`
    /// only if both attempts fail.
    ///
    /// The timeout/poll parameters and `fallbackEngine` default to production values
    /// and are only overridden by tests to keep the watchdog race fast and deterministic.
    func runDiarizationWithFallback(
        _ url: URL,
        initialTimeout: TimeInterval = 120,
        progressTimeout: TimeInterval = 30,
        pollInterval: Duration = .seconds(5),
        fallbackEngine: any DiarizationEngine = FluidDiarizationEngine(config: .fastV2)
    ) async -> DiarizationAttemptOutcome? {
        diarizationFailureDetail = nil
        if let segments = await diarizeWithWatchdog(
            using: diarizer,
            url: url,
            initialTimeout: initialTimeout,
            progressTimeout: progressTimeout,
            pollInterval: pollInterval
        ) {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            return DiarizationAttemptOutcome(segments: segments, isApproximate: false)
        }

        diarizationFailureDetail = nil
        if let segments = await diarizeWithWatchdog(
            using: fallbackEngine,
            url: url,
            initialTimeout: initialTimeout,
            progressTimeout: progressTimeout,
            pollInterval: pollInterval
        ) {
            diarizer = FluidDiarizationEngine(config: .balancedV2)
            return DiarizationAttemptOutcome(segments: segments, isApproximate: true)
        }

        diarizer = FluidDiarizationEngine(config: .balancedV2)
        return nil
    }

    /// Races a diarization attempt against a watchdog that allows up to
    /// `initialTimeout` seconds before the first progress update, then
    /// `progressTimeout` seconds without further progress. Cancels whichever task
    /// doesn't finish first.
    func diarizeWithWatchdog(
        using diarizer: any DiarizationEngine,
        url: URL,
        initialTimeout: TimeInterval = 120,
        progressTimeout: TimeInterval = 30,
        pollInterval: Duration = .seconds(5)
    ) async -> [DiarizationSegment]? {
        let progressGate = DiarizationProgressGate(initialTimeout: initialTimeout, progressTimeout: progressTimeout)
        let outcome = await withTaskGroup(of: DiarizationRaceOutcome.self) { group -> DiarizationRaceOutcome in
            group.addTask {
                do {
                    let result = try await diarizer.diarizeFile(url) { [weak self] value in
                        Task { await progressGate.reportProgress() }
                        Task { @MainActor in
                            self?.progress = 0.6 + min(max(value, 0), 1) * 0.35
                        }
                    }
                    return .finished(result)
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: pollInterval)
                    if await progressGate.hasTimedOut() {
                        return .timedOut
                    }
                }
                return .timedOut
            }
            defer { group.cancelAll() }
            return await group.next() ?? .timedOut
        }

        switch outcome {
        case .finished(let segments):
            return segments
        case .failed(let description):
            diarizationFailureDetail = description
            return nil
        case .timedOut:
            diarizationFailureDetail = "Speaker labeling timed out while processing this recording."
            return nil
        }
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
private enum DiarizationRaceOutcome: Sendable {
    case finished([DiarizationSegment])
    case failed(String)
    case timedOut
}

/// Tracks elapsed time for the diarization watchdog: allows up to
/// `initialTimeout` seconds before the first progress update, then
/// `progressTimeout` seconds without further progress.
private actor DiarizationProgressGate {
    private let startedAt = Date.now
    private var lastProgressAt: Date?
    private let initialTimeout: TimeInterval
    private let progressTimeout: TimeInterval

    init(initialTimeout: TimeInterval, progressTimeout: TimeInterval) {
        self.initialTimeout = initialTimeout
        self.progressTimeout = progressTimeout
    }

    func reportProgress() {
        lastProgressAt = .now
    }

    func hasTimedOut() -> Bool {
        if let lastProgressAt {
            return Date.now.timeIntervalSince(lastProgressAt) >= progressTimeout
        }
        return Date.now.timeIntervalSince(startedAt) >= initialTimeout
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
