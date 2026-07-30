import Darwin
import Foundation

nonisolated enum ProcessingJobStoreError: Error, Equatable, Sendable {
    case invalidJob(String)
    case corruptJob(String)
    case unknownSchemaVersion(Int)
    case staleAttempt
    case staleInputGeneration
    case staleCorrectionVersion
    case successWithoutPublishedEvidence
}

nonisolated enum ProcessingJobOperation: String, Codable, Sendable {
    case fullProcessing = "full_processing"
    case transcription
    case speakerLabels = "speaker_labels"
}

nonisolated enum ProcessingJobStage: String, Codable, Sendable {
    case queued
    case savingRecording = "saving_recording"
    case preparingModel = "preparing_model"
    case transcribing
    case savingTranscript = "saving_transcript"
    case identifyingSpeakers = "identifying_speakers"
    case savingSpeakerLabels = "saving_speaker_labels"
    case finished

    var rank: Int {
        switch self {
        case .queued: 0
        case .savingRecording: 1
        case .preparingModel: 2
        case .transcribing: 3
        case .savingTranscript: 4
        case .identifyingSpeakers: 5
        case .savingSpeakerLabels: 6
        case .finished: 7
        }
    }
}

nonisolated enum ProcessingJobState: String, Codable, Sendable {
    case queued
    case running
    case cancelRequested = "cancel_requested"
    case interrupted
    case partial
    case succeeded
    case failed
}

nonisolated struct ProcessingJobRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let jobSchemaVersion: Int
    let jobID: ArtifactStoreID
    let pipelineRunID: ArtifactStoreID
    let attemptID: ArtifactStoreID
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let requestedOperation: ProcessingJobOperation
    let inputManifestGeneration: Int?
    let inputCorrectionVersion: Int?
    let stage: ProcessingJobStage
    let state: ProcessingJobState
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let publishedOutputReferences: [ProcessingArtifactReferenceV1]

    enum CodingKeys: String, CodingKey {
        case jobSchemaVersion = "job_schema_version"
        case jobID = "job_id"
        case pipelineRunID = "pipeline_run_id"
        case attemptID = "attempt_id"
        case recordingID = "recording_id"
        case sourceAudioID = "source_audio_id"
        case requestedOperation = "requested_operation"
        case inputManifestGeneration = "input_manifest_generation"
        case inputCorrectionVersion = "input_correction_version"
        case stage
        case state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case publishedOutputReferences = "published_output_references"
    }

    func checkpoint(
        stage: ProcessingJobStage,
        state: ProcessingJobState,
        at date: Date,
        publishedOutputReferences: [ProcessingArtifactReferenceV1]? = nil
    ) -> ProcessingJobRecordV1 {
        ProcessingJobRecordV1(
            jobSchemaVersion: jobSchemaVersion,
            jobID: jobID,
            pipelineRunID: pipelineRunID,
            attemptID: attemptID,
            recordingID: recordingID,
            sourceAudioID: sourceAudioID,
            requestedOperation: requestedOperation,
            inputManifestGeneration: inputManifestGeneration,
            inputCorrectionVersion: inputCorrectionVersion,
            stage: stage,
            state: state,
            createdAt: createdAt,
            updatedAt: date,
            startedAt: startedAt ?? (state == .running ? date : nil),
            finishedAt: [.interrupted, .partial, .succeeded, .failed].contains(state) ? date : nil,
            publishedOutputReferences: publishedOutputReferences ?? self.publishedOutputReferences
        )
    }
}

nonisolated struct ProcessingJobRecoveryReport: Equatable, Sendable {
    let recoveredJobs: [ProcessingJobLocator]
    let downgradedJobs: [ProcessingJobLocator]
    let projectionJobs: [ProcessingJobLocator]
    let corruptFileNames: [String]
}

nonisolated struct ProcessingJobLocator: Equatable, Hashable, Sendable {
    let recordingID: ArtifactStoreID
    let jobID: ArtifactStoreID
}

actor ProcessingJobStore {
    typealias PublishedEvidenceValidator = @Sendable (ProcessingJobRecordV1) -> Bool
    typealias MutationHook = @Sendable (ProcessingJobRecordV1) throws -> Void

    private let applicationSupportRoot: URL
    private let storeRoot: URL
    private let fileManager: FileManager
    private let publishedEvidenceValidator: PublishedEvidenceValidator
    private let beforeCreate: MutationHook
    private let beforeCheckpoint: MutationHook

    init(
        applicationSupportRoot: URL,
        fileManager: FileManager = .default,
        publishedEvidenceValidator: @escaping PublishedEvidenceValidator = { _ in false },
        beforeCreate: @escaping MutationHook = { _ in },
        beforeCheckpoint: @escaping MutationHook = { _ in }
    ) {
        let canonicalApplicationSupportRoot = applicationSupportRoot
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.applicationSupportRoot = canonicalApplicationSupportRoot
        storeRoot = canonicalApplicationSupportRoot
            .appendingPathComponent("ProcessingArtifacts/store-v1", isDirectory: true)
        self.fileManager = fileManager
        self.publishedEvidenceValidator = publishedEvidenceValidator
        self.beforeCreate = beforeCreate
        self.beforeCheckpoint = beforeCheckpoint
    }

    func create(_ record: ProcessingJobRecordV1) throws {
        guard record.state == .queued else {
            throw ProcessingJobStoreError.invalidJob("New job must be queued")
        }
        try validate(record, requirePublishedEvidence: false)
        let url = try jobURL(recordingID: record.recordingID, jobID: record.jobID)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw ProcessingJobStoreError.invalidJob("Duplicate job ID")
        }
        try beforeCreate(record)
        try writeAtomic(record, to: url)
    }

    func start(
        _ queuedRecord: ProcessingJobRecordV1,
        stage: ProcessingJobStage,
        at date: Date = .now
    ) throws -> ProcessingJobRecordV1 {
        guard queuedRecord.state == .queued else {
            throw ProcessingJobStoreError.invalidJob("Job must begin queued")
        }
        try validate(queuedRecord, requirePublishedEvidence: false)
        let running = queuedRecord.checkpoint(stage: stage, state: .running, at: date)
        try validate(running, requirePublishedEvidence: false)
        try validateTransition(from: queuedRecord, to: running)
        let url = try jobURL(
            recordingID: queuedRecord.recordingID,
            jobID: queuedRecord.jobID
        )
        guard !fileManager.fileExists(atPath: url.path) else {
            throw ProcessingJobStoreError.invalidJob("Duplicate job ID")
        }
        try beforeCreate(queuedRecord)
        try beforeCheckpoint(running)
        try writeAtomic(running, to: url)
        return running
    }

    func load(
        _ jobID: ArtifactStoreID,
        recordingID: ArtifactStoreID
    ) throws -> ProcessingJobRecordV1 {
        let url = try jobURL(recordingID: recordingID, jobID: jobID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProcessingJobStoreError.invalidJob("Missing job")
        }
        let record = try decode(try Data(contentsOf: url))
        guard record.jobID == jobID, record.recordingID == recordingID else {
            throw ProcessingJobStoreError.corruptJob(url.lastPathComponent)
        }
        try validate(record, requirePublishedEvidence: record.state == .succeeded)
        return record
    }

    @discardableResult
    func checkpoint(
        jobID: ArtifactStoreID,
        recordingID: ArtifactStoreID,
        expectedAttemptID: ArtifactStoreID,
        expectedInputManifestGeneration: Int?,
        expectedCorrectionVersion: Int?,
        stage: ProcessingJobStage,
        state: ProcessingJobState,
        publishedOutputReferences: [ProcessingArtifactReferenceV1]? = nil,
        at date: Date = .now
    ) throws -> ProcessingJobRecordV1 {
        let current = try load(jobID, recordingID: recordingID)
        guard current.attemptID == expectedAttemptID else {
            throw ProcessingJobStoreError.staleAttempt
        }
        guard current.inputManifestGeneration == expectedInputManifestGeneration else {
            throw ProcessingJobStoreError.staleInputGeneration
        }
        guard current.inputCorrectionVersion == expectedCorrectionVersion else {
            throw ProcessingJobStoreError.staleCorrectionVersion
        }
        let updated = current.checkpoint(
            stage: stage,
            state: state,
            at: date,
            publishedOutputReferences: publishedOutputReferences
        )
        try validate(updated, requirePublishedEvidence: state == .succeeded)
        try validateTransition(from: current, to: updated)
        try beforeCheckpoint(updated)
        try writeAtomic(
            updated,
            to: try jobURL(recordingID: recordingID, jobID: jobID)
        )
        return updated
    }

    func reconcileAfterRelaunch() throws -> ProcessingJobRecoveryReport {
        let recordingsRoot = try containedURL(for: "recordings")
        guard fileManager.fileExists(atPath: recordingsRoot.path) else {
            return ProcessingJobRecoveryReport(
                recoveredJobs: [],
                downgradedJobs: [],
                projectionJobs: [],
                corruptFileNames: []
            )
        }
        let recordingDirectories = try fileManager.contentsOfDirectory(
            at: recordingsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var recovered: [ProcessingJobLocator] = []
        var downgraded: [ProcessingJobLocator] = []
        var projection: Set<ProcessingJobLocator> = []
        var corrupt: [String] = []
        for recordingDirectory in recordingDirectories {
            do {
                _ = try validateContained(recordingDirectory)
                let recordingID = try ArtifactStoreID(
                    rawValue: recordingDirectory.lastPathComponent
                )
                let jobsRoot = try jobsRoot(recordingID)
                guard fileManager.fileExists(atPath: jobsRoot.path) else { continue }
                let urls = try fileManager.contentsOfDirectory(
                    at: jobsRoot,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                for url in urls where url.pathExtension == "json" {
                    do {
                        _ = try validateContained(url)
                        var record = try decode(try Data(contentsOf: url))
                        guard url.deletingPathExtension().lastPathComponent == record.jobID.rawValue,
                              record.recordingID == recordingID else {
                            throw ProcessingJobStoreError.corruptJob(url.lastPathComponent)
                        }
                        try validate(record, requirePublishedEvidence: false)
                        let locator = ProcessingJobLocator(
                            recordingID: recordingID,
                            jobID: record.jobID
                        )
                        if record.state == .running || record.state == .cancelRequested {
                            record = record.checkpoint(
                                stage: record.stage,
                                state: .interrupted,
                                at: .now
                            )
                            try validate(record, requirePublishedEvidence: false)
                            try writeAtomic(record, to: url)
                            recovered.append(locator)
                        } else if record.state == .succeeded,
                                  !publishedEvidenceValidator(record) {
                            record = record.checkpoint(
                                stage: record.stage,
                                state: .partial,
                                at: .now
                            )
                            try validate(record, requirePublishedEvidence: false)
                            try writeAtomic(record, to: url)
                            downgraded.append(locator)
                        }
                        if [.interrupted, .partial, .failed].contains(record.state) {
                            projection.insert(locator)
                        }
                    } catch {
                        corrupt.append(
                            "\(recordingDirectory.lastPathComponent)/\(url.lastPathComponent)"
                        )
                    }
                }
            } catch {
                corrupt.append(recordingDirectory.lastPathComponent)
            }
        }
        return ProcessingJobRecoveryReport(
            recoveredJobs: recovered.sorted(by: Self.locatorOrder),
            downgradedJobs: downgraded.sorted(by: Self.locatorOrder),
            projectionJobs: projection.sorted(by: Self.locatorOrder),
            corruptFileNames: corrupt.sorted()
        )
    }

    private func validate(
        _ record: ProcessingJobRecordV1,
        requirePublishedEvidence: Bool
    ) throws {
        guard record.jobSchemaVersion == ProcessingJobRecordV1.schemaVersion else {
            throw ProcessingJobStoreError.unknownSchemaVersion(record.jobSchemaVersion)
        }
        guard record.inputManifestGeneration.map({ $0 >= 0 }) ?? true,
              record.inputCorrectionVersion.map({ $0 >= 0 }) ?? true,
              record.updatedAt >= record.createdAt else {
            throw ProcessingJobStoreError.invalidJob("Invalid job metadata")
        }
        switch record.state {
        case .queued:
            guard record.startedAt == nil, record.finishedAt == nil else {
                throw ProcessingJobStoreError.invalidJob("Queued timestamp invariant")
            }
        case .running:
            guard record.startedAt != nil, record.finishedAt == nil else {
                throw ProcessingJobStoreError.invalidJob("Running timestamp invariant")
            }
        case .cancelRequested:
            guard record.finishedAt == nil else {
                throw ProcessingJobStoreError.invalidJob("Cancel timestamp invariant")
            }
        case .interrupted, .partial, .succeeded, .failed:
            guard record.finishedAt != nil else {
                throw ProcessingJobStoreError.invalidJob("Terminal timestamp invariant")
            }
        }
        if let startedAt = record.startedAt {
            guard startedAt >= record.createdAt, startedAt <= record.updatedAt else {
                throw ProcessingJobStoreError.invalidJob("Started timestamp order")
            }
        }
        if let finishedAt = record.finishedAt {
            guard finishedAt >= record.createdAt, finishedAt <= record.updatedAt else {
                throw ProcessingJobStoreError.invalidJob("Finished timestamp order")
            }
        }
        if requirePublishedEvidence {
            guard !record.publishedOutputReferences.isEmpty,
                  publishedEvidenceValidator(record) else {
                throw ProcessingJobStoreError.successWithoutPublishedEvidence
            }
        }
        for reference in record.publishedOutputReferences {
            guard reference.recordingID == record.recordingID else {
                throw ProcessingJobStoreError.invalidJob("Cross-recording output")
            }
        }
    }

    private func validateTransition(
        from current: ProcessingJobRecordV1,
        to updated: ProcessingJobRecordV1
    ) throws {
        let terminal: Set<ProcessingJobState> = [.interrupted, .partial, .succeeded, .failed]
        guard !terminal.contains(current.state) else {
            throw ProcessingJobStoreError.invalidJob("Terminal job is immutable")
        }
        let allowed: [ProcessingJobState: Set<ProcessingJobState>] = [
            .queued: [.queued, .running, .cancelRequested, .failed],
            .running: [.running, .cancelRequested, .interrupted, .partial, .succeeded, .failed],
            .cancelRequested: [.cancelRequested, .interrupted, .partial, .failed],
        ]
        guard allowed[current.state]?.contains(updated.state) == true,
              updated.stage.rank >= current.stage.rank else {
            throw ProcessingJobStoreError.invalidJob("Illegal job transition")
        }
    }

    private func jobsRoot(_ recordingID: ArtifactStoreID) throws -> URL {
        try containedURL(for: "recordings/\(recordingID.rawValue)/jobs")
    }

    private func jobURL(
        recordingID: ArtifactStoreID,
        jobID: ArtifactStoreID
    ) throws -> URL {
        try containedURL(
            for: "recordings/\(recordingID.rawValue)/jobs/\(jobID.rawValue).json"
        )
    }

    private func containedURL(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw ProcessingJobStoreError.invalidJob("Invalid job path")
        }
        return try validateContained(storeRoot.appendingPathComponent(relativePath))
    }

    @discardableResult
    private func validateContained(_ url: URL) throws -> URL {
        let applicationRoot = applicationSupportRoot
        let root = storeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isContained(root, in: applicationRoot),
              Self.isContained(candidate, in: applicationRoot),
              Self.isContained(candidate, in: root) else {
            throw ProcessingJobStoreError.invalidJob("Job path escaped store")
        }
        return candidate
    }

    nonisolated private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func writeAtomic(_ record: ProcessingJobRecordV1, to destination: URL) throws {
        let destination = try validateContained(destination)
        let jobsRoot = try jobsRoot(record.recordingID)
        try fileManager.createDirectory(
            at: jobsRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encode(record)
        let temporary = jobsRoot.appendingPathComponent(".\(record.jobID.rawValue)-\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw ProcessingJobStoreError.invalidJob("Could not stage job")
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            let reopened = try decode(try Data(contentsOf: temporary))
            guard try encode(reopened) == data else {
                throw ProcessingJobStoreError.corruptJob(temporary.lastPathComponent)
            }
            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let descriptor = Darwin.open(jobsRoot.path, O_RDONLY)
            guard descriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    nonisolated private static func locatorOrder(
        _ lhs: ProcessingJobLocator,
        _ rhs: ProcessingJobLocator
    ) -> Bool {
        (lhs.recordingID.rawValue, lhs.jobID.rawValue)
            < (rhs.recordingID.rawValue, rhs.jobID.rawValue)
    }

    private func encode(_ record: ProcessingJobRecordV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    private func decode(_ data: Data) throws -> ProcessingJobRecordV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(ProcessingJobRecordV1.self, from: data)
        } catch let error as ProcessingJobStoreError {
            throw error
        } catch {
            throw ProcessingJobStoreError.corruptJob(error.localizedDescription)
        }
    }
}
