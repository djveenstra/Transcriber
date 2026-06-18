import SwiftData
import SwiftUI

@main
struct Transcriber2App: App {
    init() {
        _ = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()
        Task { @MainActor in
            FinalModelDownloader.shared.refreshFileStatus()
            FinalModelDownloader.shared.scheduleDefaultPreloadIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Recording.self)
    }
}
