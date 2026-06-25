import Foundation
import Testing
@testable import Transcriber

@Suite(.serialized)
struct ModelRegistryTests {
    private let descriptor = ModelRegistry.descriptor(
        for: FinalTranscriptionModelChoice.choice(for: WhisperModelChoice.defaultID)
    )

    @Test func lifecycleStatusCoversRequiredStateSet() {
        let missing = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: false,
            wasPreviouslyDownloaded: false,
            sizeBytes: nil
        )
        let partial = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: false,
            sizeBytes: 1024
        )
        let removedAfterDownload = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: false,
            wasPreviouslyDownloaded: true,
            sizeBytes: nil
        )
        let present = ModelFileSnapshot(
            isPresent: true,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: true,
            sizeBytes: 2048
        )

        #expect(status(file: missing, verification: .notChecked) == .notDownloaded)
        #expect(status(file: missing, download: .downloading(modelID: descriptor.id, progress: 0.4, message: "Loading files.")) == .downloading(progress: 0.4, message: "Loading files."))
        #expect(status(file: present, verification: .notChecked) == .downloaded)
        #expect(status(file: present, verification: .verifying) == .verifying)
        #expect(status(file: present, verification: .ready) == .ready)
        #expect(status(file: partial, verification: .notChecked) == .missingOrCorrupt)
        #expect(status(file: removedAfterDownload, verification: .notChecked) == .missingOrCorrupt)
        #expect(status(file: present, download: .failed(modelID: descriptor.id, message: "Network failed.")) == .failed("Network failed."))
    }

    @Test func downloadStateForOtherModelDoesNotOverrideThisModel() {
        let present = ModelFileSnapshot(
            isPresent: true,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: true,
            sizeBytes: 2048
        )

        let status = ModelRegistry.status(
            for: descriptor,
            download: .downloading(modelID: "different-model", progress: 0.5, message: "Downloading."),
            file: present,
            verification: .ready
        )

        #expect(status == .ready)
    }

    @Test func removingWhisperCacheLeavesSiblingUserDataUntouched() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ModelRegistryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheRoot = root.appendingPathComponent("ModelCache", isDirectory: true)
        let modelDirectory = TranscriptionModelReadiness.whisperCacheDirectory(
            for: descriptor.id,
            cacheRoot: cacheRoot
        )
        let recordingsDirectory = root.appendingPathComponent("Recordings", isDirectory: true)
        let transcriptFile = root.appendingPathComponent("transcript.json")

        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        _ = fileManager.createFile(atPath: modelDirectory.appendingPathComponent("partial.bin").path, contents: Data([1]))
        _ = fileManager.createFile(atPath: recordingsDirectory.appendingPathComponent("audio.caf").path, contents: Data([2]))
        _ = fileManager.createFile(atPath: transcriptFile.path, contents: Data([3]))

        let suiteName = "ModelRegistryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set([descriptor.id], forKey: TranscriptionModelReadiness.whisperDownloadedModelsKey)

        try TranscriptionModelReadiness.removeWhisperCache(
            modelID: descriptor.id,
            cacheRoot: cacheRoot,
            fileManager: fileManager,
            defaults: defaults
        )

        #expect(!fileManager.fileExists(atPath: modelDirectory.path))
        #expect(fileManager.fileExists(atPath: recordingsDirectory.appendingPathComponent("audio.caf").path))
        #expect(fileManager.fileExists(atPath: transcriptFile.path))
        #expect(defaults.stringArray(forKey: TranscriptionModelReadiness.whisperDownloadedModelsKey) == [])

        try? fileManager.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func registryRemembersDownloadedModelsWithoutClaimingReadiness() throws {
        let suiteName = "ModelRegistryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        #expect(!ModelRegistry.wasPreviouslyDownloaded(descriptor.id, defaults: defaults))

        ModelRegistry.rememberDownloaded(descriptor.id, defaults: defaults)

        #expect(ModelRegistry.wasPreviouslyDownloaded(descriptor.id, defaults: defaults))

        let missingKnownModel = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: false,
            wasPreviouslyDownloaded: ModelRegistry.wasPreviouslyDownloaded(descriptor.id, defaults: defaults),
            sizeBytes: nil
        )
        #expect(status(file: missingKnownModel, verification: .notChecked) == .missingOrCorrupt)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func refreshedStatusesUseLatestFileSnapshots() {
        let present = ModelFileSnapshot(
            isPresent: true,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: true,
            sizeBytes: nil
        )
        let missingKnownModel = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: false,
            wasPreviouslyDownloaded: true,
            sizeBytes: nil
        )

        var statuses = ModelRegistry.statuses(
            for: [descriptor],
            download: .idle,
            fileSnapshots: [descriptor.id: present]
        )
        #expect(statuses[descriptor.id] == .ready)

        statuses = ModelRegistry.statuses(
            for: [descriptor],
            download: .idle,
            fileSnapshots: [descriptor.id: missingKnownModel]
        )
        #expect(statuses[descriptor.id] == .missingOrCorrupt)
    }

    @Test func defaultPreloadOnlyStartsWhenDefaultIsMissingAndIdle() {
        let missing = ModelFileSnapshot(
            isPresent: false,
            hasCacheFootprint: false,
            wasPreviouslyDownloaded: false,
            sizeBytes: nil
        )
        let present = ModelFileSnapshot(
            isPresent: true,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: true,
            sizeBytes: nil
        )

        #expect(ModelRegistry.shouldPreloadDefaultModel(file: missing, download: .idle))
        #expect(!ModelRegistry.shouldPreloadDefaultModel(file: present, download: .idle))
        #expect(!ModelRegistry.shouldPreloadDefaultModel(
            file: missing,
            download: .downloading(modelID: descriptor.id, progress: 0.2, message: "Downloading.")
        ))
    }

    private func status(
        file: ModelFileSnapshot,
        download: ModelDownloadSnapshot = .idle,
        verification: ModelVerificationSnapshot = .ready
    ) -> ModelStatus {
        ModelRegistry.status(
            for: descriptor,
            download: download,
            file: file,
            verification: verification
        )
    }
}

@MainActor
struct LaunchModelReadinessTests {
    private enum TestFailure: Error {
        case expected
    }

    @Test func launchReadinessPreparesLivePreviewBeforeDefaultModel() async {
        var events: [String] = []
        let readiness = LaunchModelReadiness(
            prepareLivePreview: {
                events.append("live-preview")
            },
            prepareDefaultModel: {
                events.append("default-model")
            }
        )

        await readiness.waitForLivePreviewAttempt()

        #expect(events == ["live-preview", "default-model"])
        #expect(readiness.state == .livePreviewReady)
    }

    @Test func failedLaunchReadinessCanRetry() async {
        var shouldFail = true
        var attempts = 0
        var defaultModelStarts = 0
        let readiness = LaunchModelReadiness(
            prepareLivePreview: {
                attempts += 1
                if shouldFail {
                    throw TestFailure.expected
                }
            },
            prepareDefaultModel: {
                defaultModelStarts += 1
            }
        )

        await readiness.waitForLivePreviewAttempt()
        guard case .failed = readiness.state else {
            Issue.record("Expected launch readiness to report a retryable failure")
            return
        }
        #expect(defaultModelStarts == 0)

        shouldFail = false
        readiness.retry()
        await readiness.waitForLivePreviewAttempt()

        #expect(attempts == 2)
        #expect(readiness.state == .livePreviewReady)
        #expect(defaultModelStarts == 1)
    }
}
