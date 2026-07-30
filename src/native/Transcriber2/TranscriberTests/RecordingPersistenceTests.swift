import Foundation
import SwiftData
import Testing
@testable import Transcriber

@MainActor
struct RecordingPersistenceTests {
    private func makeRecording() -> Recording {
        Recording(
            title: "Corrupt",
            durationSeconds: 1,
            audioFileName: "recording.caf",
            segments: []
        )
    }

    @Test func corruptTranscriptDataDecodesToEmptySegments() {
        let recording = makeRecording()
        recording.transcriptData = Data("not json".utf8)

        #expect(recording.segments.isEmpty)
    }

    @Test func corruptRawTranscriptionDataDecodesToEmptyArray() {
        let recording = makeRecording()
        recording.rawTranscriptionData = Data("not json".utf8)

        #expect(recording.rawTranscription.isEmpty)
    }

    @Test func corruptSpeakerNamesDataDecodesToEmptyDictionary() {
        let recording = makeRecording()
        recording.speakerNamesData = Data("not json".utf8)

        #expect(recording.speakerNames.isEmpty)
    }

    @Test func segmentsRoundTripThroughSetterAndGetter() {
        let recording = makeRecording()
        let segments = [TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "S1", text: "Hello")]

        recording.segments = segments

        #expect(recording.segments == segments)
    }

    @Test func speakerNamesRoundTripThroughSetterAndGetter() {
        let recording = makeRecording()

        recording.speakerNames = ["SPEAKER_00": "Daniel"]

        #expect(recording.speakerNames == ["SPEAKER_00": "Daniel"])
    }

    @Test func rawTranscriptionRoundTripsThroughSetterAndGetter() {
        let recording = makeRecording()
        let raw = [TranscriptionSegment(startMs: 0, endMs: 1_000, text: "Hello")]

        recording.rawTranscription = raw

        #expect(recording.rawTranscription == raw)
    }

    @Test func optionalProcessingIdentitiesAreNilSafeAndRoundTrip() throws {
        let container = try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let legacy = makeRecording()
        context.insert(legacy)
        try context.save()
        #expect(legacy.processingRecordID == nil)
        #expect(legacy.sourceAudioID == nil)

        let recordingID = ArtifactStoreID()
        let sourceAudioID = ArtifactStoreID()
        legacy.processingRecordID = recordingID.rawValue
        legacy.sourceAudioID = sourceAudioID.rawValue
        try context.save()
        context.rollback()
        let fetched = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(fetched.processingRecordID == recordingID.rawValue)
        #expect(fetched.sourceAudioID == sourceAudioID.rawValue)
        #expect(fetched.audioFileName == "recording.caf")
    }

    @Test func genuinePreVX06SwiftDataStoreOpensWithNilOptionalIdentities() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/pre-vx06.store")
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("pre-vx06-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: temporary.path + "-shm")
            )
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: temporary.path + "-wal")
            )
        }
        try FileManager.default.copyItem(at: fixture, to: temporary)
        let configuration = ModelConfiguration(url: temporary, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Recording.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let recording = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(recording.title == "Pre-VX06 fixture")
        #expect(recording.audioFileName == "pre-vx06.caf")
        #expect(recording.processingRecordID == nil)
        #expect(recording.sourceAudioID == nil)
        #expect(recording.segments.first?.text == "preserved")
        #expect(recording.rawTranscription.first?.text == "preserved")
        #expect(recording.speakerNames == ["S1": "Speaker One"])
    }

    @Test func recoveryProjectsEveryRetryableTerminalStateAndIsIdempotent() throws {
        let recordingID = ArtifactStoreID()
        let sourceAudioID = ArtifactStoreID()
        let recording = makeRecording()
        recording.processingRecordID = recordingID.rawValue
        recording.sourceAudioID = sourceAudioID.rawValue
        let transcriptBefore = recording.transcriptData
        let states: [ProcessingJobState] = [.interrupted, .partial, .failed]
        let now = Date.now
        let jobs = states.map {
            ProcessingJobRecordV1(
                jobSchemaVersion: 1,
                jobID: ArtifactStoreID(),
                pipelineRunID: ArtifactStoreID(),
                attemptID: ArtifactStoreID(),
                recordingID: recordingID,
                sourceAudioID: sourceAudioID,
                requestedOperation: .fullProcessing,
                inputManifestGeneration: nil,
                inputCorrectionVersion: nil,
                stage: .identifyingSpeakers,
                state: $0,
                createdAt: now,
                updatedAt: now,
                startedAt: now,
                finishedAt: now,
                publishedOutputReferences: []
            )
        }
        var saves = 0

        try ProcessingJobRecoveryProjection.apply(jobs, to: [recording]) { saves += 1 }
        try ProcessingJobRecoveryProjection.apply(jobs, to: [recording]) { saves += 1 }

        #expect(recording.diarizationNeedsRetry)
        #expect(recording.transcriptData == transcriptBefore)
        #expect(saves == 2)
    }

    @Test func recoveryRequiresBothDurableIdentityValuesAndRetriesAfterSaveFailure() throws {
        let recordingID = ArtifactStoreID()
        let sourceAudioID = ArtifactStoreID()
        let recording = makeRecording()
        recording.processingRecordID = recordingID.rawValue
        recording.sourceAudioID = ArtifactStoreID().rawValue
        let now = Date.now
        let job = ProcessingJobRecordV1(
            jobSchemaVersion: 1,
            jobID: ArtifactStoreID(),
            pipelineRunID: ArtifactStoreID(),
            attemptID: ArtifactStoreID(),
            recordingID: recordingID,
            sourceAudioID: sourceAudioID,
            requestedOperation: .fullProcessing,
            inputManifestGeneration: nil,
            inputCorrectionVersion: nil,
            stage: .transcribing,
            state: .interrupted,
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            finishedAt: now,
            publishedOutputReferences: []
        )

        #expect(throws: (any Error).self) {
            try ProcessingJobRecoveryProjection.apply([job], to: [recording]) {}
        }
        recording.sourceAudioID = sourceAudioID.rawValue
        var failSave = true
        #expect(throws: (any Error).self) {
            try ProcessingJobRecoveryProjection.apply([job], to: [recording]) {
                if failSave {
                    throw ProcessingJobStoreError.invalidJob("forced save failure")
                }
            }
        }
        failSave = false
        try ProcessingJobRecoveryProjection.apply([job], to: [recording]) {}
        #expect(recording.transcriptionNeedsRetry)
    }
}
