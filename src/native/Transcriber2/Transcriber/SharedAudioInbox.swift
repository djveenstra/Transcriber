import AVFoundation
import Combine
import Foundation

nonisolated struct SharedAudioItem: Identifiable, Hashable, Sendable {
    let url: URL

    var id: URL { url }

    /// The share extension writes files as `<uuid>__<title>.<ext>` so that every
    /// import gets a unique destination filename without colliding with an existing
    /// recording's title. Recover the readable title for display here.
    var name: String {
        let base = url.deletingPathExtension().lastPathComponent
        guard let separatorRange = base.range(of: "__"),
              UUID(uuidString: String(base[base.startIndex..<separatorRange.lowerBound])) != nil
        else { return base }
        return String(base[separatorRange.upperBound...])
    }

    var receivedAt: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

@MainActor
final class SharedAudioInbox: ObservableObject {
    static let appGroupID = "group.com.daniel.transcriber2.beta"
    static let shared = SharedAudioInbox()

    @Published private(set) var items: [SharedAudioItem] = []
    private var refreshTask: Task<Void, Never>?

    private var directory: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else { return nil }
        let inbox = container.appendingPathComponent("SharedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    func refresh() {
        guard let directory else {
            refreshTask?.cancel()
            refreshTask = nil
            items = []
            return
        }

        refreshTask?.cancel()
        refreshTask = Task {
            let loadedItems = await Task.detached(priority: .userInitiated) {
                Self.loadItems(in: directory)
            }.value
            guard !Task.isCancelled else { return }
            items = loadedItems
            refreshTask = nil
        }
    }

    nonisolated static func loadItems(in directory: URL) -> [SharedAudioItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentTypeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.isAudioFile }
            .map(SharedAudioItem.init)
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    func delete(_ item: SharedAudioItem) {
        try? FileManager.default.removeItem(at: item.url)
        refresh()
    }
}

// Not private: exposed so unit tests can verify the audio-file filter.
extension URL {
    var isAudioFile: Bool {
        let audioExtensions = ["m4a", "mp3", "wav", "caf", "aiff", "aif", "aac", "flac"]
        return audioExtensions.contains(pathExtension.lowercased())
    }
}
