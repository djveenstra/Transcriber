import Combine
import Foundation
import WhisperKit

struct WhisperModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let recommendedForLive: Bool

    nonisolated static let defaultID = "openai_whisper-base.en"
    nonisolated private static let previousDefaultID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private static let lightweightDefaultMigrationKey = "didMigrateToLightweightWhisperDefault"

    nonisolated static let all: [WhisperModelChoice] = [
        .init(
            id: defaultID,
            name: "Base English - Default",
            detail: "Default choice. Small, English-only, quick to load, and best for conserving storage.",
            recommendedForLive: true
        ),
        .init(
            id: "openai_whisper-small.en_217MB",
            name: "Small English - Balanced",
            detail: "English-only and compact. The best starting point for responsive live transcription.",
            recommendedForLive: true
        ),
        .init(
            id: "openai_whisper-medium.en",
            name: "Medium English - Detailed",
            detail: "Your preferred English model. More accurate than Small, but slower and heavier on iPhone.",
            recommendedForLive: false
        ),
        .init(
            id: "distil-whisper_distil-large-v3_594MB",
            name: "Distil Large v3 - Fast Accuracy",
            detail: "Strong English accuracy with faster processing than a full large model.",
            recommendedForLive: true
        ),
        .init(
            id: previousDefaultID,
            name: "Large v3 Turbo - High Accuracy",
            detail: "A heavier option with a strong balance of accuracy and speed on newer devices.",
            recommendedForLive: true
        ),
    ]

    nonisolated static func choice(for id: String) -> WhisperModelChoice {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID }!
    }

    nonisolated static func allowedID(_ id: String?) -> String {
        guard let id, all.contains(where: { $0.id == id }) else { return defaultID }
        return id
    }

    static func migrateToLightweightDefaultIfNeeded() -> String {
        let defaults = UserDefaults.standard
        let current = defaults.string(forKey: "whisperModel")
        guard !defaults.bool(forKey: lightweightDefaultMigrationKey) else {
            return allowedID(current)
        }

        let migrated = current == nil || current == previousDefaultID
            ? defaultID
            : allowedID(current)
        defaults.set(migrated, forKey: "whisperModel")
        defaults.set(true, forKey: lightweightDefaultMigrationKey)
        return migrated
    }
}

@MainActor
final class WhisperModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case ready
        case failed(String)
    }

    static let shared = WhisperModelDownloader()

    @Published private(set) var state: State = .idle
    @Published private(set) var modelID = ""
    @Published private(set) var downloadedModelIDs: Set<String>

    private init() {
        downloadedModelIDs = TranscriptionModelReadiness.reconciledWhisperHintIDs(
            modelIDs: WhisperModelChoice.all.map(\.id)
        )
    }

    func download(_ modelID: String) async {
        self.modelID = modelID
        state = .downloading(0)
        do {
            _ = try await WhisperKit.download(variant: modelID) { [weak self] progress in
                Task { @MainActor in
                    guard self?.modelID == modelID else { return }
                    self?.state = .downloading(progress.fractionCompleted)
                }
            }
            downloadedModelIDs = TranscriptionModelReadiness.reconciledWhisperHintIDs(
                modelIDs: WhisperModelChoice.all.map(\.id)
            )
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectionChanged(to modelID: String) {
        guard self.modelID != modelID else { return }
        self.modelID = modelID
        state = .idle
    }
}
