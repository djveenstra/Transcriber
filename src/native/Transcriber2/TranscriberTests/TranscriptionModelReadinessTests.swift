import Foundation
import Testing
@testable import Transcriber

@Suite(.serialized)
struct TranscriptionModelReadinessTests {
    @Test func whisperModelIsPresentWhenRequiredCompiledModelsExist() throws {
        let fixture = try WhisperFixture()
        try fixture.createCompiledModel(named: "MelSpectrogram")
        try fixture.createCompiledModel(named: "AudioEncoder")
        try fixture.createCompiledModel(named: "TextDecoder")

        let isPresent = TranscriptionModelReadiness.isWhisperModelPresent(
            fixture.modelID,
            cacheRoot: fixture.cacheRoot,
            fileManager: fixture.fileManager,
            defaults: fixture.defaults
        )

        #expect(isPresent)
    }

    @Test func whisperModelIsMissingWhenAnyRequiredModelIsAbsent() throws {
        let fixture = try WhisperFixture()
        try fixture.createCompiledModel(named: "MelSpectrogram")
        try fixture.createCompiledModel(named: "AudioEncoder")

        let isPresent = TranscriptionModelReadiness.isWhisperModelPresent(
            fixture.modelID,
            cacheRoot: fixture.cacheRoot,
            fileManager: fixture.fileManager,
            defaults: fixture.defaults
        )

        #expect(!isPresent)
    }

    @Test func whisperModelAcceptsPackagedCoreMLFiles() throws {
        let fixture = try WhisperFixture()
        try fixture.createPackagedModel(named: "MelSpectrogram")
        try fixture.createPackagedModel(named: "AudioEncoder")
        try fixture.createPackagedModel(named: "TextDecoder")

        let isPresent = TranscriptionModelReadiness.isWhisperModelPresent(
            fixture.modelID,
            cacheRoot: fixture.cacheRoot,
            fileManager: fixture.fileManager,
            defaults: fixture.defaults
        )

        #expect(isPresent)
    }

    @Test func whisperDownloadedHintIsReconciledAgainstFiles() throws {
        let fixture = try WhisperFixture()
        fixture.defaults.set([fixture.modelID], forKey: TranscriptionModelReadiness.whisperDownloadedModelsKey)

        let isPresent = TranscriptionModelReadiness.isWhisperModelPresent(
            fixture.modelID,
            cacheRoot: fixture.cacheRoot,
            fileManager: fixture.fileManager,
            reconcileHint: true,
            defaults: fixture.defaults
        )

        #expect(!isPresent)
        #expect(fixture.defaults.stringArray(forKey: TranscriptionModelReadiness.whisperDownloadedModelsKey) == [])
    }

    private struct WhisperFixture {
        let modelID = WhisperModelChoice.defaultID
        let cacheRoot: URL
        let modelDirectory: URL
        let fileManager: FileManager
        let defaults: UserDefaults

        init() throws {
            fileManager = .default
            cacheRoot = fileManager.temporaryDirectory
                .appendingPathComponent("TranscriptionModelReadinessTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            modelDirectory = cacheRoot.appendingPathComponent(modelID, isDirectory: true)
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

            let suiteName = "TranscriptionModelReadinessTests-\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
        }

        func createCompiledModel(named name: String) throws {
            try fileManager.createDirectory(
                at: modelDirectory.appendingPathComponent("\(name).mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        func createPackagedModel(named name: String) throws {
            let packageModel = modelDirectory
                .appendingPathComponent("\(name).mlpackage", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("com.apple.CoreML", isDirectory: true)
            try fileManager.createDirectory(at: packageModel, withIntermediateDirectories: true)
            _ = fileManager.createFile(
                atPath: packageModel.appendingPathComponent("model.mlmodel").path,
                contents: Data()
            )
        }
    }
}
