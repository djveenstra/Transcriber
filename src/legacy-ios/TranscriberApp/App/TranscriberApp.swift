import SwiftUI
import SwiftData

@main
struct TranscriberApp: App {
    @StateObject private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            if modelManager.isReady {
                ContentView()
            } else {
                ModelDownloadView()
            }
        }
        .modelContainer(for: Recording.self)
        .environmentObject(modelManager)
    }
}
