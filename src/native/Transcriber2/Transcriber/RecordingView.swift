import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RecordingView: View {
    var startRequestID: UUID?
    var importRequestID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = TranscriptionSession()
#if os(macOS)
    @StateObject private var launchReadiness = LaunchModelReadiness.shared
#endif
    @State private var showingImporter = false
    @State private var showingCloseConfirmation = false
    @State private var processingTask: Task<Void, Never>?
    @State private var handledStartRequestID: UUID?
    @State private var handledImportRequestID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                statusHeader
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Transcriber 2.0")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: requestClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
#endif
            .storageErrorAlert(session)
            .task {
#if os(macOS)
                await launchReadiness.waitForLivePreviewAttempt()
                await session.prepareSelectedModel()
#endif
            }
            .onAppear {
                handleExternalStartRequest()
                handleExternalImportRequest()
            }
            .onChange(of: startRequestID) { _, _ in
                handleExternalStartRequest()
            }
            .onChange(of: importRequestID) { _, _ in
                handleExternalImportRequest()
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    processingTask = Task {
                        await session.importAudio(url, in: modelContext)
                        if !Task.isCancelled {
                            session.saveCompletedRecording(in: modelContext)
                        }
                        processingTask = nil
                    }
                }
            }
            .interactiveDismissDisabled(session.requiresCloseConfirmation)
            .alert(closeConfirmationTitle, isPresented: $showingCloseConfirmation) {
                Button("Keep Open", role: .cancel) {}
                Button(closeConfirmationActionTitle, role: .destructive) {
                    closeActiveWork()
                }
            } message: {
                Text(closeConfirmationMessage)
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
#if os(macOS)
                launchReadinessStatus
#endif
                Spacer()
            }
        case .recording:
            VStack(spacing: 12) {
                if let notice = session.microphoneFallbackNotice {
                    Label(notice, systemImage: "mic.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if session.liveSegments.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            livePreviewTitle,
                            systemImage: "waveform",
                            description: Text(livePreviewDescription)
                        )
                        if session.livePreviewState == .unavailable {
                            Button {
#if os(macOS)
                                launchReadiness.retry()
#endif
                                session.retryLivePreview()
                            } label: {
                                Label("Retry Live Preview", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                } else {
                    TranscriptList(segments: session.liveSegments)
                }
            }
        case .processing:
            VStack(spacing: 20) {
                Spacer()
                processingTimeline(cancelTitle: "Cancel Processing")
                Text("The final pass is more accurate than the live preview.")
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        case .completed:
            completedTranscriptContent
        case let .failed(message):
            ContentUnavailableView("Couldn’t Process Audio", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var statusHeader: some View {
        HStack {
            Label(statusText, systemImage: statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.state == .recording ? .red : Theme.muted)
            Spacer()
            if session.state == .recording {
                Label(session.activeMicrophoneName ?? MicrophoneRecordingRoute.systemDefaultInputName, systemImage: "mic.fill")
                    .font(.caption.weight(.semibold))
            }
            modelStatus
                .font(.caption2.weight(.semibold))
            if session.state == .recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatDuration(session.recorder.elapsedDuration))
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Elapsed recording time")
                }
            }
        }
        .foregroundStyle(Theme.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording status")
        .accessibilityValue(statusHeaderAccessibilityValue)
    }

    private var controls: some View {
        Group {
            if usesProcessingActionBar {
                processingActionBar
            } else if session.state == .completed {
                completedActionBar
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        controlButtons
                    }
                    VStack(spacing: 10) {
                        controlButtons
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var usesProcessingActionBar: Bool {
        if case .processing = session.state { return true }
        return session.state == .completed && session.isIdentifyingSpeakers
    }

    private var processingActionBar: some View {
        CompactTranscriptActionBar {
            CompactTranscriptActionButton(
                kind: .cancelProcessing,
                isDisabled: !session.canCancelProcessing,
                backgroundColor: .red
            ) {
                cancelProcessing()
            }
        }
    }

    @ViewBuilder private var completedActionBar: some View {
        if !session.isIdentifyingSpeakers {
            CompactTranscriptActionBar {
                if let recording = session.savedRecordingForEditing,
                   TranscriptEditingAvailability.canRenameOrReassignSpeakers(
                    segmentCount: recording.segments.count,
                    isPersistedEditableRecording: true
                   ) {
                    NavigationLink {
                        RecordingDetailView(recording: recording)
                    } label: {
                        CompactTranscriptActionContent(kind: .editSpeakers)
                    }
                    .buttonStyle(CompactTranscriptActionButtonStyle())
                    .accessibilityLabel(CompactTranscriptAction.editSpeakers.label)
                    .accessibilityHint(CompactTranscriptAction.editSpeakers.hint)
                    .accessibilityAddTraits(.isButton)
                }
                TranscriptShareMenu(segments: session.finalSegments, isCompact: true)
                    .buttonStyle(CompactTranscriptActionButtonStyle())
                CompactTranscriptActionButton(kind: .newRecording) {
                    session.reset()
                }
            }
        }
    }

    @ViewBuilder private var controlButtons: some View {
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
            .accessibilityHint("Stops recording and saves the audio before final transcription.")
        } else if session.state == .completed {
            if !session.isIdentifyingSpeakers {
                if let recording = session.savedRecordingForEditing,
                   TranscriptEditingAvailability.canRenameOrReassignSpeakers(
                    segmentCount: recording.segments.count,
                    isPersistedEditableRecording: true
                   ) {
                    NavigationLink {
                        RecordingDetailView(recording: recording)
                    } label: {
                        Label("Edit Speakers", systemImage: "person.text.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Opens speaker rename and reassignment tools.")
                }
                TranscriptShareMenu(segments: session.finalSegments)
                    .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                Button("New") { session.reset() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Clears this completed transcript from the recording screen.")
            }
        } else {
            Button {
                processingTask = Task {
                    await session.startRecording(in: modelContext)
                    processingTask = nil
                }
            } label: {
                Label("Record", systemImage: "mic.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
            .accessibilityHint("Starts recording immediately.")
            Button {
                showingImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(session.state == .preparing)
            .accessibilityHint("Imports an audio file for transcription.")
        }
    }

    private var completedTranscriptContent: some View {
        TranscriptReviewScroll(segments: session.finalSegments) {
            if session.isIdentifyingSpeakers {
                processingTimeline(cancelTitle: "Cancel Speaker Labels")
            }
            SpeakerLabelStatusView(
                presentation: session.speakerLabelStatusPresentation,
                retryAction: speakerLabelRetryAction
            )
            if let diagnostics = session.latestDiagnostics {
                DiagnosticsDisclosureView(diagnostics: diagnostics)
            }
        }
    }

    private var speakerLabelRetryAction: (() -> Void)? {
        guard session.speakerLabelStatusPresentation.showsRetry else { return nil }
        return { retryCurrentSpeakerLabels() }
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
        case let .processing(phase): phase.title
        case .completed: "Final transcript ready"
        case .failed: "Needs attention"
        }
    }

    private var statusIcon: String {
        switch session.state {
        case .recording:
            return "record.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .processing, .preparing:
            return "hourglass"
        case .idle:
            return "circle"
        }
    }

    private var modelStatusAccessibilityText: String {
        switch session.modelState {
        case .notLoaded:
            return "\(session.selectedModelName), not loaded"
        case .loading:
            return "\(session.selectedModelName), loading"
        case let .ready(name):
            if name == session.selectedModelName {
                return "\(name), ready"
            }
            return "Selected \(session.selectedModelName), loaded \(name)"
        case .failed:
            return "\(session.selectedModelName), unavailable"
        }
    }

    private var statusHeaderAccessibilityValue: String {
        var parts = [statusText, "Model \(modelStatusAccessibilityText)"]
        if session.state == .recording {
            let mic = session.activeMicrophoneName ?? MicrophoneRecordingRoute.systemDefaultInputName
            parts.append("Microphone \(mic)")
            parts.append("Elapsed \(formatDuration(session.recorder.elapsedDuration))")
        }
        return parts.joined(separator: ". ")
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

    private func processingTimeline(cancelTitle: String) -> some View {
        ProcessingTimelineView(
            phase: session.currentProcessingPhase ?? .preparingModel,
            progress: session.progress,
            startedAt: session.processingStartedAt,
            canCancel: session.canCancelProcessing,
            cancelTitle: cancelTitle,
            cancelAction: cancelProcessing,
            diagnostics: session.latestDiagnostics
        )
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        Task {
            await session.cancelProcessing()
        }
    }

    private func retryCurrentSpeakerLabels() {
        processingTask = Task {
            await session.retryCurrentSpeakerLabels()
            if !Task.isCancelled {
                session.saveCompletedRecording(in: modelContext)
            }
            processingTask = nil
        }
    }

    private func handleExternalStartRequest() {
        guard let startRequestID, handledStartRequestID != startRequestID else { return }
        handledStartRequestID = startRequestID
        guard canStartNewAudio else { return }
        processingTask = Task {
            await session.startRecording(in: modelContext)
            processingTask = nil
        }
    }

    private func handleExternalImportRequest() {
        guard let importRequestID, handledImportRequestID != importRequestID else { return }
        handledImportRequestID = importRequestID
        guard canStartNewAudio, session.state != .preparing else { return }
        showingImporter = true
    }

    private var canStartNewAudio: Bool {
        switch session.state {
        case .idle, .preparing, .failed:
            true
        case .recording, .processing, .completed:
            false
        }
    }

#if os(macOS)
    @ViewBuilder private var launchReadinessStatus: some View {
        switch launchReadiness.state {
        case .idle, .preparingLivePreview:
            Label("Preparing Live Preview", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        case .livePreviewReady:
            Label("Live Preview prepared", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        case let .failed(message):
            VStack(spacing: 8) {
                Text("Live Preview preparation failed. \(message)")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button {
                    launchReadiness.retry()
                } label: {
                    Label("Retry Preparation", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
#endif

    private func requestClose() {
        if session.requiresCloseConfirmation {
            showingCloseConfirmation = true
        } else {
            processingTask?.cancel()
            processingTask = nil
            dismiss()
        }
    }

    private func closeActiveWork() {
        processingTask?.cancel()
        processingTask = Task {
            let canDismiss = await session.prepareForDismissal(in: modelContext)
            processingTask = nil
            if canDismiss {
                dismiss()
            }
        }
    }

    private var closeConfirmationTitle: String {
        if session.needsDismissalSaveRetry {
            return "Retry saving before closing?"
        }
        return session.state == .recording ? "Stop recording and close?" : "Cancel current work and close?"
    }

    private var closeConfirmationActionTitle: String {
        if session.needsDismissalSaveRetry {
            return "Retry Save and Close"
        }
        return session.state == .recording ? "Stop, Save, and Close" : "Cancel and Close"
    }

    private var closeConfirmationMessage: String {
        if session.needsDismissalSaveRetry {
            return "The audio remains on disk, but its Library entry has not been saved yet."
        }
        if session.state == .recording {
            return "The captured audio will be saved in the Library and marked ready for transcription."
        }
        return "Transcriber will cancel the active preparation or processing step while preserving any audio and transcript already saved."
    }
}

private struct TranscriptExportShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct TranscriptShareMenu: View {
    let segments: [TranscriptSegment]
    var speakerNames: [String: String] = [:]
    var isCompact = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var shareItem: TranscriptExportShareItem?

    var body: some View {
        Menu {
            ForEach(TranscriptExportFormat.allCases) { format in
                Button {
                    shareItem = TranscriptExportShareItem(
                        url: TranscriptExporter.exportFile(
                            segments,
                            speakerNames: speakerNames,
                            as: format
                        )
                    )
                } label: {
                    Label(format.rawValue.uppercased(), systemImage: "doc")
                }
            }
        } label: {
            if isCompact {
                CompactTranscriptActionContent(kind: .share)
            } else {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityLabel(isCompact ? CompactTranscriptAction.share.label : "Share transcript")
        .accessibilityHint(isCompact ? CompactTranscriptAction.share.hint : "Choose TXT, SRT, or JSON export.")
        .accessibilityAddTraits(.isButton)
        .sheet(item: $shareItem) { item in
            SystemShareSheet(item: item.url) {
                shareItem = nil
            }
        }
        // Returning from the system share sheet (e.g. after AirDrop or Save to Files)
        // re-activates the scene without ever calling `onDismiss`, leaving
        // `showingShareSheet` stuck `true` and the sheet's dismiss gesture unusable.
        // Detect the scene becoming active again while the sheet thinks it's still
        // showing and dismiss it manually after a brief delay so SwiftUI has time to
        // settle the scene transition first.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, shareItem != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                shareItem = nil
            }
        }
    }
}

nonisolated enum CompactTranscriptAction: Equatable, Sendable {
    case play(isPlaying: Bool)
    case editSpeakers
    case renameSpeakers
    case share
    case newRecording
    case transcribeRecording
    case cancelProcessing

    var label: String {
        switch self {
        case let .play(isPlaying):
            isPlaying ? "Pause" : "Play"
        case .editSpeakers:
            "Edit Speakers"
        case .renameSpeakers:
            "Rename Speakers"
        case .share:
            "Share Transcript"
        case .newRecording:
            "New Recording"
        case .transcribeRecording:
            "Transcribe Recording"
        case .cancelProcessing:
            "Cancel Processing"
        }
    }

    var compactTitle: String {
        switch self {
        case let .play(isPlaying):
            isPlaying ? "Pause" : "Play"
        case .editSpeakers:
            "Edit"
        case .renameSpeakers:
            "Rename"
        case .share:
            "Share"
        case .newRecording:
            "New"
        case .transcribeRecording:
            "Transcribe"
        case .cancelProcessing:
            "Cancel"
        }
    }

    var hint: String {
        switch self {
        case let .play(isPlaying):
            isPlaying ? "Pauses the original audio." : "Plays the original audio."
        case .editSpeakers:
            "Opens speaker rename and reassignment tools."
        case .renameSpeakers:
            "Opens speaker name fields."
        case .share:
            "Choose TXT, SRT, or JSON export."
        case .newRecording:
            "Clears this completed transcript from the recording screen."
        case .transcribeRecording:
            "Creates a transcript from this shared audio file."
        case .cancelProcessing:
            "Cancels the current processing step."
        }
    }

    var systemImage: String {
        switch self {
        case let .play(isPlaying):
            isPlaying ? "pause.fill" : "play.fill"
        case .editSpeakers, .renameSpeakers:
            "person.text.rectangle"
        case .share:
            "square.and.arrow.up"
        case .newRecording:
            "plus"
        case .transcribeRecording:
            "text.quote"
        case .cancelProcessing:
            "xmark.circle.fill"
        }
    }
}

struct CompactTranscriptActionContent: View {
    let kind: CompactTranscriptAction

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 25, weight: .semibold))
                .frame(height: 27)
            Text(kind.compactTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 58)
        .padding(.horizontal, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct CompactTranscriptActionBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                content
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 76, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct CompactTranscriptActionButton: View {
    let kind: CompactTranscriptAction
    var isDisabled = false
    var backgroundColor = Theme.surface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CompactTranscriptActionContent(kind: kind)
        }
        .buttonStyle(CompactTranscriptActionButtonStyle(backgroundColor: backgroundColor))
        .disabled(isDisabled)
        .accessibilityLabel(kind.label)
        .accessibilityHint(kind.hint)
        .accessibilityAddTraits(.isButton)
    }
}

struct CompactTranscriptActionButtonStyle: ButtonStyle {
    var backgroundColor = Theme.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 64, minHeight: 58)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
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

    private var turns: [TranscriptDisplayTurn] {
        TranscriptTurnGrouping.group(segments)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(turns) { turn in
                        TranscriptTurnCard(turn: turn)
                            .id(turn.id)
                    }
                }
            }
            .onChange(of: segments.count) { _, _ in
                if let last = turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

struct TranscriptCard: View {
    let segment: TranscriptSegment
    var speakerNames: [String: String] = [:]
    var speakerOptions: [String] = []
    var onReassignSpeaker: ((String) -> Void)?

    var body: some View {
        TranscriptTurnCard(
            turn: TranscriptDisplayTurn(segment: segment),
            speakerNames: speakerNames,
            speakerOptions: speakerOptions,
            onReassignSpeaker: onReassignSpeaker
        )
    }
}

struct TranscriptTurnCard: View {
    let turn: TranscriptDisplayTurn
    var speakerNames: [String: String] = [:]
    var speakerOptions: [String] = []
    var onReassignSpeaker: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label {
                        Text(displayName)
                            .font(.caption.bold())
                    } icon: {
                        Text(TranscriptAccessibility.speakerCue(for: turn.speaker, names: speakerNames))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(speakerColor.opacity(0.25))
                            .overlay(Capsule().stroke(speakerColor, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(.white)
                    Text(turn.timestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                }
                Text(turn.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            Spacer(minLength: 8)
            if let onReassignSpeaker, !speakerOptions.isEmpty {
                Menu {
                    ForEach(speakerOptions, id: \.self) { speaker in
                        Button {
                            onReassignSpeaker(speaker)
                        } label: {
                            Label(
                                speakerMenuTitle(for: speaker),
                                systemImage: speaker == turn.speaker ? "checkmark" : "person"
                            )
                        }
                        .disabled(speaker == turn.speaker)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Change speaker for \(displayName)")
                .accessibilityHint("Reassign this transcript card to another speaker.")
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var displayName: String {
        TranscriptExporter.displayName(turn.speaker, names: speakerNames)
    }

    private var accessibilityLabel: String {
        TranscriptAccessibility.label(
            for: turn.displaySegment,
            speakerNames: speakerNames,
            canReassignSpeaker: onReassignSpeaker != nil && !speakerOptions.isEmpty
        )
    }

    private var accessibilityHint: String {
        if onReassignSpeaker == nil || speakerOptions.isEmpty {
            return turn.segmentCount == 1 ? "Transcript segment." : "Grouped speaker turn."
        }
        return turn.segmentCount == 1
            ? "Use the change speaker button to reassign the speaker."
            : "Use the change speaker button to reassign every segment in this grouped speaker turn."
    }

    private var speakerColor: Color {
        let digits = turn.speaker.filter(\.isNumber)
        return Theme.speakerColors[(Int(digits) ?? 0) % Theme.speakerColors.count]
    }

    private func speakerMenuTitle(for speaker: String) -> String {
        let customName = speakerNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultName = TranscriptExporter.displayName(speaker, names: [:])
        guard !customName.isEmpty else { return defaultName }
        return "\(customName) (\(defaultName))"
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
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
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
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}
