import Foundation

nonisolated struct RecordingProcessingIdentity: Equatable, Sendable {
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
}

@MainActor
enum RecordingProcessingIdentityAdoption {
    static func ensureSaved(
        for recording: Recording,
        save: () throws -> Void,
        reload: () throws -> (recordingID: String?, sourceAudioID: String?)
    ) throws -> RecordingProcessingIdentity {
        let originalRecordingID = recording.processingRecordID
        let originalSourceAudioID = recording.sourceAudioID
        let recordingID = try originalRecordingID.map(ArtifactStoreID.init(rawValue:))
            ?? ArtifactStoreID()
        let sourceAudioID = try originalSourceAudioID.map(ArtifactStoreID.init(rawValue:))
            ?? ArtifactStoreID()

        guard originalRecordingID == nil || originalRecordingID == recordingID.rawValue,
              originalSourceAudioID == nil || originalSourceAudioID == sourceAudioID.rawValue else {
            throw ProcessingJobStoreError.invalidJob("Recording identity changed")
        }
        if originalRecordingID == nil || originalSourceAudioID == nil {
            recording.processingRecordID = recordingID.rawValue
            recording.sourceAudioID = sourceAudioID.rawValue
            do {
                try save()
            } catch {
                recording.processingRecordID = originalRecordingID
                recording.sourceAudioID = originalSourceAudioID
                throw error
            }
        }
        let durable = try reload()
        guard durable.recordingID == recordingID.rawValue,
              durable.sourceAudioID == sourceAudioID.rawValue else {
            throw ProcessingJobStoreError.invalidJob("Saved identity could not be re-read")
        }
        return RecordingProcessingIdentity(
            recordingID: recordingID,
            sourceAudioID: sourceAudioID
        )
    }
}

@MainActor
enum ProcessingJobCompatibilityProjection {
    static func apply(_ job: ProcessingJobRecordV1, to recording: Recording) {
        switch job.state {
        case .interrupted, .failed:
            if job.stage == .identifyingSpeakers || job.stage == .savingSpeakerLabels {
                recording.diarizationNeedsRetry = true
            } else {
                recording.transcriptionNeedsRetry = true
            }
        case .partial:
            if job.stage == .identifyingSpeakers || job.stage == .savingSpeakerLabels {
                recording.diarizationNeedsRetry = true
            }
        case .queued, .running, .cancelRequested, .succeeded:
            break
        }
    }
}

@MainActor
enum ProcessingJobRecoveryProjection {
    static func apply(
        _ jobs: [ProcessingJobRecordV1],
        to recordings: [Recording],
        save: () throws -> Void
    ) throws {
        for job in jobs {
            guard let recording = recordings.first(where: {
                $0.processingRecordID == job.recordingID.rawValue
                    && $0.sourceAudioID == job.sourceAudioID.rawValue
            }) else {
                throw ProcessingJobStoreError.invalidJob(
                    "A recovered job could not be matched to its recording"
                )
            }
            ProcessingJobCompatibilityProjection.apply(job, to: recording)
        }
        try save()
    }
}
