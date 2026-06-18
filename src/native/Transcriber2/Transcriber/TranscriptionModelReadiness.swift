import FluidAudio
import Foundation

enum TranscriptionModelReadiness {
    static let whisperDownloadedModelsKey = "downloadedWhisperModelIDs"

    private static let whisperRequiredModelNames = [
        "MelSpectrogram",
        "AudioEncoder",
        "TextDecoder",
    ]

    static func isPresent(_ model: FinalTranscriptionModelChoice) -> Bool {
        switch model.provider {
        case .whisper:
            return isWhisperModelPresent(model.id, reconcileHint: true)
        case .parakeet:
            guard let version = model.parakeetVersion else { return false }
            return isParakeetModelPresent(version)
        }
    }

    static func cacheDirectory(for model: FinalTranscriptionModelChoice) -> URL? {
        switch model.provider {
        case .whisper:
            return whisperCacheDirectory(for: model.id)
        case .parakeet:
            guard let version = model.parakeetVersion else { return nil }
            return AsrModels.defaultCacheDirectory(for: version)
        }
    }

    static func hasCacheFootprint(
        for model: FinalTranscriptionModelChoice,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let directory = cacheDirectory(for: model) else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func cacheSizeBytes(
        for model: FinalTranscriptionModelChoice,
        fileManager: FileManager = .default
    ) -> Int64? {
        guard let directory = cacheDirectory(for: model) else { return nil }
        return directorySizeBytes(at: directory, fileManager: fileManager)
    }

    static func removeCache(
        for model: FinalTranscriptionModelChoice,
        fileManager: FileManager = .default
    ) throws {
        switch model.provider {
        case .whisper:
            try removeWhisperCache(modelID: model.id, fileManager: fileManager)
        case .parakeet:
            guard let directory = cacheDirectory(for: model) else { return }
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    static func isWhisperModelPresent(
        _ modelID: String,
        cacheRoot: URL = defaultWhisperCacheRoot(),
        fileManager: FileManager = .default,
        reconcileHint: Bool = false,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let modelDirectory = cacheRoot.appendingPathComponent(modelID, isDirectory: true)
        let present = whisperRequiredModelNames.allSatisfy {
            whisperModelFileExists(named: $0, in: modelDirectory, fileManager: fileManager)
        }

        if reconcileHint {
            reconcileWhisperHint(modelID: modelID, isPresent: present, defaults: defaults)
        }

        return present
    }

    static func isParakeetModelPresent(_ version: AsrModelVersion) -> Bool {
        let directory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: directory, version: version)
    }

    static func reconciledWhisperHintIDs(
        modelIDs: some Sequence<String>,
        cacheRoot: URL = defaultWhisperCacheRoot(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var reconciled = Set(defaults.stringArray(forKey: whisperDownloadedModelsKey) ?? [])
        for modelID in modelIDs {
            let present = isWhisperModelPresent(
                modelID,
                cacheRoot: cacheRoot,
                fileManager: fileManager,
                reconcileHint: false,
                defaults: defaults
            )
            if present {
                reconciled.insert(modelID)
            } else {
                reconciled.remove(modelID)
            }
        }
        defaults.set(Array(reconciled).sorted(), forKey: whisperDownloadedModelsKey)
        return reconciled
    }

    static func defaultWhisperCacheRoot(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    static func whisperCacheDirectory(
        for modelID: String,
        cacheRoot: URL = defaultWhisperCacheRoot()
    ) -> URL {
        cacheRoot.appendingPathComponent(modelID, isDirectory: true)
    }

    static func removeWhisperCache(
        modelID: String,
        cacheRoot: URL = defaultWhisperCacheRoot(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) throws {
        let directory = whisperCacheDirectory(for: modelID, cacheRoot: cacheRoot)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        reconcileWhisperHint(modelID: modelID, isPresent: false, defaults: defaults)
    }

    private static func whisperModelFileExists(
        named modelName: String,
        in modelDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        let compiledModel = modelDirectory.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
        if fileManager.fileExists(atPath: compiledModel.path) {
            return true
        }

        let packageModel = modelDirectory
            .appendingPathComponent("\(modelName).mlpackage", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("com.apple.CoreML", isDirectory: true)
            .appendingPathComponent("model.mlmodel", isDirectory: false)
        return fileManager.fileExists(atPath: packageModel.path)
    }

    private static func reconcileWhisperHint(
        modelID: String,
        isPresent: Bool,
        defaults: UserDefaults
    ) {
        var hintedIDs = Set(defaults.stringArray(forKey: whisperDownloadedModelsKey) ?? [])
        if isPresent {
            hintedIDs.insert(modelID)
        } else {
            hintedIDs.remove(modelID)
        }
        defaults.set(Array(hintedIDs).sorted(), forKey: whisperDownloadedModelsKey)
    }

    private static func directorySizeBytes(
        at url: URL,
        fileManager: FileManager
    ) -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
