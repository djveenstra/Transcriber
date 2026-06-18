import Combine
import FluidAudio
import Foundation

enum FinalTranscriptionProvider: String, Codable, Sendable {
    case whisper
    case parakeet
}

struct FinalTranscriptionModelChoice: Identifiable, Sendable {
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
        switch provider {
        case .whisper:
            // WhisperKit does not expose a stable public cache check. The downloader tracks
            // confirmed downloads during this app session and transcription can still load it.
            return WhisperModelDownloader.shared.downloadedModelIDs.contains(id)
        case .parakeet:
            guard let parakeetVersion else { return false }
            let directory = AsrModels.defaultCacheDirectory(for: parakeetVersion)
            return AsrModels.modelsExist(at: directory, version: parakeetVersion)
        }
    }
}

@MainActor
final class FinalModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(String, Double, String)
        case ready(String)
        case failed(String, String)
    }

    static let shared = FinalModelDownloader()

    @Published private(set) var state: State = .idle

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
            state = .ready(model.id)
        } catch {
            state = .failed(model.id, error.localizedDescription)
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
