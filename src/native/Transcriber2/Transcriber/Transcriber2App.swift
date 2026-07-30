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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var audioAvailability = RecordingAudioAvailabilityStore.shared
    @State private var recoveredProcessingJobs = false
    @State private var recoveryStorageError: String?
    @State private var recoveryAttemptID = UUID()

    var body: some View {
        RootView()
            .task(id: "\(reconciliationSignature):\(recoveryAttemptID)") {
                audioAvailability.reconcile(recordings: recordings)
                guard !recoveredProcessingJobs else { return }
                let store = ProcessingJobStore(applicationSupportRoot: AppStoragePaths.rootDirectory)
                do {
                    let report = try await store.reconcileAfterRelaunch()
                    var jobs: [ProcessingJobRecordV1] = []
                    for locator in report.projectionJobs {
                        jobs.append(try await store.load(
                            locator.jobID,
                            recordingID: locator.recordingID
                        ))
                    }
                    try ProcessingJobRecoveryProjection.apply(jobs, to: recordings) {
                        try modelContext.save()
                    }
                    recoveryStorageError = nil
                    recoveredProcessingJobs = true
                } catch {
                    recoveryStorageError =
                        "Recovered processing status could not be saved. Your audio and transcript remain unchanged. Retry recovery before starting new processing."
                }
            }
            .alert(
                "Storage Issue",
                isPresented: Binding(
                    get: { recoveryStorageError != nil },
                    set: { if !$0 { recoveryStorageError = nil } }
                )
            ) {
                Button("Retry") { recoveryAttemptID = UUID() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(recoveryStorageError ?? "")
            }
    }

    private var reconciliationSignature: String {
        recordings
            .map { "\($0.audioFileName):\($0.createdAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }
}
