import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = TranscriptionSession()
    @State private var showingImporter = false
    @State private var processingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusHeader
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding()
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Transcriber 2.0")
            .storageErrorAlert(session)
            .task {
#if os(macOS)
                await session.prepareSelectedModel()
#endif
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    processingTask = Task {
                        await session.importAudio(url)
                        if !Task.isCancelled {
                            session.saveCompletedRecording(in: modelContext)
                        }
                        processingTask = nil
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .idle, .preparing:
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Theme.accent)
#if os(iOS)
                Text("Private, on-device transcription")
                    .font(.title2.bold())
#else
                Text("Private, on-device Whisper transcription")
                    .font(.title2.bold())
#endif
                Text("Record a conversation or import an audio file.")
                    .foregroundStyle(Theme.muted)
                Label("Sortformer identifies up to four speakers.", systemImage: "person.3.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        case .recording:
            VStack(spacing: 12) {
                if session.liveSegments.isEmpty {
                    ContentUnavailableView(
                        livePreviewTitle,
                        systemImage: "waveform",
                        description: Text(livePreviewDescription)
                    )
                } else {
                    TranscriptList(segments: session.liveSegments)
                }
            }
        case .processing:
            VStack(spacing: 20) {
                Spacer()
                ProgressView(value: session.progress)
                    .tint(Theme.accent)
                    .frame(maxWidth: 420)
                Text(processingMessage)
                    .font(.headline)
                Text("The final pass is more accurate than the live preview.")
                    .foregroundStyle(Theme.muted)
                Button {
                    cancelProcessing()
                } label: {
                    Label("Cancel Processing", systemImage: "xmark.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
        case .completed:
            VStack(spacing: 12) {
                if session.isIdentifyingSpeakers {
                    VStack(spacing: 6) {
                        ProgressView(value: session.progress)
                            .tint(Theme.accent)
                        Text("Transcript ready. Identifying speakers…")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                    }
                }
                if let note = session.completionNote {
                    Label(note, systemImage: "person.crop.circle.badge.questionmark")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                        .padding()
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                TranscriptList(segments: session.finalSegments)
                if session.diarizationNeedsRetry {
                    Button {
                        processingTask = Task {
                            await session.retryCurrentSpeakerLabels()
                            if !Task.isCancelled {
                                session.saveCompletedRecording(in: modelContext)
                            }
                            processingTask = nil
                        }
                    } label: {
                        Label("Retry Speaker Labels", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        case let .failed(message):
            ContentUnavailableView("Couldn’t Process Audio", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(session.state == .recording ? .red : Theme.accent)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.subheadline.weight(.semibold))
            Spacer()
            modelStatus
            if session.state == .recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatDuration(session.recorder.elapsedDuration))
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .foregroundStyle(Theme.muted)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if session.state == .recording {
                Button {
                    processingTask = Task {
                        await session.stopRecording(in: modelContext)
                        if !Task.isCancelled {
                            session.saveCompletedRecording(in: modelContext)
                        }
                        processingTask = nil
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: .red))
            } else if session.state == .completed {
                if session.isIdentifyingSpeakers {
                    Button {
                        cancelProcessing()
                    } label: {
                        Label("Cancel Speaker Labels", systemImage: "xmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    TranscriptShareMenu(segments: session.finalSegments)
                    .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                    Button("New") { session.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                Button {
                    Task { await session.startRecording() }
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                Button {
                    showingImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(session.state == .preparing)
            }
        }
        .padding(.bottom, 8)
    }

    private var statusText: String {
        switch session.state {
        case .idle: "Ready"
        case .preparing: "Preparing to record"
        case .recording:
            switch session.livePreviewState {
#if os(iOS)
            case .loading: "Recording safely; Parakeet live text is loading"
            case .ready: "Recording with live Parakeet preview"
#else
            case .loading: "Recording safely; Whisper is loading"
            case .ready: "Recording with live Whisper preview"
#endif
            case .unavailable: "Recording safely; live preview unavailable"
            case .inactive: "Recording"
            }
        case let .processing(message): message
        case .completed: "Final transcript ready"
        case .failed: "Needs attention"
        }
    }

    private var livePreviewTitle: String {
        return switch session.livePreviewState {
        case .loading: "Preparing Live Preview"
        case .ready: "Listening for Speech"
        case .unavailable: "Live Preview Unavailable"
        case .inactive: "Recording"
        }
    }

    private var livePreviewDescription: String {
        if let note = session.livePreviewNote { return note }
        return switch session.livePreviewState {
        case .loading: "Recording is already safe. Live text will catch up when the model is ready."
        case .ready: "Speak normally. The first words should appear after a few seconds."
        case .unavailable: "The recording is safe and the final transcript will still run after you stop."
        case .inactive: "Recording audio."
        }
    }

    private var processingMessage: String {
        if case let .processing(message) = session.state { return message }
        return "Preparing transcription"
    }

    @ViewBuilder private var modelStatus: some View {
        switch session.modelState {
        case .notLoaded:
            Text("\(session.selectedModelName) · not loaded")
        case .loading:
            Text("\(session.selectedModelName) · loading")
        case let .ready(name):
            if name == session.selectedModelName {
                Text("\(name) · ready")
            } else {
                Text("Selected: \(session.selectedModelName) · Loaded: \(name)")
            }
        case .failed:
            Text("\(session.selectedModelName) · unavailable")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        Task {
            await session.cancelProcessing()
        }
    }
}

struct TranscriptShareMenu: View {
    let segments: [TranscriptSegment]
    var speakerNames: [String: String] = [:]
    @Environment(\.scenePhase) private var scenePhase
    @State private var shareURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        Menu {
            ForEach(TranscriptExportFormat.allCases) { format in
                Button {
                    shareURL = TranscriptExporter.exportFile(
                        segments,
                        speakerNames: speakerNames,
                        as: format
                    )
                    showingShareSheet = true
                } label: {
                    Label(format.rawValue.uppercased(), systemImage: "doc")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: clearShareItem) {
            if let shareURL {
                SystemShareSheet(item: shareURL) {
                    showingShareSheet = false
                }
            }
        }
        // Returning from the system share sheet (e.g. after AirDrop or Save to Files)
        // re-activates the scene without ever calling `onDismiss`, leaving
        // `showingShareSheet` stuck `true` and the sheet's dismiss gesture unusable.
        // Detect the scene becoming active again while the sheet thinks it's still
        // showing and dismiss it manually after a brief delay so SwiftUI has time to
        // settle the scene transition first.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, showingShareSheet else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                showingShareSheet = false
            }
        }
    }

    private func clearShareItem() {
        shareURL = nil
    }
}

#if os(iOS)
struct SystemShareSheet: UIViewControllerRepresentable {
    let item: URL
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onComplete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct SystemShareSheet: View {
    let item: URL
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Share Transcript")
                .font(.headline)
            ShareLink(item: item) {
                Label("Share File", systemImage: "square.and.arrow.up")
            }
            Button("Done", action: onComplete)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 180)
    }
}
#endif

struct TranscriptList: View {
    let segments: [TranscriptSegment]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments) { segment in
                        TranscriptCard(segment: segment)
                            .id(segment.id)
                    }
                }
            }
            .onChange(of: segments.count) { _, _ in
                if let last = segments.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

struct TranscriptCard: View {
    let segment: TranscriptSegment
    var speakerNames: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(TranscriptExporter.displayName(segment.speaker, names: speakerNames))
                    .font(.caption.bold())
                    .foregroundStyle(speakerColor)
                Text(segment.timestamp)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            Text(segment.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var speakerColor: Color {
        let digits = segment.speaker.filter(\.isNumber)
        return Theme.speakerColors[(Int(digits) ?? 0) % Theme.speakerColors.count]
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(Theme.surface)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}
