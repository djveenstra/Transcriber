import Foundation

enum ModelStatus: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double, message: String)
    case downloaded
    case verifying
    case ready
    case missingOrCorrupt
    case failed(String)

    var label: String {
        switch self {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .downloaded: "Downloaded"
        case .verifying: "Verifying"
        case .ready: "Ready"
        case .missingOrCorrupt: "Missing or corrupt"
        case .failed: "Failed"
        }
    }

    var detail: String {
        switch self {
        case .notDownloaded:
            "Download before using offline."
        case let .downloading(progress, message):
            "\(progress.formatted(.percent.precision(.fractionLength(0)))) complete. \(message)"
        case .downloaded:
            "Files are on this device and waiting for verification."
        case .verifying:
            "Checking model files."
        case .ready:
            "Ready on this device."
        case .missingOrCorrupt:
            "Files are missing or incomplete. Repair will replace only this model cache."
        case let .failed(message):
            message
        }
    }
}

enum ModelDownloadSnapshot: Equatable, Sendable {
    case idle
    case downloading(modelID: String, progress: Double, message: String)
    case ready(modelID: String)
    case failed(modelID: String, message: String)
}

enum ModelVerificationSnapshot: Equatable, Sendable {
    case notChecked
    case verifying
    case ready
    case missingOrCorrupt
    case failed(String)
}

struct ModelFileSnapshot: Equatable, Sendable {
    var isPresent: Bool
    var hasCacheFootprint: Bool
    var wasPreviouslyDownloaded: Bool
    var sizeBytes: Int64?
}

struct ModelDescriptor: Identifiable, Sendable {
    let choice: FinalTranscriptionModelChoice
    let speedHint: String
    let accuracyHint: String
    let approximateSizeBytes: Int64?
    let cacheDirectory: URL?

    var id: String { choice.id }
    var provider: FinalTranscriptionProvider { choice.provider }
    var displayName: String { choice.name }
    var detail: String { choice.detail }
}

enum ModelRegistry {
    static let downloadedModelIDsKey = "modelRegistryDownloadedModelIDs"

    static var models: [ModelDescriptor] {
        FinalTranscriptionModelChoice.all.map(descriptor(for:))
    }

    static func descriptor(for choice: FinalTranscriptionModelChoice) -> ModelDescriptor {
        ModelDescriptor(
            choice: choice,
            speedHint: speedHint(for: choice),
            accuracyHint: accuracyHint(for: choice),
            approximateSizeBytes: TranscriptionModelReadiness.cacheSizeBytes(for: choice),
            cacheDirectory: TranscriptionModelReadiness.cacheDirectory(for: choice)
        )
    }

    static func status(
        for descriptor: ModelDescriptor,
        download: ModelDownloadSnapshot,
        file: ModelFileSnapshot,
        verification: ModelVerificationSnapshot
    ) -> ModelStatus {
        switch download {
        case let .downloading(modelID, progress, message) where modelID == descriptor.id:
            return .downloading(progress: progress, message: message)
        case let .failed(modelID, message) where modelID == descriptor.id:
            return .failed(message)
        default:
            break
        }

        guard file.isPresent else {
            return file.hasCacheFootprint || file.wasPreviouslyDownloaded ? .missingOrCorrupt : .notDownloaded
        }

        switch verification {
        case .notChecked:
            return .downloaded
        case .verifying:
            return .verifying
        case .ready:
            return .ready
        case .missingOrCorrupt:
            return .missingOrCorrupt
        case let .failed(message):
            return .failed(message)
        }
    }

    static func status(
        for descriptor: ModelDescriptor,
        download: ModelDownloadSnapshot,
        fileManager: FileManager = .default
    ) -> ModelStatus {
        let file = fileSnapshot(for: descriptor, fileManager: fileManager)
        return status(
            for: descriptor,
            download: download,
            file: file,
            verification: file.isPresent ? .ready : .notChecked
        )
    }

    static func fileSnapshot(
        for descriptor: ModelDescriptor,
        fileManager: FileManager = .default
    ) -> ModelFileSnapshot {
        ModelFileSnapshot(
            isPresent: TranscriptionModelReadiness.isPresent(descriptor.choice),
            hasCacheFootprint: TranscriptionModelReadiness.hasCacheFootprint(
                for: descriptor.choice,
                fileManager: fileManager
            ),
            wasPreviouslyDownloaded: wasPreviouslyDownloaded(descriptor.id),
            sizeBytes: TranscriptionModelReadiness.cacheSizeBytes(
                for: descriptor.choice,
                fileManager: fileManager
            )
        )
    }

    static func rememberDownloaded(_ modelID: String, defaults: UserDefaults = .standard) {
        var modelIDs = Set(defaults.stringArray(forKey: downloadedModelIDsKey) ?? [])
        modelIDs.insert(modelID)
        defaults.set(Array(modelIDs).sorted(), forKey: downloadedModelIDsKey)
    }

    static func wasPreviouslyDownloaded(_ modelID: String, defaults: UserDefaults = .standard) -> Bool {
        Set(defaults.stringArray(forKey: downloadedModelIDsKey) ?? []).contains(modelID)
    }

    static func formattedSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "Size not reported yet" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func speedHint(for choice: FinalTranscriptionModelChoice) -> String {
        switch choice.provider {
        case .whisper:
            let whisper = WhisperModelChoice.choice(for: choice.id)
            return whisper.recommendedForLive ? "Fast enough for live use" : "Slower, best for final transcripts"
        case .parakeet:
            if choice.id.contains("110m") {
                return "Small and fast"
            }
            return "Larger final-transcript model"
        }
    }

    private static func accuracyHint(for choice: FinalTranscriptionModelChoice) -> String {
        switch choice.provider {
        case .whisper:
            if choice.id.contains("medium") || choice.id.contains("large") {
                return "Higher accuracy"
            }
            return "Balanced accuracy"
        case .parakeet:
            if choice.id.contains("110m") {
                return "Good quick transcript"
            }
            return "Stronger final accuracy"
        }
    }
}
