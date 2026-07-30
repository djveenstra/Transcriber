import Foundation
import SwiftData
import Testing
@testable import Transcriber

private struct InjectedJobWriteFailure: Error {}

@MainActor
struct ProcessingJobStoreTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func optionalRecordingIdentitiesRoundTripAndRetryReusesThem() throws {
        let recording = makeRecording()
        #expect(recording.processingRecordID == nil)
        #expect(recording.sourceAudioID == nil)
        var saves = 0
        var durable: (String?, String?) = (nil, nil)
        let first = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            saves += 1
            durable = (recording.processingRecordID, recording.sourceAudioID)
        } reload: {
            durable
        }
        let second = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            saves += 1
            durable = (recording.processingRecordID, recording.sourceAudioID)
        } reload: {
            durable
        }
        #expect(first == second)
        #expect(saves == 1)
        #expect(recording.processingRecordID == first.recordingID.rawValue)
        #expect(recording.sourceAudioID == first.sourceAudioID.rawValue)
    }

    @Test func identitySaveFailureRestoresLegacyNilFieldsAndCreatesNoJobDirectory() throws {
        struct SaveFailure: Error {}
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let recording = makeRecording()
        #expect(throws: SaveFailure.self) {
            _ = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
                throw SaveFailure()
            } reload: {
                (recording.processingRecordID, recording.sourceAudioID)
            }
        }
        #expect(recording.processingRecordID == nil)
        #expect(recording.sourceAudioID == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.jobsRoot.path))
    }

    @Test func partialIdentityAdoptionPersistsMissingIDAndDurablyReloadsBoth() throws {
        let recording = makeRecording()
        let existing = ArtifactStoreID()
        recording.processingRecordID = existing.rawValue
        var durable: (String?, String?) = (existing.rawValue, nil)
        let identity = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            durable = (recording.processingRecordID, recording.sourceAudioID)
        } reload: {
            durable
        }
        #expect(identity.recordingID == existing)
        #expect(identity.sourceAudioID.rawValue == durable.1)
        let retry = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            Issue.record("Durably loaded IDs should not save again")
        } reload: {
            durable
        }
        #expect(retry == identity)
    }

    @Test func partialIdentityAdoptionReloadsThroughFreshFileBackedContext() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vx06-identity-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + "-shm")
            )
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + "-wal")
            )
        }
        let container = try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        )
        let savingContext = ModelContext(container)
        let recording = makeRecording()
        let existingRecordingID = ArtifactStoreID()
        recording.processingRecordID = existingRecordingID.rawValue
        savingContext.insert(recording)
        try savingContext.save()
        let persistentID = recording.persistentModelID
        var saves = 0

        let adopted = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            saves += 1
            try savingContext.save()
        } reload: {
            let freshContext = ModelContext(container)
            guard let reloaded = freshContext.model(for: persistentID) as? Recording else {
                return (nil, nil)
            }
            return (reloaded.processingRecordID, reloaded.sourceAudioID)
        }
        let retried = try RecordingProcessingIdentityAdoption.ensureSaved(for: recording) {
            saves += 1
            try savingContext.save()
        } reload: {
            let freshContext = ModelContext(container)
            guard let reloaded = freshContext.model(for: persistentID) as? Recording else {
                return (nil, nil)
            }
            return (reloaded.processingRecordID, reloaded.sourceAudioID)
        }

        #expect(adopted.recordingID == existingRecordingID)
        #expect(adopted.sourceAudioID == retried.sourceAudioID)
        #expect(adopted == retried)
        #expect(saves == 1)
    }

    @Test func allApprovedStatesRoundTripAtomically() async throws {
        for state in ProcessingJobState.allTestStates {
            let fixture = try makeFixture(publishedEvidenceValidator: { _ in true })
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let record = fixture.record
            try await fixture.store.create(record)
            if state != .queued {
                let firstState: ProcessingJobState = state == .cancelRequested || state == .failed
                    ? state
                    : .running
                _ = try await fixture.store.checkpoint(
                    jobID: record.jobID,
                    recordingID: record.recordingID,
                    expectedAttemptID: record.attemptID,
                    expectedInputManifestGeneration: record.inputManifestGeneration,
                    expectedCorrectionVersion: record.inputCorrectionVersion,
                    stage: firstState == .running ? .transcribing : .finished,
                    state: firstState,
                    publishedOutputReferences: [],
                    at: fixedDate.addingTimeInterval(1)
                )
                if firstState == .running, state != .running {
                    _ = try await fixture.store.checkpoint(
                        jobID: record.jobID,
                        recordingID: record.recordingID,
                        expectedAttemptID: record.attemptID,
                        expectedInputManifestGeneration: record.inputManifestGeneration,
                        expectedCorrectionVersion: record.inputCorrectionVersion,
                        stage: .finished,
                        state: state,
                        publishedOutputReferences: state == .succeeded
                            ? [fixture.outputReference]
                            : [],
                        at: fixedDate.addingTimeInterval(2)
                    )
                }
            }
            #expect(try await fixture.store.load(
                record.jobID,
                recordingID: record.recordingID
            ).state == state)
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.jobsRoot.path)
                .filter { $0.hasSuffix(".tmp") }.isEmpty)
        }
    }

    @Test func relaunchRecoveryIsHonestAndIdempotent() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        _ = try await fixture.store.checkpoint(
            jobID: fixture.record.jobID,
            recordingID: fixture.record.recordingID,
            expectedAttemptID: fixture.record.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .transcribing,
            state: .running
        )
        let first = try await fixture.store.reconcileAfterRelaunch()
        #expect(first.recoveredJobs == [fixture.locator])
        #expect(try await fixture.store.load(
            fixture.record.jobID,
            recordingID: fixture.record.recordingID
        ).state == .interrupted)
        let second = try await fixture.store.reconcileAfterRelaunch()
        #expect(second.recoveredJobs.isEmpty)
    }

    @Test func cancelRequestedAlsoRecoversAsInterrupted() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        _ = try await fixture.store.checkpoint(
            jobID: fixture.record.jobID,
            recordingID: fixture.record.recordingID,
            expectedAttemptID: fixture.record.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .identifyingSpeakers,
            state: .cancelRequested
        )
        _ = try await fixture.store.reconcileAfterRelaunch()
        #expect(try await fixture.store.load(
            fixture.record.jobID,
            recordingID: fixture.record.recordingID
        ).state == .interrupted)
    }

    @Test func staleAttemptInputAndCorrectionPreconditionsAreRejected() async throws {
        let fixture = try makeFixture(inputGeneration: 4, correctionVersion: 7)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        await #expect(throws: ProcessingJobStoreError.staleAttempt) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: ArtifactStoreID(),
                expectedInputManifestGeneration: 4,
                expectedCorrectionVersion: 7,
                stage: .transcribing,
                state: .running
            )
        }
        await #expect(throws: ProcessingJobStoreError.staleInputGeneration) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: fixture.record.attemptID,
                expectedInputManifestGeneration: 3,
                expectedCorrectionVersion: 7,
                stage: .transcribing,
                state: .running
            )
        }
        await #expect(throws: ProcessingJobStoreError.staleCorrectionVersion) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: fixture.record.attemptID,
                expectedInputManifestGeneration: 4,
                expectedCorrectionVersion: 6,
                stage: .transcribing,
                state: .running
            )
        }
    }

    @Test func successWithoutValidPublishedEvidenceIsRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        await #expect(throws: ProcessingJobStoreError.successWithoutPublishedEvidence) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: fixture.record.attemptID,
                expectedInputManifestGeneration: nil,
                expectedCorrectionVersion: nil,
                stage: .finished,
                state: .succeeded,
                publishedOutputReferences: [fixture.outputReference]
            )
        }
    }

    @Test func corruptAndUnknownFilesAreReportedWithoutBlockingOtherRecovery() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        try Data("{".utf8).write(to: fixture.jobsRoot.appendingPathComponent("corrupt.json"))
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.jobURL)) as? [String: Any]
        )
        object["job_schema_version"] = 99
        try JSONSerialization.data(withJSONObject: object).write(
            to: fixture.jobsRoot.appendingPathComponent("\(ArtifactStoreID().rawValue).json")
        )
        let report = try await fixture.store.reconcileAfterRelaunch()
        #expect(report.corruptFileNames.count == 2)
        #expect(try await fixture.store.load(
            fixture.record.jobID,
            recordingID: fixture.record.recordingID
        ) == fixture.record)
    }

    @Test func compatibilityProjectionPreservesTranscriptAndAudioFields() {
        let recording = makeRecording()
        let originalTranscript = recording.transcriptData
        let originalAudioName = recording.audioFileName
        let record = makeRecord(state: .interrupted, stage: .transcribing)
        ProcessingJobCompatibilityProjection.apply(record, to: recording)
        #expect(recording.transcriptionNeedsRetry)
        #expect(recording.transcriptData == originalTranscript)
        #expect(recording.audioFileName == originalAudioName)
    }

    @Test func jobsUsePerRecordingLayoutAndRejectCrossRecordingAndSymlinkEscape() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        #expect(FileManager.default.fileExists(atPath: fixture.jobURL.path))
        await #expect(throws: ProcessingJobStoreError.self) {
            _ = try await fixture.store.load(
                fixture.record.jobID,
                recordingID: ArtifactStoreID()
            )
        }

        let escaped = try makeFixture()
        defer { try? FileManager.default.removeItem(at: escaped.root) }
        let outside = escaped.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: escaped.jobsRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: escaped.jobsRoot,
            withDestinationURL: outside
        )
        await #expect(throws: ProcessingJobStoreError.self) {
            try await escaped.store.create(escaped.record)
        }
    }

    @Test func rejectsWholeStoreRootSymlinkEscapingApplicationSupportRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let processingArtifacts = fixture.root
            .appendingPathComponent("ProcessingArtifacts", isDirectory: true)
        let storeRoot = processingArtifacts
            .appendingPathComponent("store-v1", isDirectory: true)
        let outside = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("vx06-store-escape-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(
            at: processingArtifacts,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: storeRoot,
            withDestinationURL: outside
        )

        await #expect(throws: ProcessingJobStoreError.self) {
            try await fixture.store.create(fixture.record)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func stagesAreMonotonicAndTerminalJobsAreImmutable() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.store.create(fixture.record)
        _ = try await fixture.store.checkpoint(
            jobID: fixture.record.jobID,
            recordingID: fixture.record.recordingID,
            expectedAttemptID: fixture.record.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .transcribing,
            state: .running,
            at: fixedDate.addingTimeInterval(1)
        )
        await #expect(throws: ProcessingJobStoreError.self) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: fixture.record.attemptID,
                expectedInputManifestGeneration: nil,
                expectedCorrectionVersion: nil,
                stage: .preparingModel,
                state: .running
            )
        }
        _ = try await fixture.store.checkpoint(
            jobID: fixture.record.jobID,
            recordingID: fixture.record.recordingID,
            expectedAttemptID: fixture.record.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .finished,
            state: .partial,
            at: fixedDate.addingTimeInterval(2)
        )
        await #expect(throws: ProcessingJobStoreError.self) {
            _ = try await fixture.store.checkpoint(
                jobID: fixture.record.jobID,
                recordingID: fixture.record.recordingID,
                expectedAttemptID: fixture.record.attemptID,
                expectedInputManifestGeneration: nil,
                expectedCorrectionVersion: nil,
                stage: .finished,
                state: .failed
            )
        }
    }

    @Test func invalidTimestampCombinationsAreRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let invalid = ProcessingJobRecordV1(
            jobSchemaVersion: 1,
            jobID: ArtifactStoreID(),
            pipelineRunID: ArtifactStoreID(),
            attemptID: ArtifactStoreID(),
            recordingID: ArtifactStoreID(),
            sourceAudioID: ArtifactStoreID(),
            requestedOperation: .transcription,
            inputManifestGeneration: nil,
            inputCorrectionVersion: nil,
            stage: .queued,
            state: .queued,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            startedAt: fixedDate,
            finishedAt: nil,
            publishedOutputReferences: []
        )
        await #expect(throws: ProcessingJobStoreError.self) {
            try await fixture.store.create(invalid)
        }
    }

    @Test func createAndInitialCheckpointFailuresLeaveNoQueuedOrRunningFile() async throws {
        let createFailure = try makeFixture(
            beforeCreate: { _ in throw InjectedJobWriteFailure() }
        )
        defer { try? FileManager.default.removeItem(at: createFailure.root) }
        await #expect(throws: InjectedJobWriteFailure.self) {
            _ = try await createFailure.store.start(
                createFailure.record,
                stage: .savingRecording
            )
        }
        #expect(!FileManager.default.fileExists(atPath: createFailure.jobURL.path))

        let initialFailure = try makeFixture(
            beforeCheckpoint: {
                if $0.state == .running { throw InjectedJobWriteFailure() }
            }
        )
        defer { try? FileManager.default.removeItem(at: initialFailure.root) }
        await #expect(throws: InjectedJobWriteFailure.self) {
            _ = try await initialFailure.store.start(
                initialFailure.record,
                stage: .savingRecording
            )
        }
        #expect(!FileManager.default.fileExists(atPath: initialFailure.jobURL.path))
    }

    @Test func finalAndCancelCheckpointFailuresRemainExplicitlyRepairable() async throws {
        let finalFailure = try makeFixture(
            beforeCheckpoint: {
                if $0.state == .partial { throw InjectedJobWriteFailure() }
            }
        )
        defer { try? FileManager.default.removeItem(at: finalFailure.root) }
        let running = try await finalFailure.store.start(
            finalFailure.record,
            stage: .transcribing,
            at: fixedDate.addingTimeInterval(1)
        )
        await #expect(throws: InjectedJobWriteFailure.self) {
            _ = try await finalFailure.store.checkpoint(
                jobID: running.jobID,
                recordingID: running.recordingID,
                expectedAttemptID: running.attemptID,
                expectedInputManifestGeneration: nil,
                expectedCorrectionVersion: nil,
                stage: .finished,
                state: .partial
            )
        }
        _ = try await finalFailure.store.checkpoint(
            jobID: running.jobID,
            recordingID: running.recordingID,
            expectedAttemptID: running.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .transcribing,
            state: .interrupted
        )

        let cancelFailure = try makeFixture(
            beforeCheckpoint: {
                if $0.state == .cancelRequested { throw InjectedJobWriteFailure() }
            }
        )
        defer { try? FileManager.default.removeItem(at: cancelFailure.root) }
        let cancelRunning = try await cancelFailure.store.start(
            cancelFailure.record,
            stage: .transcribing,
            at: fixedDate.addingTimeInterval(1)
        )
        await #expect(throws: InjectedJobWriteFailure.self) {
            _ = try await cancelFailure.store.checkpoint(
                jobID: cancelRunning.jobID,
                recordingID: cancelRunning.recordingID,
                expectedAttemptID: cancelRunning.attemptID,
                expectedInputManifestGeneration: nil,
                expectedCorrectionVersion: nil,
                stage: .transcribing,
                state: .cancelRequested
            )
        }
        _ = try await cancelFailure.store.checkpoint(
            jobID: cancelRunning.jobID,
            recordingID: cancelRunning.recordingID,
            expectedAttemptID: cancelRunning.attemptID,
            expectedInputManifestGeneration: nil,
            expectedCorrectionVersion: nil,
            stage: .finished,
            state: .partial
        )
    }

    private func makeRecording() -> Recording {
        Recording(
            title: "Legacy",
            durationSeconds: 2,
            audioFileName: "legacy.caf",
            segments: [TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "S1", text: "kept")]
        )
    }

    private func makeRecord(
        state: ProcessingJobState = .queued,
        stage: ProcessingJobStage = .queued,
        inputGeneration: Int? = nil,
        correctionVersion: Int? = nil
    ) -> ProcessingJobRecordV1 {
        ProcessingJobRecordV1(
            jobSchemaVersion: 1,
            jobID: ArtifactStoreID(),
            pipelineRunID: ArtifactStoreID(),
            attemptID: ArtifactStoreID(),
            recordingID: ArtifactStoreID(),
            sourceAudioID: ArtifactStoreID(),
            requestedOperation: .fullProcessing,
            inputManifestGeneration: inputGeneration,
            inputCorrectionVersion: correctionVersion,
            stage: stage,
            state: state,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            startedAt: nil,
            finishedAt: nil,
            publishedOutputReferences: []
        )
    }

    private func makeFixture(
        inputGeneration: Int? = nil,
        correctionVersion: Int? = nil,
        publishedEvidenceValidator: @escaping ProcessingJobStore.PublishedEvidenceValidator = { _ in false },
        beforeCreate: @escaping ProcessingJobStore.MutationHook = { _ in },
        beforeCheckpoint: @escaping ProcessingJobStore.MutationHook = { _ in }
    ) throws -> JobFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vx06-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = makeRecord(
            inputGeneration: inputGeneration,
            correctionVersion: correctionVersion
        )
        return JobFixture(
            root: root,
            store: ProcessingJobStore(
                applicationSupportRoot: root,
                publishedEvidenceValidator: publishedEvidenceValidator,
                beforeCreate: beforeCreate,
                beforeCheckpoint: beforeCheckpoint
            ),
            record: record
        )
    }
}

private struct JobFixture {
    let root: URL
    let store: ProcessingJobStore
    let record: ProcessingJobRecordV1

    var jobsRoot: URL {
        root.appendingPathComponent(
            "ProcessingArtifacts/store-v1/recordings/\(record.recordingID.rawValue)/jobs",
            isDirectory: true
        )
    }

    var jobURL: URL {
        jobsRoot.appendingPathComponent("\(record.jobID.rawValue).json")
    }

    var outputReference: ProcessingArtifactReferenceV1 {
        ProcessingArtifactReferenceV1(
            artifactID: ArtifactStoreID(),
            artifactKind: .transcription,
            recordingID: record.recordingID,
            envelopeRelativePath:
                "recordings/\(record.recordingID.rawValue)/artifacts/\(ArtifactStoreID().rawValue)/envelope.json"
        )
    }

    var locator: ProcessingJobLocator {
        ProcessingJobLocator(recordingID: record.recordingID, jobID: record.jobID)
    }
}

private extension ProcessingJobState {
    static let allTestStates: [ProcessingJobState] = [
        .queued, .running, .cancelRequested, .interrupted, .partial, .failed, .succeeded,
    ]
}
