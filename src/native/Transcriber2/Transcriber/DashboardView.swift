import SwiftData
import SwiftUI

nonisolated struct DashboardStatusSummary: Equatable, Sendable {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let needsAttention: Bool
}

nonisolated struct DashboardRecordingAttentionItem: Equatable, Sendable {
    let audioFileName: String
    let title: String
    let createdAt: Date
    let status: RecordingStatus
    let durationText: String
    let modelName: String
    let speakerLabelText: String
}

nonisolated enum DashboardRecordingAttention {
    static func needsAttention(status: RecordingStatus) -> Bool {
        status != .complete
    }

    static func recentNeedingAttention(
        from items: [DashboardRecordingAttentionItem],
        limit: Int = 5
    ) -> [DashboardRecordingAttentionItem] {
        items
            .filter { needsAttention(status: $0.status) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
}

enum DashboardModelStatus {
    static func summary(modelName: String, status: ModelStatus) -> DashboardStatusSummary {
        DashboardStatusSummary(
            title: "Transcription model",
            value: "\(modelName) - \(status.label)",
            detail: status.detail,
            systemImage: "cpu",
            needsAttention: warning(for: status, modelName: modelName) != nil
        )
    }

    static func warning(for status: ModelStatus, modelName: String) -> String? {
        switch status {
        case .ready:
            nil
        case .notDownloaded:
            "\(modelName) is not downloaded yet. Recording still works, but final transcription may need a download before it can finish offline."
        case let .downloading(_, message):
            if message.localizedCaseInsensitiveContains("repair") {
                "\(modelName) is being repaired. You can record now; final transcription will wait until the repair finishes."
            } else {
                "\(modelName) is downloading. You can record now; final transcription will wait until the download finishes."
            }
        case .downloaded:
            "\(modelName) is downloaded and waiting for a readiness check."
        case .verifying:
            "\(modelName) is being checked before use."
        case .missingOrCorrupt:
            "\(modelName) is missing or incomplete. Open Settings to repair or redownload it."
        case let .failed(message):
            "\(modelName) could not finish setup. \(message)"
        }
    }
}

enum DashboardMicrophoneStatus {
    static func summary(
        selectedID: String,
        visibleSelectedID: String,
        choices: [MicrophoneChoice]
    ) -> DashboardStatusSummary {
        let visibleChoice = choices.first { $0.id == visibleSelectedID } ?? .automatic
        let selectedChoice = choices.first { $0.id == selectedID }
        let savedInputUnavailable = selectedID != MicrophoneSelectionStore.automaticID
            && visibleSelectedID == MicrophoneSelectionStore.automaticID
            && selectedChoice == nil

        return DashboardStatusSummary(
            title: "Microphone",
            value: visibleChoice.name,
            detail: savedInputUnavailable
                ? "Saved input unavailable. Recording and Test Mic will use Automatic until it reconnects."
                : visibleChoice.detail,
            systemImage: "mic.fill",
            needsAttention: savedInputUnavailable
        )
    }
}

nonisolated enum DashboardSpeakerLabelStatus {
    static func summary(hasActiveSpeakerLabeling: Bool) -> DashboardStatusSummary {
        let activePresentation = SpeakerLabelStatusPresentation.identifying
        return DashboardStatusSummary(
            title: "Speaker labeling",
            value: hasActiveSpeakerLabeling ? activePresentation.title : "Sortformer Balanced V2",
            detail: hasActiveSpeakerLabeling
                ? activePresentation.detail
                : "Loads when speaker labeling starts; separate model readiness is not available yet.",
            systemImage: "person.3.fill",
            needsAttention: false
        )
    }
}

struct DashboardView: View {
    let onRecord: () -> Void
    let onImport: () -> Void
    let onModelLab: (() -> Void)?

    @AppStorage(MicrophoneSelectionStore.selectionKey) private var selectedMicrophoneID = MicrophoneSelectionStore.automaticID
#if os(iOS)
    @AppStorage("finalTranscriptionModel") private var finalModelID = FinalTranscriptionModelChoice.defaultID
#else
    @AppStorage("whisperModel") private var finalModelID = WhisperModelChoice.defaultID
#endif
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @ObservedObject private var microphoneService = MicrophoneService.shared
    @StateObject private var finalDownloader = FinalModelDownloader.shared
    @StateObject private var statusActivityStore = RecordingStatusActivityStore.shared

    private var selectedModel: FinalTranscriptionModelChoice {
        FinalTranscriptionModelChoice.choice(for: finalModelID)
    }

    private var selectedModelStatus: ModelStatus {
        let descriptor = ModelRegistry.descriptor(for: selectedModel)
        let file = ModelRegistry.fileSnapshot(for: descriptor)
        return ModelRegistry.status(
            for: descriptor,
            download: downloadSnapshot,
            file: file,
            verification: file.isPresent ? .ready : .notChecked
        )
    }

    private var microphoneSummary: DashboardStatusSummary {
        DashboardMicrophoneStatus.summary(
            selectedID: selectedMicrophoneID,
            visibleSelectedID: microphoneService.visibleSelectedID,
            choices: microphoneService.choices
        )
    }

    private var modelSummary: DashboardStatusSummary {
        DashboardModelStatus.summary(modelName: selectedModel.name, status: selectedModelStatus)
    }

    private var speakerSummary: DashboardStatusSummary {
        DashboardSpeakerLabelStatus.summary(
            hasActiveSpeakerLabeling: recordings.contains {
                statusActivityStore.activity(for: $0) == .speakerLabeling
            }
        )
    }

    private var modelWarning: String? {
        DashboardModelStatus.warning(for: selectedModelStatus, modelName: selectedModel.name)
    }

    private var attentionItems: [DashboardRecordingAttentionItem] {
        DashboardRecordingAttention.recentNeedingAttention(
            from: recordings.map { recording in
                attentionItem(for: recording)
            }
        )
    }

    private var attentionRecordings: [Recording] {
        let attentionFileNames = Set(attentionItems.map(\.audioFileName))
        return recordings.filter {
            attentionFileNames.contains($0.audioFileName)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    actionBar
                    if let modelWarning {
                        DashboardWarningView(message: modelWarning)
                    }
                    statusGrid
                    attentionSection
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready for the next recording")
                .font(.title3.bold())
            Text("Record, import, or check recent work from here.")
                .foregroundStyle(Theme.muted)

            HStack(spacing: 12) {
                Button(action: onRecord) {
                    Label("Record", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))

                Button(action: onImport) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())

#if os(iOS)
                if let onModelLab {
                    Button(action: onModelLab) {
                        Label("Open Model Lab", systemImage: "speedometer")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
#else
                Button {} label: {
                    Label("Open Model Lab", systemImage: "speedometer")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
#endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var statusGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
            DashboardStatusCard(summary: microphoneSummary)
            DashboardStatusCard(summary: modelSummary)
            DashboardStatusCard(summary: speakerSummary)
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent needing attention")
                    .font(.headline)
                Spacer()
                if !attentionItems.isEmpty {
                    Text("\(attentionItems.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if attentionItems.isEmpty {
                ContentUnavailableView(
                    "Nothing Needs Attention",
                    systemImage: "checkmark.circle",
                    description: Text("Recent recordings that need transcription or speaker-label retry will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            } else {
                VStack(spacing: 10) {
                    ForEach(attentionRecordings) { recording in
                        attentionRow(for: recording)
                    }
                }
            }
        }
    }

    private func attentionRow(for recording: Recording) -> some View {
        let item = attentionItem(for: recording)
        return NavigationLink(value: recording) {
            HStack(alignment: .top, spacing: 12) {
                RecordingStatusBadge(status: item.status)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text("\(item.durationText) · \(item.modelName)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(item.speakerLabelText)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding()
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
    }

    private func attentionItem(for recording: Recording) -> DashboardRecordingAttentionItem {
        let status = recording.recordingStatus(activity: statusActivityStore.activity(for: recording))
        return DashboardRecordingAttentionItem(
            audioFileName: recording.audioFileName,
            title: recording.title,
            createdAt: recording.createdAt,
            status: status,
            durationText: RecordingLibraryMetadata.durationText(seconds: recording.durationSeconds),
            modelName: RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID),
            speakerLabelText: RecordingLibraryMetadata.speakerLabelText(for: recording, status: status)
        )
    }

    private var downloadSnapshot: ModelDownloadSnapshot {
        switch finalDownloader.state {
        case .idle:
            .idle
        case let .downloading(id, progress, status):
            .downloading(modelID: id, progress: progress, message: status)
        case let .ready(id):
            .ready(modelID: id)
        case let .failed(id, message):
            .failed(modelID: id, message: message)
        }
    }

}

private struct DashboardStatusCard: View {
    let summary: DashboardStatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(summary.title, systemImage: summary.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(summary.value)
                .font(.headline)
                .foregroundStyle(.white)
            Text(summary.detail)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(summary.needsAttention ? Color.yellow.opacity(0.75) : Theme.border)
        )
    }
}

private struct DashboardWarningView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.yellow)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.65)))
    }
}
