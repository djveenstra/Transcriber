import AVFoundation
import Combine
import Foundation
import SwiftData

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

    let recorder = AudioRecorder()

    private let transcriber: any TranscriptionEngine = WhisperKitTranscriptionEngine()
#if os(iOS)
    private let liveParakeet = ParakeetEOULiveEngine()
    private var finalParakeet: ParakeetFinalTranscriptionEngine?
#endif
    private var diarizer: any DiarizationEngine = FluidDiarizationEngine()
    private var audioURL: URL?
    private var saved = false
    private weak var savedRecording: Recording?
    private var persistenceContext: ModelContext?
    private var livePreparationTask: Task<Void, Never>?
    private var diarizationPreparationTask: Task<Void, Never>?

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
            recorder.onBuffer = { [weak self] buffer in
                guard let self else { return }
                Task {
                    do {
#if os(iOS)
                        try await self.liveParakeet.append(buffer)
#else
                        try await self.transcriber.append(buffer)
#endif
                    } catch {
                        await MainActor.run {
                            self.livePreviewState = .unavailable
                            self.livePreviewNote = "Live preview paused: \(error.localizedDescription)"
                        }
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
                    self.livePreviewState = .ready
#else
                    try await self.transcriber.prepareLive(audioFormat: microphoneFormat)
                    self.livePreviewState = .ready
                    let loaded = await self.transcriber.currentLoadedModelID()
                    self.modelState = .ready(WhisperModelChoice.choice(for: loaded ?? "").name)
#endif
                } catch {
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
        recorder.stop()
        preserveRecording(in: context)
        state = .processing("Finalizing live transcript")
#if os(iOS)
        livePreparationTask?.cancel()
#else
        await livePreparationTask?.value
#endif
        livePreparationTask = nil
        do {
#if os(iOS)
            await liveParakeet.finish()
#else
            try await transcriber.finishLive()
            await transcriber.unload()
            modelState = .loading
            try? await Task.sleep(for: .seconds(1))
#endif
            try await processFile(audioURL)
            updateSavedRecording()
        } catch {
            savedRecording?.transcriptionNeedsRetry = true
            try? context.save()
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
        if saved {
            updateSavedRecording()
            try? context.save()
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
        try? context.save()
        savedRecording = recording
        saved = true
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
            try? context.save()
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
        livePreparationTask?.cancel()
        livePreparationTask = nil
        diarizationPreparationTask?.cancel()
        diarizationPreparationTask = nil
    }

    func retrySpeakerLabels(for recording: Recording) async {
        guard !recording.rawTranscription.isEmpty else {
            state = .failed("This older transcript does not contain the timing data needed to retry speaker labels.")
            return
        }
        audioURL = recording.audioURL
        rawTranscription = recording.rawTranscription
        finalSegments = recording.segments
        state = .processing("Identifying speakers")
        progress = 0.65
        if let diarization = await diarizationWithTimeout(recording.audioURL) {
            let merged = TranscriptMerger.merge(transcription: recording.rawTranscription, diarization: diarization)
            recording.segments = merged
            recording.diarizationNeedsRetry = false
            finalSegments = merged
            completionNote = nil
            diarizationNeedsRetry = false
            progress = 1
            state = .completed
        } else {
            completionNote = speakerLabelFailureMessage(saved: true)
            progress = 1
            state = .completed
        }
        diarizer = FluidDiarizationEngine()
    }

    func retryCurrentSpeakerLabels() async {
        guard let audioURL, !rawTranscription.isEmpty else { return }
        state = .processing("Identifying speakers")
        progress = 0.6
        if let diarization = await diarizationWithTimeout(audioURL) {
            finalSegments = TranscriptMerger.merge(transcription: rawTranscription, diarization: diarization)
            completionNote = nil
            diarizationNeedsRetry = false
        } else {
            completionNote = speakerLabelFailureMessage(saved: false)
            diarizationNeedsRetry = true
        }
        diarizer = FluidDiarizationEngine()
        savedRecording?.segments = finalSegments
        savedRecording?.diarizationNeedsRetry = diarizationNeedsRetry
        progress = 1
        state = .completed
    }

    private func processFile(_ url: URL) async throws {
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

        // Preserve the finished text before speaker labeling begins.
        finalSegments = TranscriptMerger.merge(transcription: transcription, diarization: [])
        savedRecording?.segments = finalSegments
        try? persistenceContext?.save()
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
        try? await Task.sleep(for: .seconds(1))
#else
        await unloadSelectedFinalModel()
#endif

        let diarization = await diarizationWithTimeout(url)
        diarizer = FluidDiarizationEngine()
        if let diarization {
            finalSegments = TranscriptMerger.merge(
                transcription: transcription,
                diarization: diarization
            )
            diarizationNeedsRetry = false
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
        try? context.save()
        savedRecording = recording
        saved = true
    }

    private func updateSavedRecording() {
        savedRecording?.segments = finalSegments
        savedRecording?.rawTranscription = rawTranscription
        savedRecording?.transcriptionNeedsRetry = state != .completed
        savedRecording?.diarizationNeedsRetry = diarizationNeedsRetry
        savedRecording?.finalTranscriptionModelID = selectedFinalModelID
        try? persistenceContext?.save()
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

    private func diarizationWithTimeout(_ url: URL) async -> [DiarizationSegment]? {
        await withCheckedContinuation { continuation in
            let gate = DiarizationResultGate(continuation: continuation)
            let activeDiarizer = diarizer

            Task {
                do {
                    let result = try await activeDiarizer.diarizeFile(url) { [weak self] value in
                        Task { await gate.reportProgress() }
                        Task { @MainActor in
                            self?.progress = 0.6 + min(max(value, 0), 1) * 0.35
                        }
                    }
                    await gate.finish(with: result)
                } catch {
                    await MainActor.run {
                        self.diarizationFailureDetail = error.localizedDescription
                    }
                    await gate.finish(with: nil)
                }
            }

            Task {
                while true {
                    try? await Task.sleep(for: .seconds(5))
                    if await gate.isFinished() { return }
                    if await gate.hasTimedOut() { break }
                }
                await MainActor.run {
                    self.diarizationFailureDetail = "Speaker labeling timed out while processing this recording."
                }
                await gate.finish(with: nil)
            }
        }
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
        liveTranscription.removeAll { existing in
            existing.startMs >= newSegment.startMs && existing.endMs <= newSegment.endMs
        }
        liveTranscription.append(newSegment)
        liveTranscription.sort { $0.startMs < $1.startMs }
    }
}

private actor DiarizationResultGate {
    private var continuation: CheckedContinuation<[DiarizationSegment]?, Never>?
    private let startedAt = Date.now
    private var lastProgressAt: Date?

    init(continuation: CheckedContinuation<[DiarizationSegment]?, Never>) {
        self.continuation = continuation
    }

    func finish(with result: [DiarizationSegment]?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }

    func reportProgress() {
        lastProgressAt = .now
    }

    func isFinished() -> Bool {
        continuation == nil
    }

    func hasTimedOut() -> Bool {
        guard continuation != nil else { return false }
        if let lastProgressAt {
            return Date.now.timeIntervalSince(lastProgressAt) >= 30
        }
        return Date.now.timeIntervalSince(startedAt) >= 120
    }
}
