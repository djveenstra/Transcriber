import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.daniel.transcriber2.beta"
    private let statusLabel = UILabel()
    private var hasCompleted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Saving to Transcriber..."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task { await importSharedAudio() }
    }

    private func importSharedAudio() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(message: "No audio recording was provided.", error: true)
            return
        }

        let providers = extensionItems
            .flatMap { $0.attachments ?? [] }
            .filter { provider in
                provider.registeredTypeIdentifiers.contains { identifier in
                    UTType(identifier)?.conforms(to: .audio) == true
                }
            }

        guard !providers.isEmpty else {
            finish(message: "Transcriber could not find an audio recording.", error: true)
            return
        }

        do {
            var savedCount = 0
            for provider in providers {
                try await save(provider)
                savedCount += 1
            }
            let noun = savedCount == 1 ? "recording" : "recordings"
            finish(message: "Saved \(savedCount) \(noun) to Transcriber.", error: false)
        } catch {
            let reason = error.localizedDescription
            finish(message: "Could not save this recording.\n\(reason)", error: true)
        }
    }

    private func save(_ provider: NSItemProvider) async throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw ImportError.sharedContainerUnavailable
        }
        let inbox = container.appendingPathComponent("SharedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .audio) == true
        }) else {
            throw ImportError.unsupportedAudio
        }

        let providedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providedURL = providedName.map { URL(fileURLWithPath: $0) }
        let title = providedURL?.deletingPathExtension().lastPathComponent.nonEmpty ?? "Voice Memo"
        let fileExtension = providedURL?.pathExtension.nonEmpty
            ?? UTType(typeIdentifier)?.preferredFilenameExtension
            ?? "m4a"
        let destination = uniqueDestination(in: inbox, title: title, extension: fileExtension)

        do {
            try await copyFileRepresentation(
                from: provider,
                typeIdentifier: typeIdentifier,
                to: destination
            )
        } catch {
            try await writeDataRepresentation(
                from: provider,
                typeIdentifier: typeIdentifier,
                to: destination
            )
        }
    }

    private func copyFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        to destination: URL
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                do {
                    if let error { throw error }
                    guard let sourceURL else { throw CocoaError(.fileNoSuchFile) }

                    // This URL is temporary and may disappear as soon as this callback returns.
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func writeDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        to destination: URL
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                do {
                    if let error { throw error }
                    guard let data else { throw CocoaError(.fileReadUnknown) }
                    try data.write(to: destination, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Builds a destination filename that is unique by construction (UUID-prefixed),
    /// while keeping the original title readable for display in the shared inbox.
    /// See `SharedAudioItem.name` for how the title is recovered.
    private func uniqueDestination(in directory: URL, title: String, extension fileExtension: String) -> URL {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
        let filename = "\(UUID().uuidString)__\(sanitizedTitle)"
        return directory.appendingPathComponent(filename).appendingPathExtension(fileExtension)
    }

    private func finish(message: String, error: Bool) {
        guard !hasCompleted else { return }
        hasCompleted = true
        statusLabel.text = message
        statusLabel.textColor = error ? .systemRed : .label
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 3.0 : 1.2)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

private enum ImportError: LocalizedError {
    case sharedContainerUnavailable
    case unsupportedAudio

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            "Transcriber could not open its shared storage."
        case .unsupportedAudio:
            "Voice Memos did not provide a supported audio file."
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
