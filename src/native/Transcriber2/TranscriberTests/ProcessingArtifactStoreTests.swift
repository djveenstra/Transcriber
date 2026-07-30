import Foundation
import Testing
@testable import Transcriber

private struct ForcedPointerFailure: Error {}
private struct ForcedAfterPreviousFailure: Error {}

@MainActor
struct ProcessingArtifactStoreTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func roundTripWritesValidArtifactAndPublishesManifest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let reference = try await fixture.store.writeArtifact(fixture.request)
        let read = try await fixture.store.readArtifact(
            reference,
            expectedRecordingID: fixture.recordingID
        )
        #expect(read.payload == fixture.request.payload)
        #expect(read.envelope.payload.digest == ProcessingArtifactStore.sha256(fixture.request.payload))

        let manifest = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])
        try await fixture.store.publish(manifest, expectedGeneration: nil)
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == manifest)
    }

    @Test func legacyOnlyReadDoesNotCreateAStoreOrInventPublication() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        do {
            _ = try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID)
            Issue.record("Expected legacy-only state")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .noPublishedManifest)
        }
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("ProcessingArtifacts").path
        ))
    }

    @Test func rejectsNonCanonicalIDsTraversalAndCrossRecordingReferences() async throws {
        #expect(throws: ProcessingArtifactStoreError.self) {
            _ = try ArtifactStoreID(rawValue: "../escape")
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let otherRecording = ArtifactStoreID()
        let crossReference = ProcessingArtifactReferenceV1(
            artifactID: fixture.request.artifactID,
            artifactKind: .transcription,
            recordingID: otherRecording,
            envelopeRelativePath: "../../escape"
        )
        do {
            _ = try await fixture.store.readArtifact(
                crossReference,
                expectedRecordingID: fixture.recordingID
            )
            Issue.record("Expected cross-recording rejection")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .wrongRecording)
        }
    }

    @Test func unknownEnvelopeVersionAndPayloadDigestMismatchFailClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let envelopeURL = fixture.envelopeURL
        let originalEnvelope = try Data(contentsOf: envelopeURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: originalEnvelope) as? [String: Any]
        )
        object["envelope_schema_version"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: envelopeURL)

        do {
            _ = try await fixture.store.readArtifact(reference, expectedRecordingID: fixture.recordingID)
            Issue.record("Expected unknown schema rejection")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .unknownSchemaVersion(99))
        }

        try originalEnvelope.write(to: envelopeURL)
        try Data("tampered".utf8).write(to: fixture.payloadURL)
        do {
            _ = try await fixture.store.readArtifact(reference, expectedRecordingID: fixture.recordingID)
            Issue.record("Expected digest mismatch")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .digestMismatch)
        }
    }

    @Test func corruptEnvelopeAndMissingPayloadAreIsolatedReadFailures() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let originalEnvelope = try Data(contentsOf: fixture.envelopeURL)
        try Data("{".utf8).write(to: fixture.envelopeURL)
        do {
            _ = try await fixture.store.readArtifact(reference, expectedRecordingID: fixture.recordingID)
            Issue.record("Expected corrupt envelope")
        } catch {
            #expect(error as? ProcessingArtifactStoreError != nil)
        }

        try originalEnvelope.write(to: fixture.envelopeURL)
        try FileManager.default.removeItem(at: fixture.payloadURL)
        do {
            _ = try await fixture.store.readArtifact(reference, expectedRecordingID: fixture.recordingID)
            Issue.record("Expected missing payload")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .missingPayload)
        }
    }

    @Test func staleGenerationCannotPublishOverCurrent() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let first = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])
        try await fixture.store.publish(first, expectedGeneration: nil)

        let second = makeManifest(fixture: fixture, generation: 2, artifacts: [reference])
        do {
            try await fixture.store.publish(second, expectedGeneration: nil)
            Issue.record("Expected stale generation")
        } catch {
            #expect(
                error as? ProcessingArtifactStoreError
                    == .staleGeneration(expected: nil, actual: 1)
            )
        }
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == first)
    }

    @Test func currentPreviousIsTheOnlyFallbackForCorruptCurrent() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let first = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])
        try await fixture.store.publish(first, expectedGeneration: nil)
        let second = makeManifest(fixture: fixture, generation: 2, artifacts: [reference])
        try await fixture.store.publish(second, expectedGeneration: 1)

        try Data("corrupt".utf8).write(to: fixture.manifestURL(generation: 2))
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == first)
    }

    @Test func independentlyValidPreviousCanRecoverAnUndecodableCurrentPointer() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let first = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])
        try await fixture.store.publish(first, expectedGeneration: nil)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 2, artifacts: [reference]),
            expectedGeneration: 1
        )
        try Data("corrupt".utf8).write(to: fixture.currentPointerURL)
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == first)
    }

    @Test func corruptPointerBlocksLoadAndCleanupRatherThanLookingLikeNoStore() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 1, artifacts: [reference]),
            expectedGeneration: nil
        )
        try Data("{".utf8).write(to: fixture.currentPointerURL)

        do {
            _ = try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID)
            Issue.record("Corrupt pointer must fail closed")
        } catch {
            #expect(error as? ProcessingArtifactStoreError != .noPublishedManifest)
        }
        do {
            _ = try await fixture.store.cleanupUnpublished(
                recordingID: fixture.recordingID,
                olderThan: .distantFuture
            )
            Issue.record("Cleanup must stop on corrupt pointer state")
        } catch {
            #expect(
                error as? ProcessingArtifactStoreError
                    == .cleanupBlocked("Pointer state is corrupt")
            )
        }
        #expect(FileManager.default.fileExists(atPath: fixture.artifactDirectory(reference.artifactID).path))
    }

    @Test func previousPointerMustExactlyMatchCurrentPriorLink() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 1, artifacts: [reference]),
            expectedGeneration: nil
        )
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 2, artifacts: [reference]),
            expectedGeneration: 1
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.currentPointerURL))
                as? [String: Any]
        )
        object["prior_manifest_digest"] = String(repeating: "0", count: 64)
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.currentPointerURL)

        do {
            _ = try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID)
            Issue.record("Mismatched previous linkage must fail closed")
        } catch {
            #expect(error as? ProcessingArtifactStoreError
                == .invalidPointerState("Previous pointer linkage mismatch"))
        }
    }

    @Test func publishAndReadRejectMissingWrongKindSourceMismatchAndCycles() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missingID = ArtifactStoreID()
        let missingReference = ProcessingArtifactReferenceV1(
            artifactID: missingID,
            artifactKind: .transcription,
            recordingID: fixture.recordingID,
            envelopeRelativePath: fixture.envelopeRelativePath(missingID)
        )
        let missingChild = request(
            from: fixture.request,
            artifactID: ArtifactStoreID(),
            parents: [missingReference]
        )
        let missingChildReference = try await fixture.store.writeArtifact(missingChild)
        do {
            _ = try await fixture.store.readArtifact(
                missingChildReference,
                expectedRecordingID: fixture.recordingID
            )
            Issue.record("Missing graph reference must fail")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .missingReference(missingID.rawValue))
        }

        let parentReference = try await fixture.store.writeArtifact(fixture.request)
        let wrongKindReference = ProcessingArtifactReferenceV1(
            artifactID: parentReference.artifactID,
            artifactKind: .diarization,
            recordingID: fixture.recordingID,
            envelopeRelativePath: parentReference.envelopeRelativePath
        )
        let wrongKindChild = request(
            from: fixture.request,
            artifactID: ArtifactStoreID(),
            parents: [wrongKindReference]
        )
        let wrongKindChildReference = try await fixture.store.writeArtifact(wrongKindChild)
        await #expect(throws: ProcessingArtifactStoreError.self) {
            _ = try await fixture.store.readArtifact(
                wrongKindChildReference,
                expectedRecordingID: fixture.recordingID
            )
        }

        let otherSourceChild = request(
            from: fixture.request,
            artifactID: ArtifactStoreID(),
            sourceAudioID: ArtifactStoreID(),
            parents: [parentReference]
        )
        let otherSourceReference = try await fixture.store.writeArtifact(otherSourceChild)
        do {
            _ = try await fixture.store.readArtifact(
                otherSourceReference,
                expectedRecordingID: fixture.recordingID
            )
            Issue.record("Mixed source-audio graph must fail")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .sourceAudioMismatch)
        }

        let cycleAID = ArtifactStoreID()
        let cycleBID = ArtifactStoreID()
        let cycleARef = ProcessingArtifactReferenceV1(
            artifactID: cycleAID,
            artifactKind: .transcription,
            recordingID: fixture.recordingID,
            envelopeRelativePath: fixture.envelopeRelativePath(cycleAID)
        )
        let cycleBRef = ProcessingArtifactReferenceV1(
            artifactID: cycleBID,
            artifactKind: .transcription,
            recordingID: fixture.recordingID,
            envelopeRelativePath: fixture.envelopeRelativePath(cycleBID)
        )
        _ = try await fixture.store.writeArtifact(
            request(from: fixture.request, artifactID: cycleAID, parents: [cycleBRef])
        )
        let cycleB = try await fixture.store.writeArtifact(
            request(from: fixture.request, artifactID: cycleBID, parents: [cycleARef])
        )
        do {
            try await fixture.store.publish(
                makeManifest(fixture: fixture, generation: 1, artifacts: [cycleB]),
                expectedGeneration: nil
            )
            Issue.record("Cyclic graph must not publish")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .cyclicReference(cycleBID.rawValue)
                || error as? ProcessingArtifactStoreError == .cyclicReference(cycleAID.rawValue))
        }
    }

    @Test func cleanupRetainsArtifactsNamedByEarlierValidManifest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstReference = try await fixture.store.writeArtifact(fixture.request)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 1, artifacts: [firstReference]),
            expectedGeneration: nil
        )
        let secondRequest = makeRequest(
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            payload: Data("second".utf8)
        )
        let secondReference = try await fixture.store.writeArtifact(secondRequest)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 2, artifacts: [secondReference]),
            expectedGeneration: 1
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)],
            ofItemAtPath: fixture.artifactDirectory(firstReference.artifactID).path
        )
        _ = try await fixture.store.cleanupUnpublished(
            recordingID: fixture.recordingID,
            olderThan: fixedDate
        )
        #expect(FileManager.default.fileExists(
            atPath: fixture.artifactDirectory(firstReference.artifactID).path
        ))
    }

    @Test func symlinkEscapesAreRejectedForArtifactAndPointerPaths() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture.storeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.storeRoot.appendingPathComponent("recordings"),
            withDestinationURL: outside
        )
        await #expect(throws: ProcessingArtifactStoreError.self) {
            _ = try await fixture.store.writeArtifact(fixture.request)
        }

        try FileManager.default.removeItem(at: fixture.storeRoot.appendingPathComponent("recordings"))
        let reference = try await fixture.store.writeArtifact(fixture.request)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 1, artifacts: [reference]),
            expectedGeneration: nil
        )
        let outsidePointer = outside.appendingPathComponent("pointer")
        try Data(contentsOf: fixture.currentPointerURL).write(to: outsidePointer)
        try FileManager.default.removeItem(at: fixture.currentPointerURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.currentPointerURL,
            withDestinationURL: outsidePointer
        )
        await #expect(throws: ProcessingArtifactStoreError.self) {
            _ = try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID)
        }
    }

    @Test func interruptedSecondPublicationLeavesPointersUnchangedAndNoStagedPointers() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let first = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])
        try await fixture.store.publish(first, expectedGeneration: nil)
        let originalCurrent = try Data(contentsOf: fixture.currentPointerURL)
        let failingStore = ProcessingArtifactStore(
            applicationSupportRoot: fixture.root,
            beforePointerCommit: { throw ForcedPointerFailure() }
        )
        do {
            try await failingStore.publish(
                makeManifest(fixture: fixture, generation: 2, artifacts: [reference]),
                expectedGeneration: 1
            )
            Issue.record("Expected interruption")
        } catch is ForcedPointerFailure {}

        #expect(try Data(contentsOf: fixture.currentPointerURL) == originalCurrent)
        #expect(!FileManager.default.fileExists(atPath: fixture.previousPointerURL.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.manifestsDirectory.path)
        #expect(!names.contains { $0.hasSuffix(".tmp") })
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == first)
    }

    @Test func generationTwoBoundaryFailureKeepsOldCurrentReadableAndRetryable() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstReference = try await fixture.store.writeArtifact(fixture.request)
        let first = makeManifest(fixture: fixture, generation: 1, artifacts: [firstReference])
        try await fixture.store.publish(first, expectedGeneration: nil)

        let secondRequest = makeRequest(
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            payload: Data("generation-two".utf8)
        )
        let secondReference = try await fixture.store.writeArtifact(secondRequest)
        let second = makeManifest(fixture: fixture, generation: 2, artifacts: [secondReference])
        let failingStore = ProcessingArtifactStore(
            applicationSupportRoot: fixture.root,
            afterPreviousPointerCommit: { throw ForcedAfterPreviousFailure() }
        )
        do {
            try await failingStore.publish(second, expectedGeneration: 1)
            Issue.record("Expected failure between pointer replacements")
        } catch is ForcedAfterPreviousFailure {}

        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == first)
        #expect(try Data(contentsOf: fixture.currentPointerURL)
            == Data(contentsOf: fixture.previousPointerURL))
        try markOld([firstReference.artifactID, secondReference.artifactID], fixture: fixture)
        _ = try await fixture.store.cleanupUnpublished(
            recordingID: fixture.recordingID,
            olderThan: fixedDate
        )
        #expect(FileManager.default.fileExists(
            atPath: fixture.artifactDirectory(firstReference.artifactID).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: fixture.artifactDirectory(secondReference.artifactID).path
        ))

        try await fixture.store.publish(second, expectedGeneration: 1)
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == second)
    }

    @Test func generationThreeBoundaryFailurePreservesProtectedHistoryAndRetries() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstReference = try await fixture.store.writeArtifact(fixture.request)
        try await fixture.store.publish(
            makeManifest(fixture: fixture, generation: 1, artifacts: [firstReference]),
            expectedGeneration: nil
        )
        let secondRequest = makeRequest(
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            payload: Data("generation-two".utf8)
        )
        let secondReference = try await fixture.store.writeArtifact(secondRequest)
        let second = makeManifest(fixture: fixture, generation: 2, artifacts: [secondReference])
        try await fixture.store.publish(second, expectedGeneration: 1)
        let thirdRequest = makeRequest(
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            payload: Data("generation-three".utf8)
        )
        let thirdReference = try await fixture.store.writeArtifact(thirdRequest)
        let third = makeManifest(fixture: fixture, generation: 3, artifacts: [thirdReference])
        let failingStore = ProcessingArtifactStore(
            applicationSupportRoot: fixture.root,
            afterPreviousPointerCommit: { throw ForcedAfterPreviousFailure() }
        )
        do {
            try await failingStore.publish(third, expectedGeneration: 2)
            Issue.record("Expected generation-three boundary failure")
        } catch is ForcedAfterPreviousFailure {}

        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == second)
        #expect(try Data(contentsOf: fixture.currentPointerURL)
            == Data(contentsOf: fixture.previousPointerURL))
        try markOld(
            [firstReference.artifactID, secondReference.artifactID, thirdReference.artifactID],
            fixture: fixture
        )
        _ = try await fixture.store.cleanupUnpublished(
            recordingID: fixture.recordingID,
            olderThan: fixedDate
        )
        for artifactID in [
            firstReference.artifactID,
            secondReference.artifactID,
            thirdReference.artifactID,
        ] {
            #expect(FileManager.default.fileExists(
                atPath: fixture.artifactDirectory(artifactID).path
            ))
        }

        try await fixture.store.publish(third, expectedGeneration: 2)
        #expect(try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID) == third)
    }

    @Test func pointerFailureLeavesHigherManifestUnpublishedForRollback() async throws {
        let fixture = try makeFixture(beforePointerCommit: { throw ForcedPointerFailure() })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        let manifest = makeManifest(fixture: fixture, generation: 1, artifacts: [reference])

        do {
            try await fixture.store.publish(manifest, expectedGeneration: nil)
            Issue.record("Expected pointer failure")
        } catch is ForcedPointerFailure {
            // Expected.
        }
        #expect(FileManager.default.fileExists(atPath: fixture.manifestURL(generation: 1).path))
        do {
            _ = try await fixture.store.loadPublishedManifest(recordingID: fixture.recordingID)
            Issue.record("Unpointed manifest must not be promoted")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .noPublishedManifest)
        }
    }

    @Test func duplicateArtifactIDAllowsIdentityButRejectsChangedPayload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await fixture.store.writeArtifact(fixture.request)
        #expect(try await fixture.store.writeArtifact(fixture.request) == first)

        let changed = ProcessingArtifactWriteRequest(
            artifactID: fixture.request.artifactID,
            artifactKind: fixture.request.artifactKind,
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            pipelineRunID: fixture.request.pipelineRunID,
            attemptID: fixture.request.attemptID,
            payloadSchemaVersion: 1,
            payloadEncoding: "json",
            payload: Data("changed".utf8),
            componentID: "test",
            componentVersion: "1",
            parents: [],
            inputs: [],
            privacyClass: .transcriptPrivate,
            createdAt: fixedDate
        )
        do {
            _ = try await fixture.store.writeArtifact(changed)
            Issue.record("Expected immutable conflict")
        } catch {
            #expect(error as? ProcessingArtifactStoreError == .duplicateArtifactConflict)
        }
    }

    @Test func cleanupRemovesOnlyOldUnpublishedMaterialAndKeepsPublishedArtifact() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let publishedReference = try await fixture.store.writeArtifact(fixture.request)
        let manifest = makeManifest(fixture: fixture, generation: 1, artifacts: [publishedReference])
        try await fixture.store.publish(manifest, expectedGeneration: nil)

        let orphanRequest = makeRequest(
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            payload: Data("orphan".utf8)
        )
        _ = try await fixture.store.writeArtifact(orphanRequest)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: fixture.artifactDirectory(orphanRequest.artifactID).path
        )

        let report = try await fixture.store.cleanupUnpublished(
            recordingID: fixture.recordingID,
            olderThan: fixedDate
        )
        #expect(report.removedRelativePaths.contains {
            $0.contains(orphanRequest.artifactID.rawValue)
        })
        #expect(FileManager.default.fileExists(
            atPath: fixture.artifactDirectory(fixture.request.artifactID).path
        ))
    }

    @Test func corruptUnknownManifestBlocksDestructiveCleanup() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reference = try await fixture.store.writeArtifact(fixture.request)
        try FileManager.default.createDirectory(
            at: fixture.manifestsDirectory,
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(to: fixture.manifestURL(generation: 99))

        do {
            _ = try await fixture.store.cleanupUnpublished(
                recordingID: fixture.recordingID,
                olderThan: Date.distantFuture
            )
            Issue.record("Expected cleanup block")
        } catch {
            #expect(
                error as? ProcessingArtifactStoreError
                    == .cleanupBlocked("Unknown or corrupt manifest")
            )
        }
        #expect(FileManager.default.fileExists(
            atPath: fixture.artifactDirectory(reference.artifactID).path
        ))
    }

    private func makeFixture(
        beforePointerCommit: @escaping ProcessingArtifactStore.BeforePointerCommit = {}
    ) throws -> ArtifactStoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vx05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordingID = ArtifactStoreID()
        let sourceAudioID = ArtifactStoreID()
        let store = ProcessingArtifactStore(
            applicationSupportRoot: root,
            beforePointerCommit: beforePointerCommit
        )
        return ArtifactStoreFixture(
            root: root,
            store: store,
            recordingID: recordingID,
            sourceAudioID: sourceAudioID,
            request: makeRequest(
                recordingID: recordingID,
                sourceAudioID: sourceAudioID,
                payload: Data(#"{"text":"invented"}"#.utf8)
            )
        )
    }

    private func makeRequest(
        recordingID: ArtifactStoreID,
        sourceAudioID: ArtifactStoreID,
        payload: Data
    ) -> ProcessingArtifactWriteRequest {
        ProcessingArtifactWriteRequest(
            artifactID: ArtifactStoreID(),
            artifactKind: .transcription,
            recordingID: recordingID,
            sourceAudioID: sourceAudioID,
            pipelineRunID: ArtifactStoreID(),
            attemptID: ArtifactStoreID(),
            payloadSchemaVersion: 1,
            payloadEncoding: "json",
            payload: payload,
            componentID: "test",
            componentVersion: "1",
            parents: [],
            inputs: [],
            privacyClass: .transcriptPrivate,
            createdAt: fixedDate
        )
    }

    private func request(
        from base: ProcessingArtifactWriteRequest,
        artifactID: ArtifactStoreID,
        sourceAudioID: ArtifactStoreID? = nil,
        parents: [ProcessingArtifactReferenceV1]
    ) -> ProcessingArtifactWriteRequest {
        ProcessingArtifactWriteRequest(
            artifactID: artifactID,
            artifactKind: base.artifactKind,
            recordingID: base.recordingID,
            sourceAudioID: sourceAudioID ?? base.sourceAudioID,
            pipelineRunID: base.pipelineRunID,
            attemptID: base.attemptID,
            payloadSchemaVersion: base.payloadSchemaVersion,
            payloadEncoding: base.payloadEncoding,
            payload: Data("graph-\(artifactID.rawValue)".utf8),
            componentID: base.componentID,
            componentVersion: base.componentVersion,
            parents: parents,
            inputs: [],
            privacyClass: base.privacyClass,
            createdAt: base.createdAt
        )
    }

    private func markOld(
        _ artifactIDs: [ArtifactStoreID],
        fixture: ArtifactStoreFixture
    ) throws {
        for artifactID in artifactIDs {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)],
                ofItemAtPath: fixture.artifactDirectory(artifactID).path
            )
        }
    }

    private func makeManifest(
        fixture: ArtifactStoreFixture,
        generation: Int,
        artifacts: [ProcessingArtifactReferenceV1]
    ) -> ProcessingArtifactManifestV1 {
        ProcessingArtifactManifestV1(
            manifestSchemaVersion: 1,
            recordingID: fixture.recordingID,
            sourceAudioID: fixture.sourceAudioID,
            generation: generation,
            createdAt: fixedDate,
            artifacts: artifacts
        )
    }
}

private struct ArtifactStoreFixture {
    let root: URL
    let store: ProcessingArtifactStore
    let recordingID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let request: ProcessingArtifactWriteRequest

    var storeRoot: URL {
        root.appendingPathComponent("ProcessingArtifacts/store-v1", isDirectory: true)
    }

    var recordingDirectory: URL {
        storeRoot.appendingPathComponent("recordings/\(recordingID.rawValue)", isDirectory: true)
    }

    var manifestsDirectory: URL {
        recordingDirectory.appendingPathComponent("manifests", isDirectory: true)
    }

    var currentPointerURL: URL {
        manifestsDirectory.appendingPathComponent("current")
    }

    var previousPointerURL: URL {
        manifestsDirectory.appendingPathComponent("current.previous")
    }

    var envelopeURL: URL {
        artifactDirectory(request.artifactID).appendingPathComponent("envelope.json")
    }

    var payloadURL: URL {
        artifactDirectory(request.artifactID).appendingPathComponent("payload.bin")
    }

    func artifactDirectory(_ artifactID: ArtifactStoreID) -> URL {
        recordingDirectory
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(artifactID.rawValue, isDirectory: true)
    }

    func envelopeRelativePath(_ artifactID: ArtifactStoreID) -> String {
        "recordings/\(recordingID.rawValue)/artifacts/\(artifactID.rawValue)/envelope.json"
    }

    func manifestURL(generation: Int) -> URL {
        manifestsDirectory.appendingPathComponent("manifest-\(generation).json")
    }
}
