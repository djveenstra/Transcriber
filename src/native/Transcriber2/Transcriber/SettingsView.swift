import SwiftUI

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepAudioFiles") private var keepAudioFiles = true
    @AppStorage("whisperModel") private var whisperModel = WhisperModelChoice.defaultID
    @AppStorage(MicrophoneSelectionStore.selectionKey) private var selectedMicrophoneID = MicrophoneSelectionStore.automaticID
    @ObservedObject private var microphoneService = MicrophoneService.shared
    @StateObject private var finalDownloader = FinalModelDownloader.shared
    @StateObject private var microphoneTest = MicrophoneTestSession()
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
                Section("Microphone") {
                    Picker("Input", selection: microphonePickerSelection) {
                        ForEach(microphoneService.choices) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                    Text(selectedMicrophoneDetail)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    LabeledContent("Testing", value: selectedMicrophoneName)
                    InputLevelMeter(level: microphoneTest.level)
                        .frame(height: 12)
                        .accessibilityLabel("Input level")
                        .accessibilityValue("\(Int(microphoneTest.level * 100)) percent")
                    if let microphoneTestMessage {
                        Text(microphoneTestMessage)
                            .font(.footnote)
                            .foregroundStyle(microphoneTestMessageColor)
                    }
                    Button {
                        if microphoneTest.isTesting {
                            microphoneTest.stop()
                        } else {
                            Task { await microphoneTest.start() }
                        }
                    } label: {
                        Label(microphoneTestButtonTitle, systemImage: microphoneTestButtonIcon)
                    }
                    .disabled(microphoneTest.isBusy)
                    .accessibilityLabel(microphoneTestButtonTitle)
                    .accessibilityHint(microphoneTest.isTesting ? "Stops the microphone level test." : "Starts a microphone level test without saving audio.")
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
                microphoneService.refreshInputs()
                refreshModelStatus()
#if os(iOS)
                finalModel = FinalTranscriptionModelChoice.selectedID()
#endif
            }
            .onDisappear {
                microphoneTest.stop()
            }
            .onChange(of: selectedMicrophoneID) { _, _ in
                microphoneTest.stop()
            }
#if os(iOS)
            .onChange(of: finalModel) { _, value in
                FinalTranscriptionModelChoice.setSelectedID(value)
            }
#endif
            .onChange(of: scenePhase) { _, value in
                guard value == .active else { return }
                microphoneService.refreshInputs()
            }
        }
    }

    private var selectedMicrophoneDetail: String {
        guard selectedMicrophoneID != MicrophoneSelectionStore.automaticID else {
            return MicrophoneChoice.automatic.detail
        }
        guard microphoneService.visibleSelectedID != MicrophoneSelectionStore.automaticID else {
            return "This saved input is unavailable. Test Mic and recordings will use Automatic until it reconnects."
        }
        return microphoneService.choices.first { $0.id == selectedMicrophoneID }?.detail
            ?? "This saved input is not currently listed by the system."
    }

    private var selectedMicrophoneName: String {
        microphoneService.choices.first { $0.id == microphoneService.visibleSelectedID }?.name
            ?? MicrophoneChoice.automatic.name
    }

    private var microphonePickerSelection: Binding<String> {
        Binding(
            get: {
                microphoneService.visibleSelectedID
            },
            set: { newValue in
                selectedMicrophoneID = newValue
            }
        )
    }

    private var microphoneTestButtonTitle: String {
        switch microphoneTest.state {
        case .idle, .failed:
            "Start Test Mic"
        case .starting:
            "Starting Test Mic"
        case .testing:
            "Stop Test Mic"
        }
    }

    private var microphoneTestButtonIcon: String {
        switch microphoneTest.state {
        case .idle, .failed:
            "waveform"
        case .starting:
            "hourglass"
        case .testing:
            "stop.circle.fill"
        }
    }

    private var microphoneTestMessage: String? {
        switch microphoneTest.state {
        case .idle:
            nil
        case .starting:
            "Opening microphone input..."
        case .testing:
            microphoneTest.notice ?? "Microphone test is running."
        case let .failed(message):
            message
        }
    }

    private var microphoneTestMessageColor: Color {
        if case .failed = microphoneTest.state {
            return .red
        }
        return Theme.muted
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(modelStorageAccessibilityValue(descriptor: descriptor, status: status, file: file))
    }

    @ViewBuilder private func actionControl(for descriptor: ModelDescriptor, status: ModelStatus) -> some View {
        switch status {
        case .notDownloaded:
            Button("Download") {
                Task { await finalDownloader.download(descriptor.choice) }
            }
            .accessibilityLabel("Download \(descriptor.displayName)")
        case .missingOrCorrupt, .failed:
            Button("Repair") {
                Task { await finalDownloader.repair(descriptor.choice) }
            }
            .accessibilityLabel("Repair \(descriptor.displayName)")
        case .downloaded, .ready:
            Button("Redownload") {
                Task { await finalDownloader.redownload(descriptor.choice) }
            }
            .accessibilityLabel("Redownload \(descriptor.displayName)")
        case .downloading, .verifying:
            EmptyView()
        }
    }

    private func modelStorageAccessibilityValue(
        descriptor: ModelDescriptor,
        status: ModelStatus,
        file: ModelFileSnapshot
    ) -> String {
        var parts = [
            providerLabel(descriptor.provider),
            descriptor.speedHint,
            descriptor.accuracyHint,
            status.label,
            status.detail,
            "Storage \(ModelRegistry.formattedSize(file.sizeBytes))",
        ]
        if isSelected(descriptor) {
            parts.append("Selected")
        }
        return parts.joined(separator: ". ")
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

private struct InputLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.muted.opacity(0.22))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * CGFloat(AudioLevelMeter.normalizedLevel(level)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
