import Combine
import FluidAudio
import Foundation

enum FinalTranscriptionProvider: String, Codable, Sendable {
    case whisper
    case parakeet
}

struct FinalTranscriptionModelChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let provider: FinalTranscriptionProvider
    let parakeetVersion: AsrModelVersion?

    static let defaultID = WhisperModelChoice.defaultID
    private static let selectionKey = "finalTranscriptionModel"

    static let parakeet: [FinalTranscriptionModelChoice] = [
        .init(
            id: "parakeet-tdt-ctc-110m",
            name: "Parakeet 110M - Lightweight",
            detail: "Small and fast. A strong candidate for quick final transcripts on iPhone.",
            provider: .parakeet,
            parakeetVersion: .tdtCtc110m
        ),
        .init(
            id: "parakeet-tdt-v2",
            name: "Parakeet v2 - English Accuracy",
            detail: "A larger English-only model intended for the strongest Parakeet accuracy.",
            provider: .parakeet,
            parakeetVersion: .v2
        ),
        .init(
            id: "parakeet-tdt-v3",
            name: "Parakeet v3 - Fast Large",
            detail: "A larger, high-throughput Parakeet model. English is used in this app.",
            provider: .parakeet,
            parakeetVersion: .v3
        ),
    ]

    static let whisper: [FinalTranscriptionModelChoice] = WhisperModelChoice.all.map {
        .init(id: $0.id, name: $0.name, detail: $0.detail, provider: .whisper, parakeetVersion: nil)
    }

    static let all = parakeet + whisper

    static func choice(for id: String?) -> FinalTranscriptionModelChoice {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID }!
    }

    static func selectedID() -> String {
#if os(iOS)
        let defaults = UserDefaults.standard
        if let selected = defaults.string(forKey: selectionKey), all.contains(where: { $0.id == selected }) {
            return selected
        }
        let migrated = WhisperModelChoice.allowedID(defaults.string(forKey: "whisperModel"))
        defaults.set(migrated, forKey: selectionKey)
        return migrated
#else
        return WhisperModelChoice.allowedID(UserDefaults.standard.string(forKey: "whisperModel"))
#endif
    }

    static func setSelectedID(_ id: String) {
        guard all.contains(where: { $0.id == id }) else { return }
#if os(iOS)
        UserDefaults.standard.set(id, forKey: selectionKey)
#else
        if choice(for: id).provider == .whisper {
            UserDefaults.standard.set(id, forKey: "whisperModel")
        }
#endif
    }

    var isDownloaded: Bool {
        TranscriptionModelReadiness.isPresent(self)
    }
}

@MainActor
final class FinalModelDownloader: ObservableObject {
    enum State: Equatable, Sendable {
        case idle
        case downloading(String, Double, String)
        case ready(String)
        case failed(String, String)
    }

    static let shared = FinalModelDownloader()

    @Published private(set) var state: State = .idle
    private var defaultPreloadTask: Task<Void, Never>?

    func download(_ model: FinalTranscriptionModelChoice) async {
        state = .downloading(model.id, 0, Self.initialStatus(for: model))
        do {
            switch model.provider {
            case .whisper:
                await WhisperModelDownloader.shared.download(model.id)
                if case let .failed(message) = WhisperModelDownloader.shared.state {
                    throw FinalModelDownloadError.failed(message)
                }
            case .parakeet:
                guard let version = model.parakeetVersion else { throw FinalModelDownloadError.invalidModel }
                _ = try await AsrModels.download(version: version) { [weak self] progress in
                    let status = Self.status(for: model, progress: progress)
                    Task { @MainActor in
                        self?.state = .downloading(model.id, progress.fractionCompleted, status)
                    }
                }
            }
            ModelRegistry.rememberDownloaded(model.id)
            state = .ready(model.id)
        } catch {
            state = .failed(model.id, error.localizedDescription)
        }
    }

    func repair(_ model: FinalTranscriptionModelChoice) async {
        state = .downloading(model.id, 0, "Repairing model files.")
        do {
            try TranscriptionModelReadiness.removeCache(for: model)
            await download(model)
        } catch {
            state = .failed(model.id, error.localizedDescription)
        }
    }

    func redownload(_ model: FinalTranscriptionModelChoice) async {
        await repair(model)
    }

    func scheduleDefaultPreloadIfNeeded() {
        guard defaultPreloadTask == nil else { return }
        let model = FinalTranscriptionModelChoice.choice(for: FinalTranscriptionModelChoice.defaultID)
        let descriptor = ModelRegistry.descriptor(for: model)
        let file = ModelRegistry.fileSnapshot(for: descriptor, includeSize: false)
        guard ModelRegistry.shouldPreloadDefaultModel(file: file, download: downloadSnapshot) else { return }

        defaultPreloadTask = Task { [weak self] in
            guard let self else { return }
            await self.download(model)
            self.defaultPreloadTask = nil
        }
    }

    func refreshFileStatus() {
        _ = ModelRegistry.refreshFileStatusHints(download: downloadSnapshot)
    }

    private var downloadSnapshot: ModelDownloadSnapshot {
        switch state {
        case .idle:
            return .idle
        case let .downloading(id, progress, message):
            return .downloading(modelID: id, progress: progress, message: message)
        case let .ready(id):
            return .ready(modelID: id)
        case let .failed(id, message):
            return .failed(modelID: id, message: message)
        }
    }

    nonisolated private static func initialStatus(for model: FinalTranscriptionModelChoice) -> String {
        switch model.provider {
        case .whisper:
            return "Starting download."
        case .parakeet:
            if model.parakeetVersion == .v3 {
                return "Starting a large download, about 461 MB."
            }
            return "Starting Parakeet model download."
        }
    }

    nonisolated private static func status(
        for model: FinalTranscriptionModelChoice,
        progress: DownloadUtils.DownloadProgress
    ) -> String {
        switch progress.phase {
        case .listing:
            return "Checking the model files to download."
        case let .downloading(completedFiles, totalFiles):
            let fileText = totalFiles > 0
                ? "File \(min(completedFiles + 1, totalFiles)) of \(totalFiles)."
                : "Downloading model files."
            if model.parakeetVersion == .v3 {
                let approximateDownloaded = Int((progress.fractionCompleted / 0.5 * 461).rounded())
                let clamped = max(0, min(461, approximateDownloaded))
                return "\(fileText) About \(clamped) of 461 MB downloaded."
            }
            return fileText
        case let .compiling(modelName):
            if modelName.isEmpty {
                return "Finishing model setup."
            }
            return "Preparing \(modelName) for this device."
        }
    }
}

private enum FinalModelDownloadError: LocalizedError {
    case invalidModel
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel: "The selected model is not valid."
        case let .failed(message): message
        }
    }
}

@MainActor
final class LaunchModelReadiness: ObservableObject {
    enum State: Equatable, Sendable {
        case idle
        case preparingLivePreview
        case livePreviewReady
        case failed(String)
    }

    static let shared = LaunchModelReadiness()

    @Published private(set) var state: State = .idle

    private let prepareLivePreview: () async throws -> Void
    private let prepareDefaultModel: () -> Void
    private var preparationTask: Task<Void, Never>?

    init(
        prepareLivePreview: @escaping @MainActor () async throws -> Void = {
            let engine = WhisperKitTranscriptionEngine()
            try await engine.prepare()
            await engine.unload()
        },
        prepareDefaultModel: @escaping @MainActor () -> Void = {
            FinalModelDownloader.shared.scheduleDefaultPreloadIfNeeded()
        }
    ) {
        self.prepareLivePreview = prepareLivePreview
        self.prepareDefaultModel = prepareDefaultModel
    }

    func startIfNeeded() {
        start(forceRetry: false)
    }

    func retry() {
        start(forceRetry: true)
    }

    func waitForLivePreviewAttempt() async {
        startIfNeeded()
        await preparationTask?.value
    }

    private func start(forceRetry: Bool) {
        guard preparationTask == nil else { return }
        if !forceRetry, state == .livePreviewReady { return }

        state = .preparingLivePreview
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await prepareLivePreview()
                state = .livePreviewReady
                prepareDefaultModel()
            } catch {
                state = .failed(error.localizedDescription)
            }

            // A failed high-priority Live Preview attempt remains retryable and
            // does not race a lower-priority preload. Default preload begins only
            // after Live Preview preparation succeeds.
            preparationTask = nil
        }
    }
}
