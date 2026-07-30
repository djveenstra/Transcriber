import AVFoundation
import CryptoKit
import Darwin
import Foundation

nonisolated enum AudioPreparationError: Error, Equatable, Sendable {
    case invalidSource
    case conversionFailed(String)
    case sourceChangedDuringPreparation
    case invalidPublishedResult
    case pathEscapedDerivativeRoot
    case sourceCollidesWithGeneratedPath
    case generatedOwnershipNotEstablished
}

nonisolated protocol AudioPreparationCrashSimulation: Error {}

nonisolated struct AudioPreparationRecipeV1: Codable, Equatable, Sendable {
    static let current = AudioPreparationRecipeV1(
        recipeVersion: "prepared-audio-v1",
        converterVersion: "avfoundation-v1",
        qualityVersion: "quality-v1",
        outputSampleRateHz: 16_000,
        outputChannelCount: 1,
        outputSampleFormat: "float32",
        clippingAmplitudeThreshold: 0.999,
        silenceRMSDBFSThreshold: -50,
        speechRMSDBFSThreshold: -40,
        analysisWindowFrames: 320
    )

    let recipeVersion: String
    let converterVersion: String
    let qualityVersion: String
    let outputSampleRateHz: Double
    let outputChannelCount: Int
    let outputSampleFormat: String
    let clippingAmplitudeThreshold: Double
    let silenceRMSDBFSThreshold: Double
    let speechRMSDBFSThreshold: Double
    let analysisWindowFrames: Int
}

nonisolated struct PreparedAudioSourceMetadataV1: Codable, Equatable, Sendable {
    let containerExtension: String
    let formatID: UInt32
    let sampleRateHz: Double
    let channelCount: Int
    let channelLayoutTag: UInt32?
    let frameCount: Int64
    let measuredDurationSeconds: Double
    let sourceByteCount: Int64
    let sourceDigestAlgorithm: String
    let sourceDigest: String
}

nonisolated struct PreparedAudioOutputMetadataV1: Codable, Equatable, Sendable {
    let relativeFileName: String
    let sampleRateHz: Double
    let channelCount: Int
    let channelLayout: String
    let sampleFormat: String
    let frameCount: Int64
    let measuredDurationSeconds: Double
    let byteCount: Int64
    let digestAlgorithm: String
    let digest: String
}

nonisolated struct PreparedAudioTimeMappingV1: Codable, Equatable, Sendable {
    let timebase: String
    let preparedStartFrame: Int64
    let originalStartUs: Int64
    let preparedSampleRateHz: Double
}

nonisolated enum AudioQualityRegionKindV1: String, Codable, Sendable {
    case silence
    case conservativeSpeech = "conservative_speech"
}

nonisolated struct AudioQualityRegionV1: Codable, Equatable, Sendable {
    let kind: AudioQualityRegionKindV1
    let startUs: Int64
    let endUs: Int64
}

nonisolated struct AudioQualityMeasurementsV1: Codable, Equatable, Sendable {
    let algorithmVersion: String
    let amplitudeUnit: String
    let levelUnit: String
    let regionTimeUnit: String
    let peakAmplitude: Double
    let rmsAmplitude: Double
    let rmsDBFS: Double?
    let clippingThreshold: Double
    let clippedSampleCount: Int64
    let clippingRatio: Double
    let silenceRMSDBFSThreshold: Double
    let silenceRatio: Double
    let speechRMSDBFSThreshold: Double
    let silenceRegions: [AudioQualityRegionV1]
    let conservativeSpeechRegions: [AudioQualityRegionV1]
}

nonisolated struct PreparedAudioTransformStepV1: Codable, Equatable, Sendable {
    let componentID: String
    let componentVersion: String
    let configuration: String
}

nonisolated struct PreparedAudioV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let derivativeArtifactID: ArtifactStoreID
    let sourceAudioID: ArtifactStoreID
    let source: PreparedAudioSourceMetadataV1
    let output: PreparedAudioOutputMetadataV1
    let timeMapping: PreparedAudioTimeMappingV1
    let transforms: [PreparedAudioTransformStepV1]
    let quality: AudioQualityMeasurementsV1
    let recipe: AudioPreparationRecipeV1
    let regenerationKey: String
    let regenerable: Bool
    let failureReason: String?
    let exclusionReasons: [String]
}

nonisolated private struct GeneratedAudioOwnershipV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceAudioID: ArtifactStoreID
    let sourceDigest: String
    let recipeVersion: String
    let regenerationKey: String
    let derivativeFileName: String
    let sidecarFileName: String
    let publishedDerivativeDigest: String?
    let publishedDerivativeByteCount: Int64?
}

actor AudioPreparationService {
    typealias PublicationHook = @Sendable () throws -> Void

    private let derivativeRoot: URL
    private let recipe: AudioPreparationRecipeV1
    private let fileManager: FileManager
    private let afterDerivativePublication: PublicationHook

    init(
        derivativeRoot: URL,
        recipe: AudioPreparationRecipeV1 = .current,
        fileManager: FileManager = .default,
        afterDerivativePublication: @escaping PublicationHook = {}
    ) {
        self.derivativeRoot = derivativeRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.recipe = recipe
        self.fileManager = fileManager
        self.afterDerivativePublication = afterDerivativePublication
    }

    func prepare(sourceURL: URL, sourceAudioID: ArtifactStoreID) throws -> PreparedAudioV1 {
        let sourceDigestBefore = try Self.digest(url: sourceURL)
        let sourceByteCount = try fileSize(sourceURL)
        let regenerationKey = try Self.regenerationKey(
            sourceDigest: sourceDigestBefore,
            recipe: recipe
        )
        let baseName = "\(sourceAudioID.rawValue)-\(recipe.recipeVersion)"
        let derivativeURL = try containedURL(baseName + ".caf")
        let sidecarURL = try containedURL(baseName + ".json")
        let ownershipURL = try containedURL(".\(baseName).owner.json")
        try rejectSourceCollision(
            sourceURL: sourceURL,
            generatedURLs: [derivativeURL, sidecarURL, ownershipURL]
        )

        if let reusable = try reusableResult(
            sidecarURL: sidecarURL,
            derivativeURL: derivativeURL,
            sourceAudioID: sourceAudioID,
            sourceDigest: sourceDigestBefore,
            regenerationKey: regenerationKey
        ) {
            guard try Self.digest(url: sourceURL) == sourceDigestBefore else {
                throw AudioPreparationError.sourceChangedDuringPreparation
            }
            return reusable
        }
        try invalidateGenerated(
            derivativeURL: derivativeURL,
            sidecarURL: sidecarURL,
            sourceURL: sourceURL,
            sourceAudioID: sourceAudioID,
            ownershipURL: ownershipURL,
            expectedSourceDigest: sourceDigestBefore,
            expectedRegenerationKey: regenerationKey
        )
        try fileManager.createDirectory(
            at: derivativeRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let token = UUID().uuidString.lowercased()
        let temporaryDerivative = try containedURL(".\(baseName)-\(token).tmp.caf")
        let temporarySidecar = try containedURL(".\(baseName)-\(token).tmp.json")
        let temporaryOwnership = try containedURL(".\(baseName)-\(token).owner.tmp.json")
        do {
            let ownership = GeneratedAudioOwnershipV1(
                schemaVersion: 1,
                sourceAudioID: sourceAudioID,
                sourceDigest: sourceDigestBefore,
                recipeVersion: recipe.recipeVersion,
                regenerationKey: regenerationKey,
                derivativeFileName: derivativeURL.lastPathComponent,
                sidecarFileName: sidecarURL.lastPathComponent,
                publishedDerivativeDigest: nil,
                publishedDerivativeByteCount: nil
            )
            try writeSynchronized(Self.encoder.encode(ownership), to: temporaryOwnership)
            try replace(temporaryOwnership, at: ownershipURL)
            let sourceFile: AVAudioFile
            do {
                sourceFile = try AVAudioFile(forReading: sourceURL)
            } catch {
                throw AudioPreparationError.conversionFailed("open source: \(error)")
            }
            let sourceMetadata = PreparedAudioSourceMetadataV1(
                containerExtension: sourceURL.pathExtension.lowercased(),
                formatID: sourceFile.fileFormat.formatDescription.audioStreamBasicDescription?
                    .mFormatID ?? 0,
                sampleRateHz: sourceFile.fileFormat.sampleRate,
                channelCount: Int(sourceFile.fileFormat.channelCount),
                channelLayoutTag: sourceFile.fileFormat.channelLayout?.layoutTag,
                frameCount: sourceFile.length,
                measuredDurationSeconds: sourceFile.fileFormat.sampleRate > 0
                    ? Double(sourceFile.length) / sourceFile.fileFormat.sampleRate
                    : 0,
                sourceByteCount: sourceByteCount,
                sourceDigestAlgorithm: "sha256",
                sourceDigest: sourceDigestBefore
            )
            let analysis: (frameCount: Int64, quality: AudioQualityMeasurementsV1)
            do {
                analysis = try convert(
                    sourceFile: sourceFile,
                    destinationURL: temporaryDerivative
                )
            } catch {
                throw AudioPreparationError.conversionFailed("convert: \(error)")
            }
            do {
                try synchronizeFile(temporaryDerivative)
            } catch {
                throw AudioPreparationError.conversionFailed("sync derivative: \(error)")
            }
            try replace(temporaryDerivative, at: derivativeURL)
            try afterDerivativePublication()

            let derivativeDigest = try Self.digest(url: derivativeURL)
            let derivativeByteCount = try fileSize(derivativeURL)
            let publishedOwnership = GeneratedAudioOwnershipV1(
                schemaVersion: ownership.schemaVersion,
                sourceAudioID: ownership.sourceAudioID,
                sourceDigest: ownership.sourceDigest,
                recipeVersion: ownership.recipeVersion,
                regenerationKey: ownership.regenerationKey,
                derivativeFileName: ownership.derivativeFileName,
                sidecarFileName: ownership.sidecarFileName,
                publishedDerivativeDigest: derivativeDigest,
                publishedDerivativeByteCount: derivativeByteCount
            )
            try writeSynchronized(
                Self.encoder.encode(publishedOwnership),
                to: temporaryOwnership
            )
            try replace(temporaryOwnership, at: ownershipURL)
            let result = PreparedAudioV1(
                schemaVersion: PreparedAudioV1.schemaVersion,
                derivativeArtifactID: ArtifactStoreID(),
                sourceAudioID: sourceAudioID,
                source: sourceMetadata,
                output: PreparedAudioOutputMetadataV1(
                    relativeFileName: derivativeURL.lastPathComponent,
                    sampleRateHz: recipe.outputSampleRateHz,
                    channelCount: recipe.outputChannelCount,
                    channelLayout: "mono",
                    sampleFormat: recipe.outputSampleFormat,
                    frameCount: analysis.frameCount,
                    measuredDurationSeconds: Double(analysis.frameCount)
                        / recipe.outputSampleRateHz,
                    byteCount: derivativeByteCount,
                    digestAlgorithm: "sha256",
                    digest: derivativeDigest
                ),
                timeMapping: PreparedAudioTimeMappingV1(
                    timebase: "original_audio_start_us",
                    preparedStartFrame: 0,
                    originalStartUs: 0,
                    preparedSampleRateHz: recipe.outputSampleRateHz
                ),
                transforms: [
                    PreparedAudioTransformStepV1(
                        componentID: "avfoundation.audio-converter",
                        componentVersion: recipe.converterVersion,
                        configuration:
                            "mono;\(Int(recipe.outputSampleRateHz))hz;\(recipe.outputSampleFormat)"
                    )
                ],
                quality: analysis.quality,
                recipe: recipe,
                regenerationKey: regenerationKey,
                regenerable: true,
                failureReason: nil,
                exclusionReasons: []
            )
            let encoded = try Self.encoder.encode(result)
            try writeSynchronized(encoded, to: temporarySidecar)
            try replace(temporarySidecar, at: sidecarURL)
            let reopened = try decodeSidecar(sidecarURL)
            guard reopened == result,
                  try validateDerivative(result, at: derivativeURL),
                  try Self.digest(url: sourceURL) == sourceDigestBefore else {
                throw AudioPreparationError.invalidPublishedResult
            }
            return result
        } catch {
            if !(error is any AudioPreparationCrashSimulation) {
                try? removeGeneratedFile(temporaryDerivative, protecting: sourceURL)
                try? removeGeneratedFile(temporarySidecar, protecting: sourceURL)
                try? removeGeneratedFile(temporaryOwnership, protecting: sourceURL)
                try? invalidateGenerated(
                    derivativeURL: derivativeURL,
                    sidecarURL: sidecarURL,
                    sourceURL: sourceURL,
                    sourceAudioID: sourceAudioID,
                    ownershipURL: ownershipURL,
                    expectedSourceDigest: sourceDigestBefore,
                    expectedRegenerationKey: regenerationKey
                )
            }
            if (try? Self.digest(url: sourceURL)) != sourceDigestBefore {
                throw AudioPreparationError.sourceChangedDuringPreparation
            }
            throw error
        }
    }

    func invalidate(sourceURL: URL, sourceAudioID: ArtifactStoreID) throws {
        let expectedSourceDigest = try Self.digest(url: sourceURL)
        let expectedRegenerationKey = try Self.regenerationKey(
            sourceDigest: expectedSourceDigest,
            recipe: recipe
        )
        let baseName = "\(sourceAudioID.rawValue)-\(recipe.recipeVersion)"
        try invalidateGenerated(
            derivativeURL: containedURL(baseName + ".caf"),
            sidecarURL: containedURL(baseName + ".json"),
            sourceURL: sourceURL,
            sourceAudioID: sourceAudioID,
            ownershipURL: containedURL(".\(baseName).owner.json"),
            expectedSourceDigest: expectedSourceDigest,
            expectedRegenerationKey: expectedRegenerationKey
        )
    }

    private func convert(
        sourceFile: AVAudioFile,
        destinationURL: URL
    ) throws -> (frameCount: Int64, quality: AudioQualityMeasurementsV1) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: recipe.outputSampleRateHz,
            channels: AVAudioChannelCount(recipe.outputChannelCount),
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFile.processingFormat, to: outputFormat) else {
            throw AudioPreparationError.invalidSource
        }
        let destination: AVAudioFile
        do {
            destination = try AVAudioFile(
                forWriting: destinationURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioPreparationError.conversionFailed("open destination: \(error)")
        }
        var analyzer = AudioQualityAnalyzer(recipe: recipe)
        let inputState = AudioConversionInputState()
        while true {
            if inputState.inputBuffer == nil && !inputState.reachedEndOfSource {
                let remainingFrames = sourceFile.length - sourceFile.framePosition
                if remainingFrames <= 0 {
                    inputState.reachedEndOfSource = true
                    continue
                }
                let requestedFrames = AVAudioFrameCount(min(8_192, remainingFrames))
                guard let input = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat,
                    frameCapacity: requestedFrames
                ) else {
                    throw AudioPreparationError.conversionFailed(
                        "Could not allocate input buffer"
                    )
                }
                do {
                    try sourceFile.read(into: input, frameCount: requestedFrames)
                } catch {
                    throw AudioPreparationError.conversionFailed("read source: \(error)")
                }
                if input.frameLength == 0 {
                    inputState.reachedEndOfSource = true
                } else {
                    inputState.inputBuffer = input
                    inputState.didSupplyInput = false
                }
            }
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: 16_384
            ) else {
                throw AudioPreparationError.conversionFailed("Could not allocate output buffer")
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) {
                _, statusPointer in
                if let input = inputState.inputBuffer, !inputState.didSupplyInput {
                    inputState.didSupplyInput = true
                    statusPointer.pointee = .haveData
                    return input
                }
                if inputState.reachedEndOfSource {
                    statusPointer.pointee = .endOfStream
                    return nil
                }
                statusPointer.pointee = .noDataNow
                return nil
            }
            if let conversionError { throw conversionError }
            if output.frameLength > 0 {
                do {
                    try destination.write(from: output)
                } catch {
                    throw AudioPreparationError.conversionFailed("write destination: \(error)")
                }
                analyzer.consume(output)
            }
            if status == .endOfStream { break }
            if status == .inputRanDry {
                inputState.inputBuffer = nil
                continue
            }
            guard status == .haveData || status == .inputRanDry else {
                throw AudioPreparationError.conversionFailed("AVAudioConverter stopped")
            }
        }
        return (analyzer.frameCount, analyzer.finish())
    }

    private func reusableResult(
        sidecarURL: URL,
        derivativeURL: URL,
        sourceAudioID: ArtifactStoreID,
        sourceDigest: String,
        regenerationKey: String
    ) throws -> PreparedAudioV1? {
        guard fileManager.fileExists(atPath: sidecarURL.path),
              fileManager.fileExists(atPath: derivativeURL.path),
              let result = try? decodeSidecar(sidecarURL),
              result.schemaVersion == PreparedAudioV1.schemaVersion,
              result.sourceAudioID == sourceAudioID,
              result.source.sourceDigest == sourceDigest,
              result.recipe == recipe,
              result.regenerationKey == regenerationKey,
              try validateDerivative(result, at: derivativeURL) else {
            return nil
        }
        return result
    }

    private func validateDerivative(_ result: PreparedAudioV1, at url: URL) throws -> Bool {
        let byteCount = try fileSize(url)
        let digest = try Self.digest(url: url)
        return result.output.relativeFileName == url.lastPathComponent
            && result.output.byteCount == byteCount
            && result.output.digest == digest
    }

    private func invalidateGenerated(
        derivativeURL: URL,
        sidecarURL: URL,
        sourceURL: URL,
        sourceAudioID: ArtifactStoreID,
        ownershipURL: URL,
        expectedSourceDigest: String,
        expectedRegenerationKey: String
    ) throws {
        try rejectSourceCollision(
            sourceURL: sourceURL,
            generatedURLs: [derivativeURL, sidecarURL, ownershipURL]
        )
        let sidecarExists = fileManager.fileExists(atPath: sidecarURL.path)
        let derivativeExists = fileManager.fileExists(atPath: derivativeURL.path)
        let ownershipExists = fileManager.fileExists(atPath: ownershipURL.path)
        let sidecarOwnsFiles: Bool
        if let result = try? decodeSidecar(sidecarURL) {
            let coherentRegenerationKey = try? Self.regenerationKey(
                sourceDigest: result.source.sourceDigest,
                recipe: result.recipe
            )
            sidecarOwnsFiles = result.schemaVersion == PreparedAudioV1.schemaVersion
                && result.sourceAudioID == sourceAudioID
                && result.source.sourceDigestAlgorithm == "sha256"
                && Self.isSHA256(result.source.sourceDigest)
                && result.source.sourceByteCount >= 0
                && coherentRegenerationKey == result.regenerationKey
                && result.output.relativeFileName == derivativeURL.lastPathComponent
                && result.output.digestAlgorithm == "sha256"
                && Self.isSHA256(result.output.digest)
                && result.output.byteCount >= 0
                && result.output.sampleRateHz == result.recipe.outputSampleRateHz
                && result.output.channelCount == result.recipe.outputChannelCount
                && result.output.sampleFormat == result.recipe.outputSampleFormat
                && result.recipe.outputSampleRateHz > 0
                && result.recipe.outputChannelCount > 0
                && result.recipe.analysisWindowFrames > 0
        } else {
            sidecarOwnsFiles = false
        }
        let markerOwnsFiles: Bool
        if let marker = try? Self.decoder.decode(
            GeneratedAudioOwnershipV1.self,
            from: Data(contentsOf: ownershipURL)
        ) {
            let publishedEvidenceMatches: Bool
            switch (
                marker.publishedDerivativeDigest,
                marker.publishedDerivativeByteCount
            ) {
            case (nil, nil):
                publishedEvidenceMatches = true
            case let (.some(digest), .some(byteCount)):
                publishedEvidenceMatches = derivativeExists
                    && Self.isSHA256(digest)
                    && byteCount >= 0
                    && (try? fileSize(derivativeURL)) == byteCount
                    && (try? Self.digest(url: derivativeURL)) == digest
            case (.some, nil), (nil, .some):
                publishedEvidenceMatches = false
            }
            markerOwnsFiles = marker.schemaVersion == 1
                && marker.sourceAudioID == sourceAudioID
                && marker.sourceDigest == expectedSourceDigest
                && marker.recipeVersion == recipe.recipeVersion
                && marker.regenerationKey == expectedRegenerationKey
                && marker.derivativeFileName == derivativeURL.lastPathComponent
                && marker.sidecarFileName == sidecarURL.lastPathComponent
                && publishedEvidenceMatches
        } else {
            markerOwnsFiles = false
        }
        if sidecarExists || derivativeExists || ownershipExists {
            guard sidecarOwnsFiles || markerOwnsFiles else {
                throw AudioPreparationError.generatedOwnershipNotEstablished
            }
        }
        if derivativeExists && !sidecarOwnsFiles && !markerOwnsFiles {
            throw AudioPreparationError.generatedOwnershipNotEstablished
        }
        if sidecarExists {
            try removeGeneratedFile(sidecarURL, protecting: sourceURL)
        }
        if derivativeExists {
            try removeGeneratedFile(derivativeURL, protecting: sourceURL)
        }
        if ownershipExists {
            try removeGeneratedFile(ownershipURL, protecting: sourceURL)
        }
    }

    private func rejectSourceCollision(
        sourceURL: URL,
        generatedURLs: [URL]
    ) throws {
        let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        guard !generatedURLs.contains(where: {
            $0.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource.path
        }) else {
            throw AudioPreparationError.sourceCollidesWithGeneratedPath
        }
    }

    private func removeGeneratedFile(_ url: URL, protecting sourceURL: URL) throws {
        try rejectSourceCollision(sourceURL: sourceURL, generatedURLs: [url])
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func containedURL(_ fileName: String) throws -> URL {
        guard !fileName.contains("/"), fileName != ".", fileName != ".." else {
            throw AudioPreparationError.pathEscapedDerivativeRoot
        }
        let candidate = derivativeRoot.appendingPathComponent(fileName)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.deletingLastPathComponent().path == derivativeRoot.path else {
            throw AudioPreparationError.pathEscapedDerivativeRoot
        }
        return candidate
    }

    private func decodeSidecar(_ url: URL) throws -> PreparedAudioV1 {
        try Self.decoder.decode(PreparedAudioV1.self, from: Data(contentsOf: url))
    }

    private func replace(_ temporary: URL, at destination: URL) throws {
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try synchronizeDirectory()
    }

    private func writeSynchronized(_ data: Data, to url: URL) throws {
        guard fileManager.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw AudioPreparationError.conversionFailed("Could not write sidecar")
        }
        try synchronizeFile(url)
    }

    private func synchronizeFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func synchronizeDirectory() throws {
        let descriptor = Darwin.open(derivativeRoot.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    nonisolated private static func regenerationKey(
        sourceDigest: String,
        recipe: AudioPreparationRecipeV1
    ) throws -> String {
        let recipeData = try encoder.encode(recipe)
        var hash = SHA256()
        hash.update(data: Data(sourceDigest.utf8))
        hash.update(data: recipeData)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    nonisolated private static func digest(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    nonisolated private static let decoder = JSONDecoder()
}

nonisolated private struct AudioQualityAnalyzer {
    let recipe: AudioPreparationRecipeV1
    private(set) var frameCount: Int64 = 0
    private var sumSquares = 0.0
    private var peak = 0.0
    private var clipped: Int64 = 0
    private var windowSquares = 0.0
    private var windowFrames = 0
    private var analyzedWindowFrames: Int64 = 0
    private var silentWindowFrames: Int64 = 0
    private var silenceRanges: [(Int64, Int64)] = []
    private var speechRanges: [(Int64, Int64)] = []

    init(recipe: AudioPreparationRecipeV1) {
        self.recipe = recipe
    }

    mutating func consume(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        for index in 0..<Int(buffer.frameLength) {
            let value = Double(samples[index])
            let square = value * value
            sumSquares += square
            windowSquares += square
            peak = max(peak, abs(value))
            if abs(value) >= recipe.clippingAmplitudeThreshold { clipped += 1 }
            frameCount += 1
            windowFrames += 1
            if windowFrames == recipe.analysisWindowFrames {
                closeWindow()
            }
        }
    }

    mutating func finish() -> AudioQualityMeasurementsV1 {
        if windowFrames > 0 { closeWindow() }
        let rms = frameCount > 0 ? sqrt(sumSquares / Double(frameCount)) : 0
        return AudioQualityMeasurementsV1(
            algorithmVersion: recipe.qualityVersion,
            amplitudeUnit: "linear_full_scale",
            levelUnit: "dBFS",
            regionTimeUnit: "microseconds_from_original_audio_start",
            peakAmplitude: peak,
            rmsAmplitude: rms,
            rmsDBFS: rms > 0 ? 20 * log10(rms) : nil,
            clippingThreshold: recipe.clippingAmplitudeThreshold,
            clippedSampleCount: clipped,
            clippingRatio: frameCount > 0 ? Double(clipped) / Double(frameCount) : 0,
            silenceRMSDBFSThreshold: recipe.silenceRMSDBFSThreshold,
            silenceRatio: analyzedWindowFrames > 0
                ? Double(silentWindowFrames) / Double(analyzedWindowFrames)
                : 0,
            speechRMSDBFSThreshold: recipe.speechRMSDBFSThreshold,
            silenceRegions: regions(silenceRanges, kind: .silence),
            conservativeSpeechRegions: regions(speechRanges, kind: .conservativeSpeech)
        )
    }

    private mutating func closeWindow() {
        let end = frameCount
        let start = end - Int64(windowFrames)
        let rms = sqrt(windowSquares / Double(windowFrames))
        let db = rms > 0 ? 20 * log10(rms) : -.infinity
        analyzedWindowFrames += Int64(windowFrames)
        if db <= recipe.silenceRMSDBFSThreshold {
            silentWindowFrames += Int64(windowFrames)
            append((start, end), to: &silenceRanges)
        }
        if db >= recipe.speechRMSDBFSThreshold {
            append((start, end), to: &speechRanges)
        }
        windowSquares = 0
        windowFrames = 0
    }

    private func regions(
        _ ranges: [(Int64, Int64)],
        kind: AudioQualityRegionKindV1
    ) -> [AudioQualityRegionV1] {
        ranges.map {
            AudioQualityRegionV1(
                kind: kind,
                startUs: Int64((Double($0.0) / recipe.outputSampleRateHz) * 1_000_000),
                endUs: Int64((Double($0.1) / recipe.outputSampleRateHz) * 1_000_000)
            )
        }
    }

    private func append(
        _ range: (Int64, Int64),
        to ranges: inout [(Int64, Int64)]
    ) {
        if let last = ranges.last, last.1 == range.0 {
            ranges[ranges.count - 1] = (last.0, range.1)
        } else {
            ranges.append(range)
        }
    }
}

nonisolated private final class AudioConversionInputState: @unchecked Sendable {
    var inputBuffer: AVAudioPCMBuffer?
    var didSupplyInput = false
    var reachedEndOfSource = false
}
