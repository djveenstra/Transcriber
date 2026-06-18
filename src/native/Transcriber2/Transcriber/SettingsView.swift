import SwiftUI

struct SettingsView: View {
    @AppStorage("keepAudioFiles") private var keepAudioFiles = true
    @AppStorage("whisperModel") private var whisperModel = WhisperModelChoice.defaultID
    @StateObject private var finalDownloader = FinalModelDownloader.shared
    @State private var modelStatusRefreshID = UUID()
#if os(iOS)
    @AppStorage("finalTranscriptionModel") private var finalModel = FinalTranscriptionModelChoice.defaultID
#endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Processing") {
#if os(iOS)
                    Picker("Final transcription model", selection: $finalModel) {
                        Section("Parakeet") {
                            ForEach(FinalTranscriptionModelChoice.parakeet) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        Section("Whisper") {
                            ForEach(FinalTranscriptionModelChoice.whisper) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                    Text(selectedFinalModel.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    LabeledContent("Live transcription", value: "Parakeet EOU 120M · 320 ms")
                    LabeledContent("Final transcription", value: selectedFinalModel.name)
                    LabeledContent("Live speakers", value: "Added after recording")
                    LabeledContent("Final speakers", value: "Sortformer Balanced V2")
#else
                    Picker("Whisper model", selection: $whisperModel) {
                        ForEach(WhisperModelChoice.all) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    Text("Five curated choices, optimized for English transcription.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    modelDetail
                    LabeledContent("Live transcription", value: "WhisperKit")
                    LabeledContent("Final transcription", value: "WhisperKit")
                    LabeledContent("Live speakers", value: liveSpeakerDescription)
                    LabeledContent("Final speakers", value: "Sortformer Balanced V2")
#endif
                }
#if os(iOS)
                Section("Compare Models") {
                    NavigationLink {
                        ModelLabView()
                    } label: {
                        Label("Open Model Lab", systemImage: "speedometer")
                    }
                    Text("Run models one at a time on the same recording and compare their speed and transcripts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
#endif
                Section("Model Storage") {
                    ForEach(registryModels) { descriptor in
                        modelStorageRow(descriptor)
                    }
                }
                .id(modelStatusRefreshID)
                Section("Speakers") {
                    LabeledContent("Detection", value: "Automatic")
#if os(iOS)
                    Text("Sortformer identifies up to four speakers after recording so live transcription gets the phone's full attention.")
                        .font(.footnote).foregroundStyle(Theme.muted)
#else
                    Text("Sortformer automatically identifies up to four speakers. Live labels are provisional and replaced by a stronger final pass.")
                        .font(.footnote).foregroundStyle(Theme.muted)
#endif
                }
                Section("Storage") {
                    Toggle("Keep audio with transcripts", isOn: $keepAudioFiles)
                }
                Section("Privacy") {
                    Text("Audio and transcripts are processed on this device. Model files may be downloaded during first-time setup.")
                }
                Section("About") {
                    LabeledContent("App", value: "Transcriber 2.0 Beta")
                    LabeledContent("Minimum system", value: "iOS 26 / macOS 26")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                whisperModel = WhisperModelChoice.migrateToLightweightDefaultIfNeeded()
                refreshModelStatus()
#if os(iOS)
                finalModel = FinalTranscriptionModelChoice.selectedID()
#endif
            }
#if os(iOS)
            .onChange(of: finalModel) { _, value in
                FinalTranscriptionModelChoice.setSelectedID(value)
            }
#endif
        }
    }

    private var selectedModel: WhisperModelChoice {
        WhisperModelChoice.choice(for: whisperModel)
    }

#if os(iOS)
    private var selectedFinalModel: FinalTranscriptionModelChoice {
        FinalTranscriptionModelChoice.choice(for: finalModel)
    }
#endif

    private var liveSpeakerDescription: String {
#if os(iOS)
        "Sortformer Fast V2"
#else
        "Added after recording"
#endif
    }

    private var modelDetail: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedModel.detail)
            if !selectedModel.recommendedForLive {
                Text("This heavier model may make live text lag or run out of memory on iPhone.")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
    }

    private var registryModels: [ModelDescriptor] {
#if os(iOS)
        ModelRegistry.models
#else
        FinalTranscriptionModelChoice.whisper.map(ModelRegistry.descriptor(for:))
#endif
    }

    @ViewBuilder private func modelStorageRow(_ descriptor: ModelDescriptor) -> some View {
        let file = ModelRegistry.fileSnapshot(for: descriptor)
        let status = ModelRegistry.status(
            for: descriptor,
            download: downloadSnapshot,
            file: file,
            verification: file.isPresent ? .ready : .notChecked
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.displayName)
                        .font(.headline)
                    Text("\(providerLabel(descriptor.provider)) · \(descriptor.speedHint) · \(descriptor.accuracyHint)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if isSelected(descriptor) {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }

            Label(status.label, systemImage: statusIcon(for: status))
                .font(.subheadline)
                .foregroundStyle(statusColor(for: status))
            if case let .downloading(progress, message) = status {
                ProgressView(value: progress)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            LabeledContent("Storage", value: ModelRegistry.formattedSize(file.sizeBytes))
                .font(.caption)

            actionControl(for: descriptor, status: status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func actionControl(for descriptor: ModelDescriptor, status: ModelStatus) -> some View {
        switch status {
        case .notDownloaded:
            Button("Download") {
                Task { await finalDownloader.download(descriptor.choice) }
            }
        case .missingOrCorrupt, .failed:
            Button("Repair") {
                Task { await finalDownloader.repair(descriptor.choice) }
            }
        case .downloaded, .ready:
            Button("Redownload") {
                Task { await finalDownloader.redownload(descriptor.choice) }
            }
        case .downloading, .verifying:
            EmptyView()
        }
    }

    private var downloadSnapshot: ModelDownloadSnapshot {
        switch finalDownloader.state {
        case .idle:
            return .idle
        case let .downloading(id, progress, status):
            return .downloading(modelID: id, progress: progress, message: status)
        case let .ready(id):
            return .ready(modelID: id)
        case let .failed(id, message):
            return .failed(modelID: id, message: message)
        }
    }

    private func refreshModelStatus() {
        finalDownloader.refreshFileStatus()
        finalDownloader.scheduleDefaultPreloadIfNeeded()
        modelStatusRefreshID = UUID()
    }

    private func providerLabel(_ provider: FinalTranscriptionProvider) -> String {
        switch provider {
        case .whisper: "Whisper"
        case .parakeet: "Parakeet"
        }
    }

    private func isSelected(_ descriptor: ModelDescriptor) -> Bool {
#if os(iOS)
        descriptor.id == finalModel
#else
        descriptor.id == whisperModel
#endif
    }

    private func statusIcon(for status: ModelStatus) -> String {
        switch status {
        case .notDownloaded: "arrow.down.circle"
        case .downloading: "arrow.down.circle.fill"
        case .downloaded: "tray.and.arrow.down.fill"
        case .verifying: "checkmark.shield"
        case .ready: "checkmark.circle.fill"
        case .missingOrCorrupt: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func statusColor(for status: ModelStatus) -> Color {
        switch status {
        case .ready:
            Theme.accent
        case .missingOrCorrupt, .failed:
            .red
        case .downloading, .verifying:
            .blue
        case .notDownloaded, .downloaded:
            Theme.muted
        }
    }
}
