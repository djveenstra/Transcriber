import Foundation
import Testing
@testable import Transcriber

@Suite(.serialized)
struct WhisperModelChoiceTests {
    private static let modelKey = "whisperModel"
    private static let migrationKey = "didMigrateToLightweightWhisperDefault"
    private static let previousDefaultID = "openai_whisper-large-v3-v20240930_turbo_632MB"

    @Test func allowedIDFallsBackToDefaultForUnknownOrMissingModel() {
        #expect(WhisperModelChoice.allowedID("not-a-real-model") == WhisperModelChoice.defaultID)
        #expect(WhisperModelChoice.allowedID(nil) == WhisperModelChoice.defaultID)
    }

    @Test func allowedIDPassesThroughKnownModel() {
        let known = WhisperModelChoice.all[1].id
        #expect(WhisperModelChoice.allowedID(known) == known)
    }

    @Test func migrationMovesPreviousDefaultToLightweightDefault() {
        withRestoredDefaults {
            let defaults = UserDefaults.standard
            defaults.set(Self.previousDefaultID, forKey: Self.modelKey)
            defaults.set(false, forKey: Self.migrationKey)

            let migrated = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()

            #expect(migrated == WhisperModelChoice.defaultID)
            #expect(defaults.string(forKey: Self.modelKey) == WhisperModelChoice.defaultID)
            #expect(defaults.bool(forKey: Self.migrationKey))
        }
    }

    @Test func migrationLeavesOtherModelChoicesAloneOnFirstRun() {
        withRestoredDefaults {
            let defaults = UserDefaults.standard
            let chosenModel = WhisperModelChoice.all[1].id
            defaults.set(chosenModel, forKey: Self.modelKey)
            defaults.set(false, forKey: Self.migrationKey)

            let migrated = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()

            #expect(migrated == chosenModel)
            #expect(defaults.string(forKey: Self.modelKey) == chosenModel)
            #expect(defaults.bool(forKey: Self.migrationKey))
        }
    }

    @Test func migrationIsNoOpAfterItHasAlreadyRun() {
        withRestoredDefaults {
            let defaults = UserDefaults.standard
            defaults.set(Self.previousDefaultID, forKey: Self.modelKey)
            defaults.set(true, forKey: Self.migrationKey)

            let migrated = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()

            #expect(migrated == Self.previousDefaultID)
            #expect(defaults.string(forKey: Self.modelKey) == Self.previousDefaultID)
        }
    }

    private func withRestoredDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previousModel = defaults.string(forKey: Self.modelKey)
        let previousMigrationFlag = defaults.bool(forKey: Self.migrationKey)
        defer {
            if let previousModel {
                defaults.set(previousModel, forKey: Self.modelKey)
            } else {
                defaults.removeObject(forKey: Self.modelKey)
            }
            defaults.set(previousMigrationFlag, forKey: Self.migrationKey)
        }
        body()
    }
}
