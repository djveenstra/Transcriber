#if os(iOS)
import AVFoundation
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ModelLabResult: Identifiable, Sendable {
    let id = UUID()
    let modelID: String
    let modelName: String
    let elapsed: TimeInterval
    let audioDuration: TimeInterval
    let transcript: String
    let error: String?

    var speedDescription: String {
        guard elapsed > 0 else { return "—" }
        return String(format: "%.1f× real time", audioDuration / elapsed)
    }
}

@MainActor
final class ModelLabRunner: ObservableObject {
    @Published private(set) var results: [ModelLabResult] = []
    @Published private(set) var runningModelName: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRunning = false

    func run(audioURL: URL, modelIDs: Set<String>, deleteAudioWhenFinished: Bool = false) async {
        guard !isRunning else { return }
        defer {
            if deleteAudioWhenFinished {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        isRunning = true
        results = []
        progress = 0
        let choices = FinalTranscriptionModelChoice.all.filter { modelIDs.contains($0.id) }
        let duration = (try? AVAudioFile(forReading: audioURL)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0

        for (index, choice) in choices.enumerated() {
            runningModelName = choice.name
            let started = Date()
            do {
                let segments: [TranscriptionSegment]
                switch choice.provider {
                case .parakeet:
                    let engine = ParakeetFinalTranscriptionEngine(model: choice)
                    segments = try await engine.transcribeFile(audioURL) { [weak self] value in
                        Task { @MainActor in
                            self?.progress = (Double(index) + value) / Double(max(choices.count, 1))
                        }
                    }
                    await engine.unload()
                case .whisper:
                    UserDefaults.standard.set(choice.id, forKey: "whisperModel")
                    let engine = WhisperKitTranscriptionEngine()
                    segments = try await engine.transcribeFile(audioURL) { [weak self] value in
                        Task { @MainActor in
                            self?.progress = (Double(index) + value) / Double(max(choices.count, 1))
                        }
                    }
                    await engine.unload()
                }
                results.append(
                    ModelLabResult(
                        modelID: choice.id,
                        modelName: choice.name,
                        elapsed: Date().timeIntervalSince(started),
                        audioDuration: duration,
                        transcript: segments.map(\.text).joined(separator: " "),
                        error: nil
                    )
                )
            } catch {
                results.append(
                    ModelLabResult(
                        modelID: choice.id,
                        modelName: choice.name,
                        elapsed: Date().timeIntervalSince(started),
                        audioDuration: duration,
                        transcript: "",
                        error: error.localizedDescription
                    )
                )
            }
            progress = Double(index + 1) / Double(max(choices.count, 1))
        }
        runningModelName = nil
        isRunning = false
    }

    var report: String {
        results.map { result in
            """
            \(result.modelName)
            Time: \(result.elapsed.formatted(.number.precision(.fractionLength(1)))) seconds
            Speed: \(result.speedDescription)
            \(result.error.map { "Error: \($0)" } ?? result.transcript)
            """
        }.joined(separator: "\n\n--------------------\n\n")
    }
}

struct ModelLabView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var runner = ModelLabRunner()
    @State private var selectedAudioFileName = ""
    @State private var selectedModels: Set<String> = []
    @State private var showingImporter = false
    @State private var importedURL: URL?

    var body: some View {
        List {
            Section("Audio") {
                Picker("Recording", selection: $selectedAudioFileName) {
                    Text("Choose a recording").tag("")
                    ForEach(recordings) { recording in
                        Text(recording.title).tag(recording.audioFileName)
                    }
                }
                Button("Import Audio for Comparison") { showingImporter = true }
                if let importedURL {
                    Label(importedURL.lastPathComponent, systemImage: "waveform")
                }
            }

            Section("Models") {
                Text("Download models in Settings first. Model Lab runs selections one at a time to protect iPhone memory.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                ForEach(FinalTranscriptionModelChoice.all) { model in
                    Toggle(isOn: binding(for: model.id)) {
                        VStack(alignment: .leading) {
                            Text(model.name)
                            Text(model.isDownloaded ? (model.provider == .parakeet ? "Parakeet · downloaded" : "Whisper · downloaded") : "Download in Settings first")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .disabled(!model.isDownloaded)
                }
            }

            Section {
                Button {
                    guard let url = selectedAudioURL else { return }
                    Task {
                        await runner.run(
                            audioURL: url,
                            modelIDs: selectedModels,
                            deleteAudioWhenFinished: importedURL != nil
                        )
                        if importedURL == url { importedURL = nil }
                    }
                } label: {
                    Label("Run Comparison", systemImage: "speedometer")
                }
                .disabled(selectedAudioURL == nil || selectedModels.isEmpty || runner.isRunning)

                if runner.isRunning {
                    ProgressView(value: runner.progress)
                    Text("Running \(runner.runningModelName ?? "model")")
                        .foregroundStyle(Theme.muted)
                }
            }

            if !runner.results.isEmpty {
                Section("Results") {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(runner.results) { result in
                                resultCard(result)
                            }
                        }
                    }
                    ShareLink(item: runner.report) {
                        Label("Share Comparison Report", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Model Lab")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
            guard case let .success(source) = result else { return }
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            let destination = AppStoragePaths.rootDirectory.appendingPathComponent("model-lab-\(UUID().uuidString).\(source.pathExtension)")
            if let importedURL {
                try? FileManager.default.removeItem(at: importedURL)
            }
            try? FileManager.default.copyItem(at: source, to: destination)
            importedURL = destination
            selectedAudioFileName = ""
        }
    }

    private var selectedAudioURL: URL? {
        if let importedURL { return importedURL }
        return recordings.first { $0.audioFileName == selectedAudioFileName }?.audioURL
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedModels.contains(id) },
            set: { enabled in
                if enabled { selectedModels.insert(id) } else { selectedModels.remove(id) }
            }
        )
    }

    private func resultCard(_ result: ModelLabResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.modelName).font(.headline)
            Text("\(result.elapsed.formatted(.number.precision(.fractionLength(1)))) sec · \(result.speedDescription)")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Divider()
            Text(result.error ?? result.transcript)
                .textSelection(.enabled)
        }
        .padding()
        .frame(width: 310, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
#endif
