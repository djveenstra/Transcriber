import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import Transcriber

private struct InjectedPreparationInterruption: Error {}
private struct InjectedPreparationCrash: AudioPreparationCrashSimulation {}

@MainActor
struct AudioPreparationServiceTests {
    @Test func stereo44100ConvertsToMono16000AndReusesDeterministically() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 44_100,
            channels: 2,
            frameCount: 44_100
        ) { frame, channel in
            let frequency = channel == 0 ? 440.0 : 660.0
            return Float(sin(2 * .pi * frequency * Double(frame) / 44_100) * 0.4)
        }
        let original = try Data(contentsOf: fixture.source)
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)

        let first = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        let firstDerivative = fixture.derivatives
            .appendingPathComponent(first.output.relativeFileName)
        let derivativeBytes = try Data(contentsOf: firstDerivative)
        let second = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        let outputFile = try AVAudioFile(forReading: firstDerivative)

        #expect(first == second)
        #expect(first.source.sampleRateHz == 44_100)
        #expect(first.source.channelCount == 2)
        #expect(first.source.frameCount == 44_100)
        #expect(first.output.sampleRateHz == 16_000)
        #expect(first.output.channelCount == 1)
        #expect(abs(first.output.frameCount - 16_000) <= 1)
        #expect(outputFile.fileFormat.channelCount == 1)
        #expect(outputFile.fileFormat.sampleRate == 16_000)
        #expect(try Data(contentsOf: firstDerivative) == derivativeBytes)
        #expect(try Data(contentsOf: fixture.source) == original)
        #expect(first.timeMapping.originalStartUs == 0)
        #expect(first.timeMapping.preparedStartFrame == 0)
    }

    @Test func qualityMeasurementsReportLevelClippingSilenceAndSpeechRegions() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 16_000
        ) { frame, _ in
            switch frame {
            case 0..<4_000, 12_000..<16_000:
                return 0
            case 4_000..<8_000:
                return Float(sin(2 * .pi * 440 * Double(frame) / 16_000) * 0.5)
            default:
                return frame.isMultiple(of: 2) ? 1 : -1
            }
        }
        let originalDigest = try digest(fixture.source)

        let result = try await AudioPreparationService(
            derivativeRoot: fixture.derivatives
        ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)

        #expect(result.quality.peakAmplitude >= 0.99)
        #expect(result.quality.rmsAmplitude > 0)
        #expect(result.quality.rmsDBFS != nil)
        #expect(result.quality.clippedSampleCount >= 3_900)
        #expect(result.quality.clippingRatio > 0.24)
        #expect(result.quality.silenceRatio > 0.45)
        #expect(result.quality.silenceRegions.count == 2)
        #expect(!result.quality.conservativeSpeechRegions.isEmpty)
        #expect(try digest(fixture.source) == originalDigest)
    }

    @Test func sourceAndRecipeChangesInvalidatePriorPublication() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 22_050,
            channels: 1,
            frameCount: 11_025
        ) { _, _ in 0.2 }
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)
        let first = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        try writeAudio(
            to: fixture.source,
            sampleRate: 22_050,
            channels: 1,
            frameCount: 11_025
        ) { _, _ in 0.3 }
        let changedSourceBytes = try Data(contentsOf: fixture.source)
        let changedSource = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        var changedRecipe = AudioPreparationRecipeV1.current
        changedRecipe = AudioPreparationRecipeV1(
            recipeVersion: changedRecipe.recipeVersion,
            converterVersion: changedRecipe.converterVersion,
            qualityVersion: changedRecipe.qualityVersion,
            outputSampleRateHz: changedRecipe.outputSampleRateHz,
            outputChannelCount: changedRecipe.outputChannelCount,
            outputSampleFormat: changedRecipe.outputSampleFormat,
            clippingAmplitudeThreshold: 0.98,
            silenceRMSDBFSThreshold: changedRecipe.silenceRMSDBFSThreshold,
            speechRMSDBFSThreshold: changedRecipe.speechRMSDBFSThreshold,
            analysisWindowFrames: changedRecipe.analysisWindowFrames
        )
        let changedRecipeResult = try await AudioPreparationService(
            derivativeRoot: fixture.derivatives,
            recipe: changedRecipe
        ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)
        let publishedFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.derivatives,
            includingPropertiesForKeys: nil
        ).filter { !$0.lastPathComponent.hasPrefix(".") }

        #expect(first.regenerationKey != changedSource.regenerationKey)
        #expect(first.derivativeArtifactID != changedSource.derivativeArtifactID)
        #expect(changedSource.regenerationKey != changedRecipeResult.regenerationKey)
        #expect(changedSource.derivativeArtifactID != changedRecipeResult.derivativeArtifactID)
        #expect(publishedFiles.count == 2)
        #expect(try Data(contentsOf: fixture.source) == changedSourceBytes)
    }

    @Test func interruptedPublicationLeavesNoAuthoritativeResultAndPreservesSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 48_000,
            channels: 2,
            frameCount: 4_800
        ) { _, _ in 0.1 }
        let original = try Data(contentsOf: fixture.source)
        let interrupted = AudioPreparationService(
            derivativeRoot: fixture.derivatives,
            afterDerivativePublication: { throw InjectedPreparationInterruption() }
        )

        await #expect(throws: InjectedPreparationInterruption.self) {
            _ = try await interrupted.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        let remaining = try FileManager.default.contentsOfDirectory(
            atPath: fixture.derivatives.path
        )
        #expect(remaining.isEmpty)
        #expect(try Data(contentsOf: fixture.source) == original)

        _ = try await AudioPreparationService(
            derivativeRoot: fixture.derivatives
        ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)
        #expect(try Data(contentsOf: fixture.source) == original)
    }

    @Test func emptyInvalidAndCleanupCasesNeverAlterSource() async throws {
        let empty = try makeFixture()
        defer { try? FileManager.default.removeItem(at: empty.root) }
        try writeAudio(
            to: empty.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 0
        ) { _, _ in 0 }
        let emptyBytes = try Data(contentsOf: empty.source)
        let service = AudioPreparationService(derivativeRoot: empty.derivatives)
        let emptyResult = try await service.prepare(
            sourceURL: empty.source,
            sourceAudioID: empty.sourceID
        )
        #expect(emptyResult.output.frameCount == 0)
        #expect(emptyResult.quality.clippingRatio == 0)
        #expect(emptyResult.quality.silenceRatio == 0)
        try await service.invalidate(
            sourceURL: empty.source,
            sourceAudioID: empty.sourceID
        )
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: empty.derivatives.path
        ).isEmpty)
        #expect(try Data(contentsOf: empty.source) == emptyBytes)

        let invalid = try makeFixture()
        defer { try? FileManager.default.removeItem(at: invalid.root) }
        let invalidBytes = Data("not audio".utf8)
        try invalidBytes.write(to: invalid.source)
        await #expect(throws: (any Error).self) {
            _ = try await AudioPreparationService(
                derivativeRoot: invalid.derivatives
            ).prepare(sourceURL: invalid.source, sourceAudioID: invalid.sourceID)
        }
        #expect(try Data(contentsOf: invalid.source) == invalidBytes)
    }

    @Test func exactAndSymlinkSourceCollisionsAreRejectedForPrepareAndInvalidate() async throws {
        for (targetExtension, useAlias) in [
            ("caf", false),
            ("caf", true),
            ("json", false),
            ("json", true),
        ] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vx07-collision-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let derivatives = root.appendingPathComponent("derivatives", isDirectory: true)
            try FileManager.default.createDirectory(
                at: derivatives,
                withIntermediateDirectories: true
            )
            let sourceID = ArtifactStoreID()
            let generatedSource = derivatives.appendingPathComponent(
                "\(sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).\(targetExtension)"
            )
            if targetExtension == "caf" {
                try writeAudio(
                    to: generatedSource,
                    sampleRate: 16_000,
                    channels: 1,
                    frameCount: 800
                ) { _, _ in 0.25 }
            } else {
                try Data("source bytes in sidecar path".utf8).write(to: generatedSource)
            }
            let sourceURL: URL
            if useAlias {
                sourceURL = root.appendingPathComponent("source-alias.caf")
                try FileManager.default.createSymbolicLink(
                    at: sourceURL,
                    withDestinationURL: generatedSource
                )
            } else {
                sourceURL = generatedSource
            }
            let bytes = try Data(contentsOf: generatedSource)
            let digestBefore = try digest(generatedSource)
            let service = AudioPreparationService(derivativeRoot: derivatives)

            await #expect(throws: AudioPreparationError.sourceCollidesWithGeneratedPath) {
                _ = try await service.prepare(
                    sourceURL: sourceURL,
                    sourceAudioID: sourceID
                )
            }
            await #expect(throws: AudioPreparationError.sourceCollidesWithGeneratedPath) {
                try await service.invalidate(
                    sourceURL: sourceURL,
                    sourceAudioID: sourceID
                )
            }
            #expect(try Data(contentsOf: generatedSource) == bytes)
            #expect(try digest(generatedSource) == digestBefore)
        }
    }

    @Test func generatedPathSymlinkEscapeIsRejectedWithoutChangingOutsideFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 640
        ) { _, _ in 0.2 }
        try FileManager.default.createDirectory(
            at: fixture.derivatives,
            withIntermediateDirectories: true
        )
        let outside = fixture.root.appendingPathComponent("outside.caf")
        let outsideBytes = Data("outside must remain".utf8)
        try outsideBytes.write(to: outside)
        let generatedPath = fixture.derivatives.appendingPathComponent(
            "\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).caf"
        )
        try FileManager.default.createSymbolicLink(
            at: generatedPath,
            withDestinationURL: outside
        )
        let sourceBytes = try Data(contentsOf: fixture.source)

        await #expect(throws: AudioPreparationError.pathEscapedDerivativeRoot) {
            _ = try await AudioPreparationService(
                derivativeRoot: fixture.derivatives
            ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)
        }
        #expect(try Data(contentsOf: outside) == outsideBytes)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func unownedDeterministicFileIsNeverTreatedAsGeneratedCleanup() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 640
        ) { _, _ in 0.2 }
        try FileManager.default.createDirectory(
            at: fixture.derivatives,
            withIntermediateDirectories: true
        )
        let deterministicFile = fixture.derivatives.appendingPathComponent(
            "\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).caf"
        )
        let unrelatedBytes = Data("not owned by audio preparation".utf8)
        try unrelatedBytes.write(to: deterministicFile)
        let sourceBytes = try Data(contentsOf: fixture.source)
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)

        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            _ = try await service.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            try await service.invalidate(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        #expect(try Data(contentsOf: deterministicFile) == unrelatedBytes)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func shortNonemptyInputAndPublishedFileAreFloat32() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 160
        ) { frame, _ in frame.isMultiple(of: 2) ? 0.2 : -0.2 }

        let result = try await AudioPreparationService(
            derivativeRoot: fixture.derivatives
        ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)
        let outputFile = try AVAudioFile(
            forReading: fixture.derivatives.appendingPathComponent(
                result.output.relativeFileName
            )
        )

        #expect(result.output.frameCount == 160)
        #expect(result.quality.rmsAmplitude > 0)
        #expect(outputFile.fileFormat.commonFormat == .pcmFormatFloat32)
        #expect(outputFile.processingFormat.commonFormat == .pcmFormatFloat32)
    }

    @Test func derivativeCorruptionForcesVerifiedRegeneration() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { frame, _ in Float(sin(2 * .pi * 220 * Double(frame) / 16_000) * 0.3) }
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)
        let first = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        let derivative = fixture.derivatives.appendingPathComponent(
            first.output.relativeFileName
        )
        var corruptBytes = try Data(contentsOf: derivative)
        corruptBytes[corruptBytes.index(before: corruptBytes.endIndex)] ^= 0xff
        try corruptBytes.write(to: derivative)

        let repaired = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )

        #expect(repaired.derivativeArtifactID != first.derivativeArtifactID)
        #expect(repaired.output.digest == first.output.digest)
        #expect(repaired.output.byteCount == first.output.byteCount)
        #expect(try digest(derivative) == repaired.output.digest)
    }

    @Test func crashOrphanIsRecoveredByNewServiceInstance() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 32_000,
            channels: 1,
            frameCount: 3_200
        ) { _, _ in 0.15 }
        let sourceBytes = try Data(contentsOf: fixture.source)
        let crashing = AudioPreparationService(
            derivativeRoot: fixture.derivatives,
            afterDerivativePublication: { throw InjectedPreparationCrash() }
        )
        await #expect(throws: InjectedPreparationCrash.self) {
            _ = try await crashing.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        let orphanFiles = try FileManager.default.contentsOfDirectory(
            atPath: fixture.derivatives.path
        )
        #expect(orphanFiles.filter { $0.hasSuffix(".caf") }.count == 1)
        #expect(orphanFiles.filter {
            $0.hasSuffix(".json") && !$0.hasPrefix(".")
        }.isEmpty)
        #expect(orphanFiles.filter { $0.hasSuffix(".owner.json") }.count == 1)

        let recovered = try await AudioPreparationService(
            derivativeRoot: fixture.derivatives
        ).prepare(sourceURL: fixture.source, sourceAudioID: fixture.sourceID)
        #expect(FileManager.default.fileExists(
            atPath: fixture.derivatives.appendingPathComponent(
                recovered.output.relativeFileName
            ).path
        ))
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func forcedRegenerationAfterInvalidateIsReproducible() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 48_000,
            channels: 2,
            frameCount: 4_800
        ) { frame, channel in
            Float(sin(2 * .pi * Double(300 + channel * 100) * Double(frame) / 48_000) * 0.2)
        }
        let sourceBytes = try Data(contentsOf: fixture.source)
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)
        let first = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        try await service.invalidate(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        let regenerated = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )

        #expect(regenerated.derivativeArtifactID != first.derivativeArtifactID)
        #expect(regenerated.regenerationKey == first.regenerationKey)
        #expect(regenerated.output.digest == first.output.digest)
        #expect(regenerated.output.byteCount == first.output.byteCount)
        #expect(regenerated.quality == first.quality)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func structurallyValidWrongDigestAndKeyMarkerCannotAuthorizeDeletion() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { _, _ in 0.2 }
        try await leaveCrashOrphan(fixture)
        let markerURL = ownershipMarkerURL(fixture)
        var marker = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: markerURL))
                as? [String: Any]
        )
        marker["sourceDigest"] = String(repeating: "0", count: 64)
        marker["regenerationKey"] = String(repeating: "1", count: 64)
        try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
            .write(to: markerURL)
        let derivativeURL = deterministicDerivativeURL(fixture)
        let derivativeBytes = try Data(contentsOf: derivativeURL)
        let sourceBytes = try Data(contentsOf: fixture.source)
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)

        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            _ = try await service.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            try await service.invalidate(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        #expect(try Data(contentsOf: derivativeURL) == derivativeBytes)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func staleSameIDSourceMarkerFailsClosedWithoutDeletingOrphan() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { _, _ in 0.2 }
        try await leaveCrashOrphan(fixture)
        let derivativeURL = deterministicDerivativeURL(fixture)
        let derivativeBytes = try Data(contentsOf: derivativeURL)
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { _, _ in 0.35 }
        let changedSourceBytes = try Data(contentsOf: fixture.source)
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)

        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            _ = try await service.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            try await service.invalidate(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        #expect(try Data(contentsOf: derivativeURL) == derivativeBytes)
        #expect(try Data(contentsOf: fixture.source) == changedSourceBytes)
    }

    @Test func staleSameIDRecipeMarkerFailsClosedWithoutDeletingOrphan() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { _, _ in 0.2 }
        try await leaveCrashOrphan(fixture)
        let derivativeURL = deterministicDerivativeURL(fixture)
        let derivativeBytes = try Data(contentsOf: derivativeURL)
        let sourceBytes = try Data(contentsOf: fixture.source)
        let current = AudioPreparationRecipeV1.current
        let changedRecipe = AudioPreparationRecipeV1(
            recipeVersion: current.recipeVersion,
            converterVersion: current.converterVersion,
            qualityVersion: current.qualityVersion,
            outputSampleRateHz: current.outputSampleRateHz,
            outputChannelCount: current.outputChannelCount,
            outputSampleFormat: current.outputSampleFormat,
            clippingAmplitudeThreshold: 0.97,
            silenceRMSDBFSThreshold: current.silenceRMSDBFSThreshold,
            speechRMSDBFSThreshold: current.speechRMSDBFSThreshold,
            analysisWindowFrames: current.analysisWindowFrames
        )
        let changedService = AudioPreparationService(
            derivativeRoot: fixture.derivatives,
            recipe: changedRecipe
        )

        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            _ = try await changedService.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            try await changedService.invalidate(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        #expect(try Data(contentsOf: derivativeURL) == derivativeBytes)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func publishedMarkerCannotAuthorizeArbitraryDerivativeWithoutCoherentSidecar() async throws {
        for corruptSidecar in [false, true] {
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try writeAudio(
                to: fixture.source,
                sampleRate: 16_000,
                channels: 1,
                frameCount: 1_600
            ) { _, _ in 0.2 }
            let service = AudioPreparationService(derivativeRoot: fixture.derivatives)
            let published = try await service.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
            let derivativeURL = fixture.derivatives.appendingPathComponent(
                published.output.relativeFileName
            )
            let sidecarURL = fixture.derivatives.appendingPathComponent(
                "\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).json"
            )
            if corruptSidecar {
                try Data("corrupt sidecar".utf8).write(to: sidecarURL)
            } else {
                try FileManager.default.removeItem(at: sidecarURL)
            }
            let arbitraryBytes = Data("arbitrary deterministic occupant".utf8)
            try arbitraryBytes.write(to: derivativeURL)
            let sourceBytes = try Data(contentsOf: fixture.source)

            await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
                _ = try await service.prepare(
                    sourceURL: fixture.source,
                    sourceAudioID: fixture.sourceID
                )
            }
            await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
                try await service.invalidate(
                    sourceURL: fixture.source,
                    sourceAudioID: fixture.sourceID
                )
            }
            #expect(try Data(contentsOf: derivativeURL) == arbitraryBytes)
            #expect(try Data(contentsOf: fixture.source) == sourceBytes)
        }
    }

    @Test func halfPopulatedPublishedMarkerFailsClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeAudio(
            to: fixture.source,
            sampleRate: 16_000,
            channels: 1,
            frameCount: 1_600
        ) { _, _ in 0.2 }
        let service = AudioPreparationService(derivativeRoot: fixture.derivatives)
        let published = try await service.prepare(
            sourceURL: fixture.source,
            sourceAudioID: fixture.sourceID
        )
        let derivativeURL = fixture.derivatives.appendingPathComponent(
            published.output.relativeFileName
        )
        let derivativeBytes = try Data(contentsOf: derivativeURL)
        let sourceBytes = try Data(contentsOf: fixture.source)
        let sidecarURL = fixture.derivatives.appendingPathComponent(
            "\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).json"
        )
        try FileManager.default.removeItem(at: sidecarURL)
        let markerURL = ownershipMarkerURL(fixture)
        var marker = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: markerURL))
                as? [String: Any]
        )
        marker.removeValue(forKey: "publishedDerivativeByteCount")
        try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
            .write(to: markerURL)

        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            _ = try await service.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        await #expect(throws: AudioPreparationError.generatedOwnershipNotEstablished) {
            try await service.invalidate(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
        #expect(try Data(contentsOf: derivativeURL) == derivativeBytes)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    private func makeFixture() throws -> AudioPreparationFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vx07-\(UUID().uuidString)", isDirectory: true)
        let derivatives = root.appendingPathComponent("derivatives", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return AudioPreparationFixture(
            root: root,
            source: root.appendingPathComponent("source.caf"),
            derivatives: derivatives,
            sourceID: ArtifactStoreID()
        )
    }

    private func leaveCrashOrphan(_ fixture: AudioPreparationFixture) async throws {
        let crashing = AudioPreparationService(
            derivativeRoot: fixture.derivatives,
            afterDerivativePublication: { throw InjectedPreparationCrash() }
        )
        await #expect(throws: InjectedPreparationCrash.self) {
            _ = try await crashing.prepare(
                sourceURL: fixture.source,
                sourceAudioID: fixture.sourceID
            )
        }
    }

    private func deterministicDerivativeURL(_ fixture: AudioPreparationFixture) -> URL {
        fixture.derivatives.appendingPathComponent(
            "\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).caf"
        )
    }

    private func ownershipMarkerURL(_ fixture: AudioPreparationFixture) -> URL {
        fixture.derivatives.appendingPathComponent(
            ".\(fixture.sourceID.rawValue)-\(AudioPreparationRecipeV1.current.recipeVersion).owner.json"
        )
    }

    private func writeAudio(
        to url: URL,
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frameCount: AVAudioFrameCount,
        sample: (Int, Int) -> Float
    ) throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ))
        var file: AVAudioFile? = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard frameCount > 0 else {
            file = nil
            return
        }
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        for channel in 0..<Int(channels) {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frameCount) {
                samples[frame] = sample(frame, channel)
            }
        }
        try file?.write(from: buffer)
        file = nil
    }

    private func digest(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct AudioPreparationFixture {
    let root: URL
    let source: URL
    let derivatives: URL
    let sourceID: ArtifactStoreID
}
