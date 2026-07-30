import CryptoKit
import Darwin
import Foundation

nonisolated enum ProcessingArtifactStoreError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case invalidRelativePath(String)
    case unknownSchemaVersion(Int)
    case corruptData(String)
    case digestMismatch
    case wrongRecording
    case missingPayload
    case duplicateArtifactConflict
    case staleGeneration(expected: Int?, actual: Int?)
    case invalidGeneration
    case noPublishedManifest
    case cleanupBlocked(String)
    case pointerCommitFailed
    case invalidPointerState(String)
    case missingReference(String)
    case cyclicReference(String)
    case sourceAudioMismatch
}

nonisolated struct ArtifactStoreID: Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) throws {
        guard let uuid = UUID(uuidString: rawValue),
              uuid.uuidString.lowercased() == rawValue else {
            throw ProcessingArtifactStoreError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    init() {
        rawValue = UUID().uuidString.lowercased()
    }

    init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum ProcessingArtifactKind: String, Codable, Sendable {
    case preparedAudio = "prepared_audio"
    case transcription
    case diarization
    case identity
    case reconciliation
    case transcriptVersion = "transcript_version"
    case correctionLog = "correction_log"
    case diagnostics
    case provenance
}

nonisolated enum ProcessingArtifactPrivacyClass: String, Codable, Sendable {
    case ordinaryPrivate = "ordinary_private"
    case transcriptPrivate = "transcript_private"
    case audioPrivate = "audio_private"
    case identitySensitive = "identity_sensitive"
}

nonisolated struct ProcessingArtifactReferenceV1: Codable, Equatable, Sendable {
    let artifactID: ArtifactStoreID
    let artifactKind: ProcessingArtifactKind
    let recordingID: ArtifactStoreID
    let envelopeRelativePath: String

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case artifactKind = "artifact_kind"
        case recordingID = "recording_id"
        case envelopeRelativePath = "envelope_relative_path"
    }
}

nonisolated struct ProcessingArtifactPayloadDescriptorV1: Codable, Equatable, Sendable {
    let encoding: String
    let relativePath: String
    let byteCount: Int
    let digestAlgorithm: String
    let digest: String

    enum CodingKeys: String, CodingKey {
        case encoding
        case relativePath = "relative_path"
        case byteCount = "byte_count"
        case digestAlgorithm = "digest_algorithm"
        case digest
    }
}

nonisolated struct ProcessingArtifactEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let envelopeSchemaVersion: Int
    let artifactID: ArtifactStoreID
    let artifactKind: ProcessingArtifactKind
    let payloadSchemaVersion: Int
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let pipelineRunID: ArtifactStoreID
    let attemptID: ArtifactStoreID
    let createdAt: Date
    let completedAt: Date?
    let componentID: String
    let componentVersion: String
    let parents: [ProcessingArtifactReferenceV1]
    let inputs: [ProcessingArtifactReferenceV1]
    let payload: ProcessingArtifactPayloadDescriptorV1
    let privacyClass: ProcessingArtifactPrivacyClass

    enum CodingKeys: String, CodingKey {
        case envelopeSchemaVersion = "envelope_schema_version"
        case artifactID = "artifact_id"
        case artifactKind = "artifact_kind"
        case payloadSchemaVersion = "payload_schema_version"
        case recordingID = "recording_id"
        case sourceAudioID = "source_audio_id"
        case pipelineRunID = "pipeline_run_id"
        case attemptID = "attempt_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case componentID = "component_id"
        case componentVersion = "component_version"
        case parents
        case inputs
        case payload
        case privacyClass = "privacy_class"
    }
}

nonisolated struct ProcessingArtifactManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let manifestSchemaVersion: Int
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let generation: Int
    let createdAt: Date
    let artifacts: [ProcessingArtifactReferenceV1]

    enum CodingKeys: String, CodingKey {
        case manifestSchemaVersion = "manifest_schema_version"
        case recordingID = "recording_id"
        case sourceAudioID = "source_audio_id"
        case generation
        case createdAt = "created_at"
        case artifacts
    }
}

nonisolated struct ProcessingArtifactPointerV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let pointerSchemaVersion: Int
    let recordingID: ArtifactStoreID
    let generation: Int
    let manifestRelativePath: String
    let manifestDigestAlgorithm: String
    let manifestDigest: String
    let priorGeneration: Int?
    let priorManifestDigest: String?

    enum CodingKeys: String, CodingKey {
        case pointerSchemaVersion = "pointer_schema_version"
        case recordingID = "recording_id"
        case generation
        case manifestRelativePath = "manifest_relative_path"
        case manifestDigestAlgorithm = "manifest_digest_algorithm"
        case manifestDigest = "manifest_digest"
        case priorGeneration = "prior_generation"
        case priorManifestDigest = "prior_manifest_digest"
    }
}

nonisolated struct ProcessingArtifactWriteRequest: Sendable {
    let artifactID: ArtifactStoreID
    let artifactKind: ProcessingArtifactKind
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let pipelineRunID: ArtifactStoreID
    let attemptID: ArtifactStoreID
    let payloadSchemaVersion: Int
    let payloadEncoding: String
    let payload: Data
    let componentID: String
    let componentVersion: String
    let parents: [ProcessingArtifactReferenceV1]
    let inputs: [ProcessingArtifactReferenceV1]
    let privacyClass: ProcessingArtifactPrivacyClass
    let createdAt: Date
}

nonisolated struct ProcessingArtifactReadResult: Equatable, Sendable {
    let envelope: ProcessingArtifactEnvelopeV1
    let payload: Data
}

nonisolated struct ProcessingArtifactCleanupReport: Equatable, Sendable {
    let removedRelativePaths: [String]
}

actor ProcessingArtifactStore {
    typealias BeforePointerCommit = @Sendable () throws -> Void
    typealias AfterPreviousPointerCommit = @Sendable () throws -> Void

    let storeRoot: URL
    private let fileManager: FileManager
    private let beforePointerCommit: BeforePointerCommit
    private let afterPreviousPointerCommit: AfterPreviousPointerCommit

    init(
        applicationSupportRoot: URL,
        fileManager: FileManager = .default,
        beforePointerCommit: @escaping BeforePointerCommit = {},
        afterPreviousPointerCommit: @escaping AfterPreviousPointerCommit = {}
    ) {
        storeRoot = applicationSupportRoot
            .appendingPathComponent("ProcessingArtifacts", isDirectory: true)
            .appendingPathComponent("store-v1", isDirectory: true)
        self.fileManager = fileManager
        self.beforePointerCommit = beforePointerCommit
        self.afterPreviousPointerCommit = afterPreviousPointerCommit
    }

    func writeArtifact(_ request: ProcessingArtifactWriteRequest) throws -> ProcessingArtifactReferenceV1 {
        try validateReferences(request.parents + request.inputs, recordingID: request.recordingID)
        let artifactsRoot = try containedURL(
            for: "recordings/\(request.recordingID.rawValue)/artifacts"
        )
        try createDirectory(artifactsRoot)

        let finalDirectory = try containedURL(
            for: "recordings/\(request.recordingID.rawValue)/artifacts/\(request.artifactID.rawValue)"
        )
        let payloadRelativePath = artifactPayloadRelativePath(
            recordingID: request.recordingID,
            artifactID: request.artifactID
        )
        let envelopeRelativePath = artifactEnvelopeRelativePath(
            recordingID: request.recordingID,
            artifactID: request.artifactID
        )
        let payloadDigest = Self.sha256(request.payload)
        let envelope = ProcessingArtifactEnvelopeV1(
            envelopeSchemaVersion: ProcessingArtifactEnvelopeV1.schemaVersion,
            artifactID: request.artifactID,
            artifactKind: request.artifactKind,
            payloadSchemaVersion: request.payloadSchemaVersion,
            recordingID: request.recordingID,
            sourceAudioID: request.sourceAudioID,
            pipelineRunID: request.pipelineRunID,
            attemptID: request.attemptID,
            createdAt: request.createdAt,
            completedAt: request.createdAt,
            componentID: request.componentID,
            componentVersion: request.componentVersion,
            parents: request.parents,
            inputs: request.inputs,
            payload: ProcessingArtifactPayloadDescriptorV1(
                encoding: request.payloadEncoding,
                relativePath: payloadRelativePath,
                byteCount: request.payload.count,
                digestAlgorithm: "sha256",
                digest: payloadDigest
            ),
            privacyClass: request.privacyClass
        )
        let envelopeData = try encode(envelope)

        if fileManager.fileExists(atPath: finalDirectory.path) {
            let existing = try readArtifact(
                ProcessingArtifactReferenceV1(
                    artifactID: request.artifactID,
                    artifactKind: request.artifactKind,
                    recordingID: request.recordingID,
                    envelopeRelativePath: envelopeRelativePath
                ),
                expectedRecordingID: request.recordingID
            )
            guard existing.envelope == envelope, existing.payload == request.payload else {
                throw ProcessingArtifactStoreError.duplicateArtifactConflict
            }
            return ProcessingArtifactReferenceV1(
                artifactID: request.artifactID,
                artifactKind: request.artifactKind,
                recordingID: request.recordingID,
                envelopeRelativePath: envelopeRelativePath
            )
        }

        let temporaryDirectory = try containedURL(
            for: "recordings/\(request.recordingID.rawValue)/.artifact-\(request.artifactID.rawValue)-\(UUID().uuidString).tmp"
        )
        try createDirectory(temporaryDirectory)
        do {
            try writeSynced(request.payload, to: temporaryDirectory.appendingPathComponent("payload.bin"))
            try writeSynced(envelopeData, to: temporaryDirectory.appendingPathComponent("envelope.json"))
            let stagedPayload = try readData(
                at: temporaryDirectory.appendingPathComponent("payload.bin")
            )
            let stagedEnvelope: ProcessingArtifactEnvelopeV1 = try decode(
                ProcessingArtifactEnvelopeV1.self,
                from: try readData(
                    at: temporaryDirectory.appendingPathComponent("envelope.json")
                )
            )
            try validateEnvelope(stagedEnvelope, payload: stagedPayload, expectedRecordingID: request.recordingID)
            guard Darwin.rename(temporaryDirectory.path, finalDirectory.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try synchronizeDirectory(artifactsRoot)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }

        return ProcessingArtifactReferenceV1(
            artifactID: request.artifactID,
            artifactKind: request.artifactKind,
            recordingID: request.recordingID,
            envelopeRelativePath: envelopeRelativePath
        )
    }

    func readArtifact(
        _ reference: ProcessingArtifactReferenceV1,
        expectedRecordingID: ArtifactStoreID
    ) throws -> ProcessingArtifactReadResult {
        var visiting: Set<ArtifactStoreID> = []
        var validated: Set<ArtifactStoreID> = []
        return try readArtifactGraph(
            reference,
            expectedRecordingID: expectedRecordingID,
            expectedSourceAudioID: nil,
            visiting: &visiting,
            validated: &validated
        )
    }

    private func readArtifactGraph(
        _ reference: ProcessingArtifactReferenceV1,
        expectedRecordingID: ArtifactStoreID,
        expectedSourceAudioID: ArtifactStoreID?,
        visiting: inout Set<ArtifactStoreID>,
        validated: inout Set<ArtifactStoreID>
    ) throws -> ProcessingArtifactReadResult {
        guard reference.recordingID == expectedRecordingID else {
            throw ProcessingArtifactStoreError.wrongRecording
        }
        guard !visiting.contains(reference.artifactID) else {
            throw ProcessingArtifactStoreError.cyclicReference(reference.artifactID.rawValue)
        }
        let expectedEnvelopePath = artifactEnvelopeRelativePath(
            recordingID: expectedRecordingID,
            artifactID: reference.artifactID
        )
        guard reference.envelopeRelativePath == expectedEnvelopePath else {
            throw ProcessingArtifactStoreError.invalidRelativePath(reference.envelopeRelativePath)
        }
        let envelopeURL = try containedURL(for: reference.envelopeRelativePath)
        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            throw ProcessingArtifactStoreError.missingReference(reference.artifactID.rawValue)
        }
        let envelope: ProcessingArtifactEnvelopeV1 = try decode(
            ProcessingArtifactEnvelopeV1.self,
            from: try readData(at: envelopeURL)
        )
        guard envelope.artifactID == reference.artifactID,
              envelope.artifactKind == reference.artifactKind else {
            throw ProcessingArtifactStoreError.corruptData("Reference does not match envelope")
        }
        if let expectedSourceAudioID, envelope.sourceAudioID != expectedSourceAudioID {
            throw ProcessingArtifactStoreError.sourceAudioMismatch
        }
        let payloadURL = try containedURL(for: envelope.payload.relativePath)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw ProcessingArtifactStoreError.missingPayload
        }
        let payload = try readData(at: payloadURL)
        try validateEnvelope(envelope, payload: payload, expectedRecordingID: expectedRecordingID)
        if !validated.contains(reference.artifactID) {
            visiting.insert(reference.artifactID)
            defer { visiting.remove(reference.artifactID) }
            for dependency in envelope.parents + envelope.inputs {
                _ = try readArtifactGraph(
                    dependency,
                    expectedRecordingID: expectedRecordingID,
                    expectedSourceAudioID: envelope.sourceAudioID,
                    visiting: &visiting,
                    validated: &validated
                )
            }
            validated.insert(reference.artifactID)
        }
        return ProcessingArtifactReadResult(envelope: envelope, payload: payload)
    }

    func publish(
        _ manifest: ProcessingArtifactManifestV1,
        expectedGeneration: Int?
    ) throws {
        try validateManifest(manifest)
        let currentPublication = try loadCurrentPublicationOrNil(recordingID: manifest.recordingID)
        let actualGeneration = currentPublication?.manifest.generation
        guard actualGeneration == expectedGeneration else {
            throw ProcessingArtifactStoreError.staleGeneration(
                expected: expectedGeneration,
                actual: actualGeneration
            )
        }
        let nextGeneration = (actualGeneration ?? 0) + 1
        guard manifest.generation == nextGeneration else {
            throw ProcessingArtifactStoreError.invalidGeneration
        }

        try validateManifestGraph(manifest)

        let manifestsRoot = try manifestsRoot(manifest.recordingID)
        let manifestRelativePath = manifestRelativePath(
            recordingID: manifest.recordingID,
            generation: manifest.generation
        )
        let manifestURL = try containedURL(for: manifestRelativePath)
        let manifestData = try encode(manifest)
        try writeImmutableFile(manifestData, to: manifestURL)
        let decoded: ProcessingArtifactManifestV1 = try decode(
            ProcessingArtifactManifestV1.self,
            from: try readData(at: manifestURL)
        )
        try validateManifest(decoded)
        try validateManifestGraph(decoded)

        let currentURL = try containedURL(
            for: "recordings/\(manifest.recordingID.rawValue)/manifests/current"
        )
        let previousURL = try containedURL(
            for: "recordings/\(manifest.recordingID.rawValue)/manifests/current.previous"
        )
        let priorPointer = currentPublication?.pointer

        let pointer = ProcessingArtifactPointerV1(
            pointerSchemaVersion: ProcessingArtifactPointerV1.schemaVersion,
            recordingID: manifest.recordingID,
            generation: manifest.generation,
            manifestRelativePath: manifestRelativePath,
            manifestDigestAlgorithm: "sha256",
            manifestDigest: Self.sha256(manifestData),
            priorGeneration: priorPointer?.generation,
            priorManifestDigest: priorPointer?.manifestDigest
        )
        let stagedPrevious = try priorPointer.map {
            try stageValidatedPointer(
                $0,
                beside: previousURL,
                expectedRecordingID: manifest.recordingID
            )
        }
        let stagedCurrent = try stageValidatedPointer(
            pointer,
            beside: currentURL,
            expectedRecordingID: manifest.recordingID
        )
        do {
            try beforePointerCommit()
            if let stagedPrevious {
                try replace(stagedPrevious, with: previousURL)
                try afterPreviousPointerCommit()
            }
            try replace(stagedCurrent, with: currentURL)
            try synchronizeDirectory(manifestsRoot)
        } catch {
            if let stagedPrevious { try? fileManager.removeItem(at: stagedPrevious) }
            try? fileManager.removeItem(at: stagedCurrent)
            throw error
        }
        let reopened = try loadPublishedManifest(recordingID: manifest.recordingID)
        guard reopened == manifest else {
            throw ProcessingArtifactStoreError.pointerCommitFailed
        }
    }

    func loadPublishedManifest(recordingID: ArtifactStoreID) throws -> ProcessingArtifactManifestV1 {
        let currentURL = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests/current"
        )
        let previousURL = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests/current.previous"
        )
        guard fileManager.fileExists(atPath: currentURL.path) else {
            guard !fileManager.fileExists(atPath: previousURL.path) else {
                throw ProcessingArtifactStoreError.invalidPointerState("Previous pointer without current")
            }
            throw ProcessingArtifactStoreError.noPublishedManifest
        }
        let current: ProcessingArtifactPointerV1
        do {
            current = try strictPointer(at: currentURL, expectedRecordingID: recordingID)
        } catch {
            guard fileManager.fileExists(atPath: previousURL.path) else { throw error }
            let independentPrevious = try strictPointer(
                at: previousURL,
                expectedRecordingID: recordingID
            )
            return try manifestThroughPointer(independentPrevious, recordingID: recordingID)
        }
        let previous = try linkedPrevious(
            for: current,
            at: previousURL,
            recordingID: recordingID
        )
        do {
            return try manifestThroughPointer(current, recordingID: recordingID)
        } catch {
            if let previous {
                return previous.manifest
            }
            throw error
        }
    }

    func cleanupUnpublished(
        recordingID: ArtifactStoreID,
        olderThan cutoff: Date
    ) throws -> ProcessingArtifactCleanupReport {
        let recordingRoot = try recordingRoot(recordingID)
        guard fileManager.fileExists(atPath: recordingRoot.path) else {
            return ProcessingArtifactCleanupReport(removedRelativePaths: [])
        }
        let manifestsRoot = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests"
        )
        var retainedIDs: Set<ArtifactStoreID> = []
        let manifestURLs: [URL]
        if fileManager.fileExists(atPath: manifestsRoot.path) {
            manifestURLs = try fileManager.contentsOfDirectory(
                at: manifestsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } else {
            manifestURLs = []
        }
        for url in manifestURLs {
            _ = try validateInternalURL(url)
            guard url.lastPathComponent.hasPrefix("manifest-") else { continue }
            do {
                let manifest: ProcessingArtifactManifestV1 = try decode(
                    ProcessingArtifactManifestV1.self,
                    from: try readData(at: url)
                )
                try validateManifest(manifest)
                guard manifest.recordingID == recordingID else {
                    throw ProcessingArtifactStoreError.wrongRecording
                }
                retainedIDs.formUnion(try validateManifestGraph(manifest))
            } catch {
                throw ProcessingArtifactStoreError.cleanupBlocked("Unknown or corrupt manifest")
            }
        }

        do {
            _ = try loadCurrentPublicationOrNil(recordingID: recordingID)
        } catch {
            throw ProcessingArtifactStoreError.cleanupBlocked("Pointer state is corrupt")
        }
        var removed: [String] = []

        let children = try fileManager.contentsOfDirectory(
            at: recordingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: []
        )
        for child in children where child.lastPathComponent.hasSuffix(".tmp") {
            _ = try validateInternalURL(child)
            if try isOlder(child, than: cutoff) {
                let removedPath = try relativePath(for: child)
                try fileManager.removeItem(at: child)
                removed.append(removedPath)
            }
        }

        let artifactsRoot = try containedURL(
            for: "recordings/\(recordingID.rawValue)/artifacts"
        )
        let artifactDirectories = fileManager.fileExists(atPath: artifactsRoot.path)
            ? try fileManager.contentsOfDirectory(
                at: artifactsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: []
            )
            : []
        for directory in artifactDirectories {
            _ = try validateInternalURL(directory)
            guard let artifactID = try? ArtifactStoreID(rawValue: directory.lastPathComponent),
                  !retainedIDs.contains(artifactID),
                  try isOlder(directory, than: cutoff) else {
                continue
            }
            let removedPath = try relativePath(for: directory)
            try fileManager.removeItem(at: directory)
            removed.append(removedPath)
        }
        return ProcessingArtifactCleanupReport(removedRelativePaths: removed.sorted())
    }

    private func loadCurrentPublicationOrNil(
        recordingID: ArtifactStoreID
    ) throws -> (pointer: ProcessingArtifactPointerV1, manifest: ProcessingArtifactManifestV1)? {
        let currentURL = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests/current"
        )
        let previousURL = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests/current.previous"
        )
        guard fileManager.fileExists(atPath: currentURL.path) else {
            guard !fileManager.fileExists(atPath: previousURL.path) else {
                throw ProcessingArtifactStoreError.invalidPointerState("Previous pointer without current")
            }
            return nil
        }
        let pointer = try strictPointer(at: currentURL, expectedRecordingID: recordingID)
        _ = try linkedPrevious(for: pointer, at: previousURL, recordingID: recordingID)
        return (pointer, try manifestThroughPointer(pointer, recordingID: recordingID))
    }

    private func linkedPrevious(
        for current: ProcessingArtifactPointerV1,
        at previousURL: URL,
        recordingID: ArtifactStoreID
    ) throws -> (pointer: ProcessingArtifactPointerV1, manifest: ProcessingArtifactManifestV1)? {
        if fileManager.fileExists(atPath: previousURL.path) {
            let previous = try strictPointer(at: previousURL, expectedRecordingID: recordingID)
            if previous == current {
                // A crash can occur after replacing current.previous but before replacing
                // current. In that state current is still authoritative and the duplicate
                // previous pointer is an inert journal of the interrupted publication.
                _ = try manifestThroughPointer(previous, recordingID: recordingID)
                return nil
            }
        }
        guard let priorGeneration = current.priorGeneration,
              let priorDigest = current.priorManifestDigest else {
            guard !fileManager.fileExists(atPath: previousURL.path) else {
                throw ProcessingArtifactStoreError.invalidPointerState("Unexpected previous pointer")
            }
            return nil
        }
        guard fileManager.fileExists(atPath: previousURL.path) else {
            throw ProcessingArtifactStoreError.invalidPointerState("Missing linked previous pointer")
        }
        let previous = try strictPointer(at: previousURL, expectedRecordingID: recordingID)
        guard previous.generation == priorGeneration,
              previous.manifestDigest == priorDigest else {
            throw ProcessingArtifactStoreError.invalidPointerState("Previous pointer linkage mismatch")
        }
        return (previous, try manifestThroughPointer(previous, recordingID: recordingID))
    }

    private func manifestThroughPointer(
        _ pointer: ProcessingArtifactPointerV1,
        recordingID: ArtifactStoreID
    ) throws -> ProcessingArtifactManifestV1 {
        let manifestURL = try containedURL(for: pointer.manifestRelativePath)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ProcessingArtifactStoreError.invalidPointerState("Missing pointed manifest")
        }
        let data = try readData(at: manifestURL)
        guard Self.sha256(data) == pointer.manifestDigest else {
            throw ProcessingArtifactStoreError.digestMismatch
        }
        let manifest = try decode(ProcessingArtifactManifestV1.self, from: data)
        try validateManifest(manifest)
        guard manifest.recordingID == recordingID,
              manifest.generation == pointer.generation else {
            throw ProcessingArtifactStoreError.invalidPointerState("Pointer and manifest disagree")
        }
        try validateManifestGraph(manifest)
        return manifest
    }

    private func strictPointer(
        at url: URL,
        expectedRecordingID: ArtifactStoreID
    ) throws -> ProcessingArtifactPointerV1 {
        _ = try validateInternalURL(url)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProcessingArtifactStoreError.invalidPointerState("Missing pointer")
        }
        let pointer = try decode(
            ProcessingArtifactPointerV1.self,
            from: try readData(at: url)
        )
        guard pointer.pointerSchemaVersion == ProcessingArtifactPointerV1.schemaVersion,
              pointer.recordingID == expectedRecordingID,
              pointer.generation > 0,
              pointer.manifestDigestAlgorithm == "sha256",
              pointer.manifestRelativePath == manifestRelativePath(
                recordingID: expectedRecordingID,
                generation: pointer.generation
              ),
              (pointer.priorGeneration == nil) == (pointer.priorManifestDigest == nil),
              pointer.priorGeneration.map({ $0 == pointer.generation - 1 }) ?? true else {
            throw ProcessingArtifactStoreError.invalidPointerState("Invalid pointer fields")
        }
        return pointer
    }

    private func validateEnvelope(
        _ envelope: ProcessingArtifactEnvelopeV1,
        payload: Data,
        expectedRecordingID: ArtifactStoreID
    ) throws {
        guard envelope.envelopeSchemaVersion == ProcessingArtifactEnvelopeV1.schemaVersion else {
            throw ProcessingArtifactStoreError.unknownSchemaVersion(envelope.envelopeSchemaVersion)
        }
        guard envelope.payloadSchemaVersion == 1 else {
            throw ProcessingArtifactStoreError.unknownSchemaVersion(envelope.payloadSchemaVersion)
        }
        guard envelope.recordingID == expectedRecordingID else {
            throw ProcessingArtifactStoreError.wrongRecording
        }
        let expectedPayloadPath = artifactPayloadRelativePath(
            recordingID: envelope.recordingID,
            artifactID: envelope.artifactID
        )
        guard envelope.payload.relativePath == expectedPayloadPath else {
            throw ProcessingArtifactStoreError.invalidRelativePath(envelope.payload.relativePath)
        }
        try validateReferences(envelope.parents + envelope.inputs, recordingID: expectedRecordingID)
        guard envelope.completedAt != nil,
              envelope.payload.digestAlgorithm == "sha256" else {
            throw ProcessingArtifactStoreError.corruptData("Invalid envelope metadata")
        }
        guard Self.sha256(payload) == envelope.payload.digest else {
            throw ProcessingArtifactStoreError.digestMismatch
        }
        guard envelope.payload.byteCount == payload.count else {
            throw ProcessingArtifactStoreError.corruptData("Invalid envelope metadata")
        }
    }

    private func validateManifest(_ manifest: ProcessingArtifactManifestV1) throws {
        guard manifest.manifestSchemaVersion == ProcessingArtifactManifestV1.schemaVersion else {
            throw ProcessingArtifactStoreError.unknownSchemaVersion(manifest.manifestSchemaVersion)
        }
        guard manifest.generation > 0 else {
            throw ProcessingArtifactStoreError.invalidGeneration
        }
        try validateReferences(manifest.artifacts, recordingID: manifest.recordingID)
        guard Set(manifest.artifacts.map(\.artifactID)).count == manifest.artifacts.count else {
            throw ProcessingArtifactStoreError.corruptData("Duplicate artifact reference")
        }
    }

    @discardableResult
    private func validateManifestGraph(
        _ manifest: ProcessingArtifactManifestV1
    ) throws -> Set<ArtifactStoreID> {
        var visiting: Set<ArtifactStoreID> = []
        var validated: Set<ArtifactStoreID> = []
        for reference in manifest.artifacts {
            _ = try readArtifactGraph(
                reference,
                expectedRecordingID: manifest.recordingID,
                expectedSourceAudioID: manifest.sourceAudioID,
                visiting: &visiting,
                validated: &validated
            )
        }
        return validated
    }

    private func validateReferences(
        _ references: [ProcessingArtifactReferenceV1],
        recordingID: ArtifactStoreID
    ) throws {
        for reference in references {
            guard reference.recordingID == recordingID else {
                throw ProcessingArtifactStoreError.wrongRecording
            }
            guard reference.envelopeRelativePath == artifactEnvelopeRelativePath(
                recordingID: recordingID,
                artifactID: reference.artifactID
            ) else {
                throw ProcessingArtifactStoreError.invalidRelativePath(reference.envelopeRelativePath)
            }
        }
    }

    private func recordingRoot(_ recordingID: ArtifactStoreID) throws -> URL {
        let relative = "recordings/\(recordingID.rawValue)"
        return try containedURL(for: relative)
    }

    private func manifestsRoot(_ recordingID: ArtifactStoreID) throws -> URL {
        let root = try containedURL(
            for: "recordings/\(recordingID.rawValue)/manifests"
        )
        try createDirectory(root)
        return root
    }

    private func artifactEnvelopeRelativePath(
        recordingID: ArtifactStoreID,
        artifactID: ArtifactStoreID
    ) -> String {
        "recordings/\(recordingID.rawValue)/artifacts/\(artifactID.rawValue)/envelope.json"
    }

    private func artifactPayloadRelativePath(
        recordingID: ArtifactStoreID,
        artifactID: ArtifactStoreID
    ) -> String {
        "recordings/\(recordingID.rawValue)/artifacts/\(artifactID.rawValue)/payload.bin"
    }

    private func manifestRelativePath(
        recordingID: ArtifactStoreID,
        generation: Int
    ) -> String {
        "recordings/\(recordingID.rawValue)/manifests/manifest-\(generation).json"
    }

    private func containedURL(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.isEmpty,
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw ProcessingArtifactStoreError.invalidRelativePath(relativePath)
        }
        return try validateInternalURL(storeRoot.appendingPathComponent(relativePath))
    }

    @discardableResult
    private func validateInternalURL(_ url: URL) throws -> URL {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = storeRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw ProcessingArtifactStoreError.invalidRelativePath(url.path)
        }
        return candidate
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPath = storeRoot.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(rootPath) else {
            throw ProcessingArtifactStoreError.invalidRelativePath(path)
        }
        return String(path.dropFirst(rootPath.count))
    }

    private func createDirectory(_ url: URL) throws {
        let url = try validateInternalURL(url)
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func stageValidatedPointer(
        _ pointer: ProcessingArtifactPointerV1,
        beside destination: URL,
        expectedRecordingID: ArtifactStoreID
    ) throws -> URL {
        let destination = try validateInternalURL(destination)
        try createDirectory(destination.deletingLastPathComponent())
        let staged = try validateInternalURL(
            destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString).tmp")
        )
        do {
            try writeSynced(try encode(pointer), to: staged)
            let reopened = try strictPointer(
                at: staged,
                expectedRecordingID: expectedRecordingID
            )
            guard reopened == pointer else {
                throw ProcessingArtifactStoreError.pointerCommitFailed
            }
            return staged
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    private func replace(_ staged: URL, with destination: URL) throws {
        let staged = try validateInternalURL(staged)
        let destination = try validateInternalURL(destination)
        guard Darwin.rename(staged.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func writeImmutableFile(_ data: Data, to destination: URL) throws {
        let destination = try validateInternalURL(destination)
        try createDirectory(destination.deletingLastPathComponent())
        if fileManager.fileExists(atPath: destination.path) {
            guard try readData(at: destination) == data else {
                throw ProcessingArtifactStoreError.corruptData("Immutable file conflict")
            }
            return
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString).tmp")
        try writeSynced(data, to: temporary)
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try synchronizeDirectory(destination.deletingLastPathComponent())
    }

    private func readData(at url: URL) throws -> Data {
        try Data(contentsOf: validateInternalURL(url))
    }

    private func writeSynced(_ data: Data, to url: URL) throws {
        let url = try validateInternalURL(url)
        guard fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw ProcessingArtifactStoreError.corruptData("Could not create staged file")
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let directory = try validateInternalURL(directory)
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func isOlder(_ url: URL, than cutoff: Date) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values.contentModificationDate else { return false }
        return modified < cutoff
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch let error as ProcessingArtifactStoreError {
            throw error
        } catch {
            throw ProcessingArtifactStoreError.corruptData(error.localizedDescription)
        }
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
