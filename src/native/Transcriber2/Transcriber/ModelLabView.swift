import Foundation
import AVFoundation
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ModelLabResult: Identifiable, Sendable {
    let id = UUID()
    let modelID: String
    let modelName: String
    let loadTime: TimeInterval
    let transcriptionTime: TimeInterval
    let audioDuration: TimeInterval
    let modelSize: String
    let modelStatus: String
    let modelStatusDetail: String
    let transcript: String
    let error: String?

    var speedDescription: String {
        DiagnosticsMetricFormatter.speedDescription(
            audioDuration: audioDuration,
            processingTime: transcriptionTime
        )
    }

    var failureStatus: String {
        error == nil ? "None" : "Failed"
    }

    var transcriptOutput: String {
        transcript.isEmpty ? "No transcript output" : transcript
    }
}

struct ModelLabModelDiagnostics: Equatable, Sendable {
    let size: String
    let status: String
    let statusDetail: String

    static func snapshot(
        for descriptor: ModelDescriptor,
        download: ModelDownloadSnapshot,
        file: ModelFileSnapshot? = nil,
        verification: ModelVerificationSnapshot? = nil
    ) -> ModelLabModelDiagnostics {
        let file = file ?? ModelRegistry.fileSnapshot(for: descriptor)
        let status = ModelRegistry.status(
            for: descriptor,
            download: download,
            file: file,
            verification: verification ?? (file.isPresent ? .ready : .notChecked)
        )
        return ModelLabModelDiagnostics(
            size: ModelRegistry.formattedSize(file.sizeBytes),
            status: status.label,
            statusDetail: status.detail
        )
    }
}

enum ModelLabReport {
    static func report(for results: [ModelLabResult]) -> String {
        results.map { result in
            """
            \(result.modelName)
            Model status: \(result.modelStatus)
            Model detail: \(result.modelStatusDetail)
            Model size: \(result.modelSize)
            Model load time: \(formatSeconds(result.loadTime))
            Processing time: \(formatSeconds(result.transcriptionTime))
            Speed: \(result.speedDescription)
            Failure status: \(result.failureStatus)
            \(result.error.map { "Error: \($0)" } ?? "Transcript:\n\(result.transcriptOutput)")
            """
        }.joined(separator: "\n\n--------------------\n\n")
    }

    static func formatSeconds(_ value: TimeInterval) -> String {
        DiagnosticsMetricFormatter.formatSeconds(value)
    }
}

@MainActor
enum ModelLabPlatformSupport {
    static var supportedChoices: [FinalTranscriptionModelChoice] {
#if os(iOS)
        FinalTranscriptionModelChoice.all
#else
        FinalTranscriptionModelChoice.whisper
#endif
    }

    static var supportedDescriptors: [ModelDescriptor] {
        supportedChoices.map(ModelRegistry.descriptor(for:))
    }

    static var runGuidance: String {
#if os(iOS)
        "Download models in Settings first. Model Lab runs selections one at a time to protect iPhone memory."
#else
        "Download Whisper models in Settings first. Model Lab runs selections one at a time to protect system memory."
#endif
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
        let choices = ModelLabPlatformSupport.supportedChoices.filter { modelIDs.contains($0.id) }
        let duration = (try? AVAudioFile(forReading: audioURL)).map {
            Double($0.length) / $0.processingFormat.sampleRate
        } ?? 0

        for (index, choice) in choices.enumerated() {
            runningModelName = choice.name
            let descriptor = ModelRegistry.descriptor(for: choice)
            let diagnostics = ModelLabModelDiagnostics.snapshot(
                for: descriptor,
                download: downloadSnapshot
            )
            let loadStarted = Date()
            var loadTime: TimeInterval = 0
            var transcriptionTime: TimeInterval = 0
            var transcriptionStarted: Date?
            do {
                let segments: [TranscriptionSegment]
                switch choice.provider {
                case .parakeet:
#if os(iOS)
                    let engine = ParakeetFinalTranscriptionEngine(model: choice)
                    do {
                        try await engine.prepare { [weak self] value in
                            Task { @MainActor in
                                self?.setProgress(index: index, modelCount: choices.count, phaseProgress: value * 0.15)
                            }
                        }
                        loadTime = Date().timeIntervalSince(loadStarted)
                        transcriptionStarted = Date()
                        segments = try await engine.transcribeFile(audioURL) { [weak self] value in
                            Task { @MainActor in
                                self?.setProgress(index: index, modelCount: choices.count, phaseProgress: 0.15 + value * 0.85)
                            }
                        }
                        if let transcriptionStarted {
                            transcriptionTime = Date().timeIntervalSince(transcriptionStarted)
                        }
                        await engine.unload()
                    } catch {
                        await engine.unload()
                        throw error
                    }
#else
                    throw ModelLabRunnerError.unsupportedModel
#endif
                case .whisper:
                    UserDefaults.standard.set(choice.id, forKey: "whisperModel")
                    let engine = WhisperKitTranscriptionEngine()
                    do {
                        try await engine.prepare()
                        loadTime = Date().timeIntervalSince(loadStarted)
                        transcriptionStarted = Date()
                        segments = try await engine.transcribeFile(audioURL) { [weak self] value in
                            Task { @MainActor in
                                self?.setProgress(index: index, modelCount: choices.count, phaseProgress: 0.15 + value * 0.85)
                            }
                        }
                        if let transcriptionStarted {
                            transcriptionTime = Date().timeIntervalSince(transcriptionStarted)
                        }
                        await engine.unload()
                    } catch {
                        await engine.unload()
                        throw error
                    }
                }
                results.append(
                    ModelLabResult(
                        modelID: choice.id,
                        modelName: choice.name,
                        loadTime: loadTime,
                        transcriptionTime: transcriptionTime,
                        audioDuration: duration,
                        modelSize: diagnostics.size,
                        modelStatus: diagnostics.status,
                        modelStatusDetail: diagnostics.statusDetail,
                        transcript: segments.map(\.text).joined(separator: " "),
                        error: nil
                    )
                )
            } catch {
                loadTime = loadTime == 0 ? Date().timeIntervalSince(loadStarted) : loadTime
                if let transcriptionStarted, transcriptionTime == 0 {
                    transcriptionTime = Date().timeIntervalSince(transcriptionStarted)
                }
                results.append(
                    ModelLabResult(
                        modelID: choice.id,
                        modelName: choice.name,
                        loadTime: loadTime,
                        transcriptionTime: transcriptionTime,
                        audioDuration: duration,
                        modelSize: diagnostics.size,
                        modelStatus: diagnostics.status,
                        modelStatusDetail: diagnostics.statusDetail,
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
        ModelLabReport.report(for: results)
    }

    private func setProgress(index: Int, modelCount: Int, phaseProgress: Double) {
        progress = (Double(index) + phaseProgress) / Double(max(modelCount, 1))
    }

    private var downloadSnapshot: ModelDownloadSnapshot {
        switch FinalModelDownloader.shared.state {
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

private enum ModelLabRunnerError: LocalizedError {
    case unsupportedModel

    var errorDescription: String? {
        "This model is not available on Mac."
    }
}

struct ModelLabView: View {
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var runner = ModelLabRunner()
    @StateObject private var finalDownloader = FinalModelDownloader.shared
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
                    .accessibilityHint("Imports an audio file for model comparison.")
                if let importedURL {
                    Label(importedURL.lastPathComponent, systemImage: "waveform")
                        .accessibilityLabel("Imported audio")
                        .accessibilityValue(importedURL.lastPathComponent)
                }
            }

            Section("Models") {
                Text(ModelLabPlatformSupport.runGuidance)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                ForEach(ModelLabPlatformSupport.supportedDescriptors) { descriptor in
                    modelToggle(descriptor)
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
                .accessibilityHint("Runs selected models one at a time on the chosen audio.")

                if runner.isRunning {
                    ProgressView(value: runner.progress)
                        .accessibilityLabel("Model Lab progress")
                        .accessibilityValue("\(Int((runner.progress * 100).rounded())) percent")
                    Text("Running \(runner.runningModelName ?? "model")")
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Running model")
                        .accessibilityValue(runner.runningModelName ?? "model")
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
                    .accessibilityHint("Shares the Model Lab comparison report.")
                }
            }
        }
        .navigationTitle("Model Lab")
        .onAppear {
            finalDownloader.refreshFileStatus()
        }
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

    private func modelToggle(_ descriptor: ModelDescriptor) -> some View {
        let diagnostics = diagnostics(for: descriptor)
        return Toggle(isOn: binding(for: descriptor.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.displayName)
                Text("\(providerLabel(descriptor.provider)) · \(diagnostics.status) · \(diagnostics.size)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text(diagnostics.statusDetail)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .disabled(!isRunnable(diagnostics))
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(providerLabel(descriptor.provider)). \(diagnostics.status). \(diagnostics.size). \(diagnostics.statusDetail)"
        )
    }

    private func resultCard(_ result: ModelLabResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.modelName).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Status", value: result.modelStatus)
                LabeledContent("Size", value: result.modelSize)
                LabeledContent("Load", value: ModelLabReport.formatSeconds(result.loadTime))
                LabeledContent("Transcribe", value: ModelLabReport.formatSeconds(result.transcriptionTime))
                LabeledContent("Speed", value: result.speedDescription)
                LabeledContent("Failure", value: result.failureStatus)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            Divider()
            Text(result.error.map { "Error: \($0)" } ?? result.transcriptOutput)
                .textSelection(.enabled)
        }
        .padding()
        .frame(width: 310, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.modelName)
        .accessibilityValue(resultAccessibilityValue(result))
    }

    private func resultAccessibilityValue(_ result: ModelLabResult) -> String {
        [
            "Status \(result.modelStatus)",
            "Size \(result.modelSize)",
            "Load \(ModelLabReport.formatSeconds(result.loadTime))",
            "Transcribe \(ModelLabReport.formatSeconds(result.transcriptionTime))",
            "Speed \(result.speedDescription)",
            "Failure \(result.failureStatus)",
            result.error.map { "Error \($0)" } ?? "Transcript \(result.transcriptOutput)",
        ].joined(separator: ". ")
    }

    private func diagnostics(for descriptor: ModelDescriptor) -> ModelLabModelDiagnostics {
        ModelLabModelDiagnostics.snapshot(for: descriptor, download: downloadSnapshot)
    }

    private func isRunnable(_ diagnostics: ModelLabModelDiagnostics) -> Bool {
        diagnostics.status == ModelStatus.downloaded.label || diagnostics.status == ModelStatus.ready.label
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

    private func providerLabel(_ provider: FinalTranscriptionProvider) -> String {
        switch provider {
        case .whisper: "Whisper"
        case .parakeet: "Parakeet"
        }
    }
}
