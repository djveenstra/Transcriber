import Foundation
import Combine

/// Manages ML model files. Models are stored in Application Support.
/// On first launch, downloads models from public HuggingFace URLs.
/// Subsequent launches use cached files.
///
/// Total download: ~350MB (one-time, then fully offline forever).
class ModelManager: ObservableObject {
    @Published var isReady: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = "Checking models..."
    @Published var errorMessage: String?

    static let shared = ModelManager()

    private let modelsDir: URL

    // Model file names
    private static let whisperModelName = "ggml-base.bin"
    private static let sileroVADName = "silero-vad.mlmodelc"
    private static let segmentationName = "segmentation-3.0.mlmodelc"
    private static let embeddingName = "wespeaker-resnet34.mlmodelc"

    // Public download URLs (no auth required)
    private static let modelSources: [(name: String, url: String, sizeMB: Int)] = [
        (whisperModelName,
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
         142),
        // CoreML models from FluidInference - these are zip archives containing .mlmodelc dirs
        (sileroVADName,
         "https://huggingface.co/FluidInference/silero-vad-coreml/resolve/main/silero-vad.mlmodelc.zip",
         2),
        (segmentationName,
         "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main/segmentation-3.0.mlmodelc.zip",
         20),
        (embeddingName,
         "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main/wespeaker-resnet34.mlmodelc.zip",
         50),
    ]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDir = appSupport.appendingPathComponent("TranscriberApp/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        isReady = checkModels()
    }

    // MARK: - Public model paths

    var whisperModelPath: URL? {
        let path = modelsDir.appendingPathComponent(Self.whisperModelName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    var sileroVADPath: URL? {
        let path = modelsDir.appendingPathComponent(Self.sileroVADName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    var segmentationPath: URL? {
        let path = modelsDir.appendingPathComponent(Self.segmentationName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    var embeddingPath: URL? {
        let path = modelsDir.appendingPathComponent(Self.embeddingName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // MARK: - Check & Download

    /// Returns true if all required model files are present.
    func checkModels() -> Bool {
        return whisperModelPath != nil &&
               sileroVADPath != nil &&
               segmentationPath != nil &&
               embeddingPath != nil
    }

    /// Download all missing models. Call from a Task {} block.
    func downloadMissingModels() async {
        await MainActor.run {
            errorMessage = nil
            downloadProgress = 0.0
        }

        let missingModels = Self.modelSources.filter { source in
            let path = modelsDir.appendingPathComponent(source.name)
            return !FileManager.default.fileExists(atPath: path.path)
        }

        if missingModels.isEmpty {
            await MainActor.run {
                isReady = true
                downloadProgress = 1.0
                statusMessage = "Ready"
            }
            return
        }

        let totalSize = missingModels.reduce(0) { $0 + $1.sizeMB }
        var downloadedSize = 0

        for source in missingModels {
            await MainActor.run {
                statusMessage = "Downloading \(source.name) (\(source.sizeMB) MB)..."
            }

            do {
                guard let url = URL(string: source.url) else {
                    throw ModelError.invalidURL(source.url)
                }

                let destPath = modelsDir.appendingPathComponent(source.name)

                // Download file
                let (tempURL, _) = try await URLSession.shared.download(from: url)

                // If it's a zip file, unzip it
                if source.url.hasSuffix(".zip") {
                    try unzipModel(from: tempURL, to: modelsDir, expectedName: source.name)
                    try? FileManager.default.removeItem(at: tempURL)
                } else {
                    // Move directly
                    if FileManager.default.fileExists(atPath: destPath.path) {
                        try FileManager.default.removeItem(at: destPath)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destPath)
                }

                downloadedSize += source.sizeMB
                await MainActor.run {
                    downloadProgress = Double(downloadedSize) / Double(totalSize)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download \(source.name): \(error.localizedDescription)"
                    statusMessage = "Download failed"
                }
                return
            }
        }

        await MainActor.run {
            isReady = checkModels()
            downloadProgress = 1.0
            statusMessage = isReady ? "Ready" : "Some models failed to download"
        }
    }

    /// Unzip a downloaded .mlmodelc.zip archive.
    private func unzipModel(from zipURL: URL, to destDir: URL, expectedName: String) throws {
        // Use Process or a lightweight unzip approach.
        // On iOS, we can use FileManager or a built-in approach.
        // For simplicity, use the `unzip` command isn't available on iOS,
        // so we use Foundation's built-in ZIP support via a simple implementation.

        // Create a temp directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use Archive (if available) or manual extraction
        // For iOS, we'll use a simple approach: rename .zip and extract
        let zipPath = tempDir.appendingPathComponent("model.zip")
        try FileManager.default.copyItem(at: zipURL, to: zipPath)

        // Extract using built-in unzip (available via NSFileCoordinator on iOS)
        // Alternative: include a lightweight zip library like ZIPFoundation
        // For now, assume the .mlmodelc is delivered as a directory in the zip
        let destPath = destDir.appendingPathComponent(expectedName)
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }

        // Simple extraction using FileManager's built-in support
        // NOTE: In production, use ZIPFoundation SPM package for reliable unzipping
        try extractZIP(at: zipPath, to: tempDir)

        // Find the .mlmodelc directory in the extracted contents
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        if let modelDir = contents.first(where: { $0.lastPathComponent == expectedName }) {
            try FileManager.default.moveItem(at: modelDir, to: destPath)
        } else if let modelDir = contents.first(where: { $0.pathExtension == "mlmodelc" }) {
            try FileManager.default.moveItem(at: modelDir, to: destPath)
        }
    }

    /// Basic ZIP extraction. In production, replace with ZIPFoundation.
    private func extractZIP(at zipURL: URL, to destURL: URL) throws {
        // iOS doesn't have a built-in unzip command.
        // This is a placeholder — in the real implementation, add ZIPFoundation as a dependency:
        // .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
        // Then: try FileManager.default.unzipItem(at: zipURL, to: destURL)
        fatalError("Add ZIPFoundation package and replace this with: try FileManager.default.unzipItem(at: zipURL, to: destURL)")
    }

    enum ModelError: LocalizedError {
        case invalidURL(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid model URL: \(url)"
            case .extractionFailed(let name): return "Failed to extract model: \(name)"
            }
        }
    }
}
