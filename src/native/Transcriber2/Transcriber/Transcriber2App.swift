import SwiftData
import SwiftUI

@main
struct Transcriber2App: App {
    init() {
        _ = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Recording.self)
    }
}
