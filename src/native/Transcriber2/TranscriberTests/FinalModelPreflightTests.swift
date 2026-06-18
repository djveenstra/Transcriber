import Foundation
import Testing
@testable import Transcriber

struct FinalModelPreflightTests {
    private let selected = FinalTranscriptionModelChoice.choice(for: "openai_whisper-medium.en")
    private let fallback = FinalTranscriptionModelChoice.choice(for: FinalTranscriptionModelChoice.defaultID)

    @Test func verifySuccessUsesSelectedModel() async throws {
        let result = try await FinalModelPreflight.resolveModel(
            selected: selected,
            fallback: fallback
        ) { model in
            model.id == selected.id ? .ready : .failed("Fallback should not be checked.")
        }

        #expect(result.choice.id == selected.id)
        #expect(result.notice == nil)
    }

    @Test func verifyFailureFallsBackToDefaultWithNotice() async throws {
        let result = try await FinalModelPreflight.resolveModel(
            selected: selected,
            fallback: fallback
        ) { model in
            model.id == fallback.id ? .ready : .missingOrCorrupt
        }

        #expect(result.choice.id == fallback.id)
        #expect(result.notice?.contains(selected.name) == true)
        #expect(result.notice?.contains(fallback.name) == true)
    }

    @Test func verifyFailureThrowsWhenFallbackIsUnavailable() async {
        await #expect(throws: FinalModelPreflightError.self) {
            _ = try await FinalModelPreflight.resolveModel(
                selected: selected,
                fallback: fallback
            ) { _ in
                .missingOrCorrupt
            }
        }
    }
}
