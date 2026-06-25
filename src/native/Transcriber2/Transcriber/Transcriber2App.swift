import SwiftData
import SwiftUI

@main
struct Transcriber2App: App {
    init() {
        _ = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()
        Task { @MainActor in
            FinalModelDownloader.shared.refreshFileStatus()
#if os(macOS)
            LaunchModelReadiness.shared.startIfNeeded()
#else
            FinalModelDownloader.shared.scheduleDefaultPreloadIfNeeded()
#endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ReconciledRootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Recording.self)
    }
}

private struct ReconciledRootView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var audioAvailability = RecordingAudioAvailabilityStore.shared

    var body: some View {
        RootView()
            .task(id: reconciliationSignature) {
                audioAvailability.reconcile(recordings: recordings)
            }
    }

    private var reconciliationSignature: String {
        recordings
            .map { "\($0.audioFileName):\($0.createdAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }
}
