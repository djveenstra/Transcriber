import SwiftUI

/// The primary screen. Records audio, shows live transcription, then runs diarization.
///
/// State machine: .idle → .recording → .processing → .done
struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main content area
                switch viewModel.state {
                case .idle:
                    idleView

                case .recording:
                    recordingView

                case .processing:
                    processingView

                case .done:
                    doneView
                }

                Spacer()

                // Bottom controls
                controlsView
                    .padding(.bottom, 30)
            }
            .navigationTitle("Transcriber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.state == .done {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New") {
                            viewModel.reset()
                        }
                    }
                }
            }
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "mic.circle")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            Text("Tap Record to start")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var recordingView: some View {
        VStack(spacing: 16) {
            // Duration
            Text(viewModel.formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.red)
                .padding(.top, 20)

            // Audio level indicator
            WaveformView(level: viewModel.audioLevel)
                .frame(height: 60)
                .padding(.horizontal)

            // Live transcript (no speaker labels yet)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.liveSegments) { segment in
                            Text(segment.text)
                                .font(.body)
                                .id(segment.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.liveSegments.count) { _, _ in
                    if let last = viewModel.liveSegments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: viewModel.diarizationProgress) {
                Text(viewModel.processingStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Text("Identifying speakers...")
                .font(.title3)

            Text("This takes about 1-2 minutes for a 60-minute recording")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var doneView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.finalSegments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SpeakerBadge(name: segment.speakerName,
                                        colorIndex: segment.speakerColorIndex)
                            Text(segment.timestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(segment.text)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 30) {
            switch viewModel.state {
            case .idle:
                recordButton

            case .recording:
                stopButton

            case .processing:
                EmptyView()

            case .done:
                shareButton
            }
        }
    }

    private var recordButton: some View {
        Button {
            Task { await viewModel.startRecording() }
        } label: {
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 84, height: 84)
            }
        }
    }

    private var stopButton: some View {
        Button {
            Task { await viewModel.stopRecording() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red)
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 84, height: 84)
            }
        }
    }

    private var shareButton: some View {
        ShareLink(
            item: viewModel.exportedText,
            subject: Text("Transcript"),
            message: Text("Here's the transcript from my recording")
        ) {
            Label("Share Transcript", systemImage: "square.and.arrow.up")
                .font(.headline)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - ViewModel

@MainActor
class RecordingViewModel: ObservableObject {
    enum State {
        case idle
        case recording
        case processing
        case done
    }

    @Published var state: State = .idle
    @Published var liveSegments: [TranscriptionSegment] = []
    @Published var finalSegments: [MergedSegment] = []
    @Published var diarizationProgress: Double = 0.0
    @Published var processingStatus: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0

    private var recorder: AudioRecorder?
    private var transcriber: StreamingTranscriber?
    private var recordedFileURL: URL?

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var exportedText: String {
        TranscriptExporter.toText(finalSegments)
    }

    func startRecording() async {
        // Request microphone permission
        let recorder = AudioRecorder()
        let granted = await recorder.requestPermission()
        guard granted else {
            // TODO: show permission denied alert
            return
        }

        state = .recording
        liveSegments = []
        self.recorder = recorder

        // Set up file URL
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "recording_\(Int(Date().timeIntervalSince1970)).wav"
        let fileURL = docs.appendingPathComponent(fileName)
        recordedFileURL = fileURL

        // Set up streaming transcriber
        let transcriber = StreamingTranscriber()
        self.transcriber = transcriber

        // Load whisper model
        if let modelPath = ModelManager.shared.whisperModelPath {
            try? await transcriber.loadModel(
                modelPath: modelPath.path,
                coreMLPath: nil  // Add CoreML path here for acceleration
            )
        }

        // Connect transcriber output to UI
        await transcriber.setOnNewSegments { [weak self] segments in
            Task { @MainActor in
                self?.liveSegments.append(contentsOf: segments)
            }
        }

        // Connect recorder to transcriber
        recorder.onAudioBuffer = { [weak self] samples in
            guard let transcriber = self?.transcriber else { return }
            Task { await transcriber.appendSamples(samples) }
        }

        // Observe audio level
        recorder.$audioLevel
            .assign(to: &$audioLevel)
        recorder.$recordingDuration
            .assign(to: &$recordingDuration)

        // Start recording
        do {
            try recorder.startRecording(to: fileURL)
        } catch {
            state = .idle
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() async {
        state = .processing
        processingStatus = "Finishing transcription..."

        // Stop recording
        recorder?.stopRecording()
        recorder = nil

        // Flush remaining audio to transcriber
        await transcriber?.flush()

        // Run diarization
        guard let audioURL = recordedFileURL,
              let vadPath = ModelManager.shared.sileroVADPath,
              let embedPath = ModelManager.shared.embeddingPath else {
            // Fallback: show transcript without speaker labels
            finalSegments = liveSegments.map {
                MergedSegment(startMs: $0.startMs, endMs: $0.endMs, speaker: "Unknown", text: $0.text)
            }
            state = .done
            return
        }

        do {
            let pipeline = try DiarizationPipeline(
                vadModelPath: vadPath,
                embedderModelPath: embedPath,
                clusteringThreshold: 0.75
            )

            // Observe pipeline progress
            pipeline.$progress
                .assign(to: &$diarizationProgress)
            pipeline.$status
                .assign(to: &$processingStatus)

            // Run diarization
            let diarSegments = try await pipeline.run(audioURL: audioURL)

            // Merge transcription with diarization
            let merged = SegmentMerger.merge(
                transcription: liveSegments,
                diarization: diarSegments
            )

            finalSegments = merged
            state = .done

            // Save to library
            await saveRecording(segments: merged, audioFileName: audioURL.lastPathComponent)

        } catch {
            // Fallback: show transcript without speaker labels
            finalSegments = liveSegments.map {
                MergedSegment(startMs: $0.startMs, endMs: $0.endMs, speaker: "Unknown", text: $0.text)
            }
            state = .done
            print("Diarization failed: \(error)")
        }
    }

    func reset() {
        state = .idle
        liveSegments = []
        finalSegments = []
        diarizationProgress = 0.0
        processingStatus = ""
        audioLevel = 0.0
        recordingDuration = 0.0
        recordedFileURL = nil
    }

    private func saveRecording(segments: [MergedSegment], audioFileName: String) async {
        // This would use SwiftData's ModelContext to persist
        // Implementation depends on how the ModelContext is passed in
        // For now, this is a placeholder
    }
}

// Helper extension for StreamingTranscriber callback
extension StreamingTranscriber {
    func setOnNewSegments(_ callback: @escaping ([TranscriptionSegment]) -> Void) {
        self.onNewSegments = callback
    }
}
