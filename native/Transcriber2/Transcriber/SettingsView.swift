import SwiftUI

struct SettingsView: View {
    @AppStorage("keepAudioFiles") private var keepAudioFiles = true
    @AppStorage("whisperModel") private var whisperModel = WhisperModelChoice.defaultID
    @StateObject private var downloader = WhisperModelDownloader.shared
#if os(iOS)
    @AppStorage("finalTranscriptionModel") private var finalModel = FinalTranscriptionModelChoice.defaultID
    @StateObject private var finalDownloader = FinalModelDownloader.shared
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
                    finalDownloadControl
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
                    downloadControl
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
#if os(iOS)
                finalModel = FinalTranscriptionModelChoice.selectedID()
#endif
            }
            .onChange(of: whisperModel) { _, value in
                downloader.selectionChanged(to: value)
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

    @ViewBuilder private var finalDownloadControl: some View {
        switch finalDownloader.state {
        case let .downloading(id, progress) where id == finalModel:
            VStack(alignment: .leading) {
                ProgressView(value: progress)
                Text("Downloading \(selectedFinalModel.name): \(progress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        case let .ready(id) where id == finalModel:
            Label("Selected model downloaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        case let .failed(id, message) where id == finalModel:
            VStack(alignment: .leading) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try Download Again") {
                    Task { await finalDownloader.download(selectedFinalModel) }
                }
            }
        default:
            Button("Download Selected Model") {
                Task { await finalDownloader.download(selectedFinalModel) }
            }
        }
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

    @ViewBuilder private var downloadControl: some View {
        switch downloader.state {
        case .idle where downloader.modelID == whisperModel, .idle:
            Button("Download Selected Model") {
                Task { await downloader.download(whisperModel) }
            }
        case let .downloading(progress) where downloader.modelID == whisperModel:
            VStack(alignment: .leading) {
                ProgressView(value: progress)
                Text("Downloading \(selectedModel.name): \(progress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        case .ready where downloader.modelID == whisperModel:
            Label("Selected model downloaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        case let .failed(message) where downloader.modelID == whisperModel:
            VStack(alignment: .leading) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try Download Again") {
                    Task { await downloader.download(whisperModel) }
                }
            }
        default:
            Button("Download Selected Model") {
                Task { await downloader.download(whisperModel) }
            }
        }
    }
}
