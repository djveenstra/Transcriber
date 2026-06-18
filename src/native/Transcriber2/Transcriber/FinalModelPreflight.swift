import Foundation

struct FinalModelPreflightResult: Equatable, Sendable {
    let choice: FinalTranscriptionModelChoice
    let notice: String?
}

enum FinalModelPreflightError: LocalizedError, Equatable {
    case unavailable(modelName: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(modelName, reason):
            return "\(modelName) is not ready for transcription. \(reason)"
        }
    }
}

enum FinalModelPreflight {
    static func resolveModel(
        selected: FinalTranscriptionModelChoice,
        fallback: FinalTranscriptionModelChoice,
        verify: @Sendable (FinalTranscriptionModelChoice) async -> ModelVerificationSnapshot
    ) async throws -> FinalModelPreflightResult {
        let selectedVerification = await verify(selected)
        if selectedVerification.isReadyForProcessing {
            return FinalModelPreflightResult(choice: selected, notice: nil)
        }

        guard selected.id != fallback.id else {
            throw FinalModelPreflightError.unavailable(
                modelName: selected.name,
                reason: selectedVerification.failureDescription
            )
        }

        let fallbackVerification = await verify(fallback)
        guard fallbackVerification.isReadyForProcessing else {
            throw FinalModelPreflightError.unavailable(
                modelName: selected.name,
                reason: "The selected model was unavailable, and the default fallback could not be prepared. \(fallbackVerification.failureDescription)"
            )
        }

        return FinalModelPreflightResult(
            choice: fallback,
            notice: "The selected model \(selected.name) was not ready, so this transcript used \(fallback.name). Open Settings to repair or redownload \(selected.name)."
        )
    }
}

private extension ModelVerificationSnapshot {
    var isReadyForProcessing: Bool {
        if case .ready = self { return true }
        return false
    }

    var failureDescription: String {
        switch self {
        case .notChecked:
            return "The model could not be checked."
        case .verifying:
            return "The model is still being checked."
        case .ready:
            return "The model is ready."
        case .missingOrCorrupt:
            return "Its files are missing or incomplete."
        case let .failed(message):
            return message
        }
    }
}
