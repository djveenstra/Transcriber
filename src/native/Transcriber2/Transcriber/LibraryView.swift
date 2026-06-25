@preconcurrency import AVFoundation
import Combine
import os
import SwiftData
import SwiftUI

private nonisolated let playbackLogger = Logger(subsystem: "com.daniel.transcriber2", category: "Playback")

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var sharedInbox = SharedAudioInbox.shared
    @StateObject private var statusActivityStore = RecordingStatusActivityStore.shared
    @StateObject private var audioAvailability = RecordingAudioAvailabilityStore.shared
    @State private var deletionErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty && sharedInbox.items.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "waveform",
                        description: Text("Finished recordings and audio shared from Voice Memos appear here.")
                    )
                } else {
                    List {
                        if !sharedInbox.items.isEmpty {
                            Section("Shared with Transcriber") {
                                ForEach(sharedInbox.items) { item in
                                    NavigationLink {
                                        SharedAudioDetailView(item: item, inbox: sharedInbox)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.name).font(.headline)
                                            Text(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                            }
                        }
                        if !recordings.isEmpty {
                            Section("Transcripts") {
                                ForEach(recordings) { recording in
                                    NavigationLink(value: recording) {
                                        RecordingLibraryRow(
                                            recording: recording,
                                            activity: statusActivityStore.activity(for: recording),
                                            isAudioMissing: audioAvailability.isAudioMissing(for: recording)
                                        )
                                    }
                                }
                                .onDelete(perform: delete)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Recording.self) { recording in
                RecordingDetailView(recording: recording)
            }
            .onAppear {
                sharedInbox.refresh()
                audioAvailability.reconcile(recordings: recordings)
            }
        }
        .alert(
            "Couldn’t Delete Recording",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { isPresented in if !isPresented { deletionErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { deletionErrorMessage = nil }
            },
            message: {
                Text(deletionErrorMessage ?? "")
            }
        )
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let recording = recordings[offset]
            // Keep the SwiftData record if the audio file can't be removed, so the
            // recording (and its transcript) remain accessible rather than orphaned.
            if FileManager.default.fileExists(atPath: recording.audioURL.path) {
                do {
                    try FileManager.default.removeItem(at: recording.audioURL)
                } catch {
                    deletionErrorMessage = "This recording's audio file could not be deleted, so the recording was kept. \(error.localizedDescription)"
                    continue
                }
            }
            modelContext.delete(recording)
        }
    }
}

private struct RecordingLibraryRow: View {
    let recording: Recording
    let activity: RecordingStatusActivity?
    let isAudioMissing: Bool

    private var status: RecordingStatus {
        recording.recordingStatus(activity: activity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title)
                        .font(.headline)
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                RecordingStatusBadge(status: status)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metadataSummary
                }
                VStack(alignment: .leading, spacing: 4) {
                    metadataSummary
                }
            }

            RecordingMetadataLabel(
                systemImage: "person.3.fill",
                text: RecordingLibraryMetadata.speakerLabelText(for: recording, status: status)
            )

            if isAudioMissing {
                Label("Audio file missing. Transcript data was kept.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recording.title)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var metadataSummary: some View {
        RecordingMetadataLabel(
            systemImage: "timer",
            text: RecordingLibraryMetadata.durationText(seconds: recording.durationSeconds)
        )
        RecordingMetadataLabel(
            systemImage: "cpu",
            text: RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID)
        )
    }

    private var accessibilityValue: String {
        var parts = [
            status.display.title,
            recording.createdAt.formatted(date: .abbreviated, time: .shortened),
            RecordingLibraryMetadata.durationText(seconds: recording.durationSeconds),
            RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID),
            RecordingLibraryMetadata.speakerLabelText(for: recording, status: status),
        ]
        if isAudioMissing {
            parts.append("Audio file missing. Transcript data was kept.")
        }
        return parts.joined(separator: ". ")
    }
}

struct RecordingStatusBadge: View {
    let status: RecordingStatus

    var body: some View {
        Label(status.display.title, systemImage: status.display.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(badgeColor.opacity(0.22))
            .overlay(
                Capsule()
                    .stroke(badgeColor.opacity(0.65), lineWidth: 1)
            )
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status")
            .accessibilityValue(status.display.title)
    }

    private var badgeColor: Color {
        switch status {
        case .complete:
            .green
        case .recordingSaved, .needsTranscription:
            Theme.accent
        case .transcribing, .speakerLabeling:
            .cyan
        case .speakerLabelsFailed:
            .yellow
        }
    }
}

private struct RecordingMetadataLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SharedAudioDetailView: View {
    let item: SharedAudioItem
    @ObservedObject var inbox: SharedAudioInbox
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = TranscriptionSession()
    @StateObject private var playback = AudioPlaybackController()
    @State private var processingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            switch session.state {
            case .idle:
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Theme.accent)
                Text(item.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Saved from Voice Memos. Play it now or create a transcript when you are ready.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Label("Sortformer identifies up to four speakers.", systemImage: "person.3.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Spacer()
            case .preparing, .processing:
                Spacer()
                sharedProcessingTimeline(cancelTitle: "Cancel Processing")
                Text("You can leave this screen open while Transcriber works on-device.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            case .completed:
                sharedCompletedTranscriptContent
            case let .failed(message):
                ContentUnavailableView(
                    "Couldn’t Process Audio",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .recording:
                EmptyView()
            }

            sharedAudioActionArea

            if allowsPlaybackAndTranscription {
                Button("Delete Recording", role: .destructive) {
                    playback.stop()
                    inbox.delete(item)
                    dismiss()
                }
            }
        }
        .padding()
        .background(Theme.background)
        .navigationTitle("Shared Recording")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .storageErrorAlert(session)
        .onDisappear {
            playback.stop()
        }
    }

    @ViewBuilder private var sharedAudioActionArea: some View {
        if usesSharedAudioProcessingActionBar {
            sharedAudioProcessingActionBar
        } else if session.state == .completed {
            CompactTranscriptActionBar {
                sharedAudioCompletedControls
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    sharedAudioControls
                }
                VStack(spacing: 10) {
                    sharedAudioControls
                }
            }
        }
    }

    private var usesSharedAudioProcessingActionBar: Bool {
        if case .processing = session.state { return true }
        return session.state == .preparing || (session.state == .completed && session.isIdentifyingSpeakers)
    }

    private var sharedAudioProcessingActionBar: some View {
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

    @ViewBuilder private var sharedAudioControls: some View {
        if allowsPlaybackAndTranscription {
            Button {
                playback.toggle(url: item.url)
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint(playback.isPlaying ? "Pauses this shared audio file." : "Plays this shared audio file.")

            Button {
                playback.stop()
                processingTask = Task {
                    await session.importAudio(item.url, in: modelContext)
                    if !Task.isCancelled {
                        saveTranscriptIfCompleted()
                    }
                    processingTask = nil
                }
            } label: {
                Label("Transcribe Recording", systemImage: "text.quote")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
            .accessibilityHint("Creates a transcript from this shared audio file.")
        } else if session.state == .completed {
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
        }
    }

    @ViewBuilder private var sharedAudioCompletedControls: some View {
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
    }

    private func sharedProcessingTimeline(cancelTitle: String) -> some View {
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

    private var sharedCompletedTranscriptContent: some View {
        TranscriptReviewScroll(segments: session.finalSegments) {
            if session.isIdentifyingSpeakers {
                sharedProcessingTimeline(cancelTitle: "Cancel Speaker Labels")
            }
            SpeakerLabelStatusView(
                presentation: session.speakerLabelStatusPresentation,
                retryAction: sharedSpeakerLabelRetryAction
            )
            if let diagnostics = session.latestDiagnostics {
                DiagnosticsDisclosureView(diagnostics: diagnostics)
            }
        }
    }

    private var sharedSpeakerLabelRetryAction: (() -> Void)? {
        guard session.speakerLabelStatusPresentation.showsRetry else { return nil }
        return { retryCurrentSpeakerLabels() }
    }

    private var allowsPlaybackAndTranscription: Bool {
        switch session.state {
        case .idle, .failed:
            true
        default:
            false
        }
    }

    private func saveTranscriptIfCompleted() {
        guard session.state == .completed else { return }
        session.saveCompletedRecording(in: modelContext)
    }

    private func retryCurrentSpeakerLabels() {
        saveTranscriptIfCompleted()
        processingTask = Task {
            await session.retryCurrentSpeakerLabels()
            if !Task.isCancelled {
                saveTranscriptIfCompleted()
            }
            processingTask = nil
        }
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        Task {
            await session.cancelProcessing()
        }
    }
}

@MainActor
final class AudioPlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlayerNodeAttached = false
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var hasScheduledFile = false
    private var playbackID = UUID()

    func toggle(url: URL) {
        if isPlaying {
            pause()
            return
        }

        play(url: url)
    }

    func stop() {
        resetPlayback(deactivateSession: true)
    }

    private func play(url: URL) {
        do {
#if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
#endif
            if currentURL != url || currentFile == nil || !hasScheduledFile {
                try load(url: url)
            }
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
            isPlaying = true
            playbackLogger.info("Playback started for \(url.lastPathComponent, privacy: .public)")
        } catch {
            playbackLogger.error("Playback failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            resetPlayback(deactivateSession: true)
        }
    }

    private func pause() {
        playerNode.pause()
        isPlaying = false
        playbackLogger.info("Playback paused")
    }

    private func load(url: URL) throws {
        resetPlayback(deactivateSession: false)
        let file = try AVAudioFile(forReading: url)
        guard AudioPlaybackFileInspector.duration(for: file) > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if !isPlayerNodeAttached {
            engine.attach(playerNode)
            isPlayerNodeAttached = true
        }
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
        currentFile = file
        currentURL = url
        scheduleCurrentFile()
    }

    private func scheduleCurrentFile() {
        guard let currentFile else { return }
        let id = UUID()
        playbackID = id
        hasScheduledFile = true
        playerNode.scheduleFile(
            currentFile,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackID == id else { return }
                self.playerNode.stop()
                self.hasScheduledFile = false
                self.isPlaying = false
                playbackLogger.info("Playback finished")
            }
        }
    }

    private func resetPlayback(deactivateSession: Bool) {
        playbackID = UUID()
        playerNode.stop()
        playerNode.reset()
        engine.stop()
        currentFile = nil
        currentURL = nil
        hasScheduledFile = false
        isPlaying = false
#if os(iOS)
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
#endif
    }
}

nonisolated enum AudioPlaybackFileInspector {
    static func duration(for url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return duration(for: file)
    }

    static func duration(for file: AVAudioFile) -> TimeInterval {
        guard file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @StateObject private var playback = CompletedRecordingAudioPlayer()
    @State private var showingNames = false
    @State private var storageErrorMessage: String?
    @StateObject private var retrySession = TranscriptionSession()
    @StateObject private var audioAvailability = RecordingAudioAvailabilityStore.shared
    @StateObject private var statusActivityStore = RecordingStatusActivityStore.shared
    @StateObject private var diagnosticsStore = ProcessingDiagnosticsStore.shared
    @State private var retryTask: Task<Void, Never>?

    private var isAudioMissing: Bool {
        audioAvailability.isAudioMissing(for: recording)
    }

    var body: some View {
        VStack(spacing: 8) {
            if isAudioMissing {
                Label("Audio file missing. The Library row and any saved transcript were kept.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.yellow)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if case .processing = retrySession.state {
                Spacer()
                retryProcessingTimeline
                Spacer()
            } else {
                if recording.transcriptionNeedsRetry {
                    ContentUnavailableView(
                        "Recording Saved",
                        systemImage: "waveform.badge.exclamationmark",
                        description: Text("The audio is safe, but its final transcript still needs to be created.")
                    )
                } else {
                    CompletedRecordingMiniPlayer(
                        player: playback,
                        audioURL: recording.audioURL,
                        isDisabled: isAudioMissing,
                        isCompact: true
                    )
                    TranscriptReviewScroll(
                        segments: recording.segments,
                        speakerNames: recording.speakerNames,
                        speakerOptions: TranscriptSegmentReassignment.availableSpeakers(in: recording.segments),
                        onReassignSpeaker: reassignSegment,
                        onReassignSpeakerGroup: reassignSegments
                    ) {
                        recordingDetailScrollHeader
                    }
                }
            }
            detailActionArea
            if recording.transcriptionNeedsRetry {
                Button {
                    retryTask = Task {
                        await retrySession.retryTranscription(for: recording, in: modelContext)
                        retryTask = nil
                    }
                } label: {
                    Label("Create Transcript", systemImage: "text.quote")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .disabled(isAudioMissing)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Theme.background)
        .navigationTitle(recording.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .storageErrorAlert(retrySession)
        .alert(
            "Storage Issue",
            isPresented: Binding(
                get: { storageErrorMessage != nil },
                set: { isPresented in if !isPresented { storageErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { storageErrorMessage = nil }
            },
            message: {
                Text(storageErrorMessage ?? "")
            }
        )
        .sheet(isPresented: $showingNames) {
            SpeakerRenameView(recording: recording)
        }
        .onDisappear {
            playback.stop()
        }
    }

    private var recordingDetailScrollHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 6) {
                        SpeakerLabelStatusView(
                            presentation: speakerLabelPresentation,
                            retryAction: speakerLabelRetryAction
                        )
                        DiagnosticsDisclosureView(diagnostics: detailDiagnostics)
            }
        }
        .background(Theme.background)
    }

    @ViewBuilder private var detailActionArea: some View {
        if case .processing = retrySession.state {
            CompactTranscriptActionBar {
                CompactTranscriptActionButton(
                    kind: .cancelProcessing,
                    isDisabled: !retrySession.canCancelProcessing,
                    backgroundColor: .red
                ) {
                    cancelRetryProcessing()
                }
            }
        } else {
            VStack(spacing: 6) {
                CompactTranscriptActionBar {
                    detailControls
                }
            }
        }
    }

    @ViewBuilder private var detailControls: some View {
        CompactTranscriptActionButton(
            kind: .renameSpeakers,
            isDisabled: recording.segments.isEmpty
        ) {
            showingNames = true
        }

        TranscriptShareMenu(segments: recording.segments, speakerNames: recording.speakerNames, isCompact: true)
            .buttonStyle(CompactTranscriptActionButtonStyle())
            .disabled(recording.segments.isEmpty)
    }

    private var speakerLabelPresentation: SpeakerLabelStatusPresentation {
        SpeakerLabelStatusPresentation.make(
            status: recording.recordingStatus(activity: statusActivityStore.activity(for: recording)),
            speakerCount: Set(recording.segments.map(\.speaker)).count,
            diarizationNeedsRetry: recording.diarizationNeedsRetry
        )
    }

    private var speakerLabelRetryAction: (() -> Void)? {
        guard speakerLabelPresentation.showsRetry, !isAudioMissing else { return nil }
        return { retrySpeakerLabels() }
    }

    private var retryProcessingTimeline: some View {
        ProcessingTimelineView(
            phase: retrySession.currentProcessingPhase ?? .preparingModel,
            progress: retrySession.progress,
            startedAt: retrySession.processingStartedAt,
            canCancel: retrySession.canCancelProcessing,
            cancelTitle: "Cancel Processing",
            cancelAction: cancelRetryProcessing,
            diagnostics: retrySession.latestDiagnostics ?? diagnosticsStore.diagnostics(forAudioFileName: recording.audioFileName)
        )
    }

    private var detailDiagnostics: ProcessingDiagnostics {
        diagnosticsStore.diagnostics(forAudioFileName: recording.audioFileName)
            ?? ProcessingDiagnostics.derivedSummary(
                for: recording,
                activity: statusActivityStore.activity(for: recording)
            )
    }

    private func retrySpeakerLabels() {
        guard !isAudioMissing else { return }
        retryTask = Task {
            await retrySession.retrySpeakerLabels(for: recording, in: modelContext)
            retryTask = nil
        }
    }

    private func cancelRetryProcessing() {
        retryTask?.cancel()
        retryTask = nil
        Task {
            await retrySession.cancelProcessing()
        }
    }

    private func reassignSegment(_ segmentID: TranscriptSegment.ID, to speaker: String) {
        reassignSegments([segmentID], to: speaker)
    }

    private func reassignSegments(_ segmentIDs: [TranscriptSegment.ID], to speaker: String) {
        let currentSegments = recording.segments
        let updatedSegments = TranscriptSegmentReassignment.reassign(
            segmentIDs: segmentIDs,
            to: speaker,
            in: currentSegments
        )
        guard updatedSegments != currentSegments else { return }

        recording.segments = updatedSegments
        do {
            try modelContext.save()
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "This speaker change could not be saved. It remains visible here, but it may be lost if you leave this screen."
        }
    }
}

@MainActor
final class CompletedRecordingAudioPlayer: ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case preparing
        case ready
        case playing
        case paused
        case failed(String)
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var sourceURL: URL?
    private var playableURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    var isPlaying: Bool {
        state == .playing
    }

    var isPreparing: Bool {
        state == .preparing
    }

    var errorMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    func play(url: URL) async {
        do {
#if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
#endif
            if sourceURL != url || player == nil {
                try await prepare(url: url)
            }
            if currentTime >= duration, duration > 0 {
                seek(to: 0)
            }
            player?.play()
            state = .playing
            playbackLogger.info("Completed recording playback started for \(url.lastPathComponent, privacy: .public)")
        } catch {
            fail("Playback could not start.")
            playbackLogger.error("Completed recording playback failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func pause() {
        player?.pause()
        if player != nil {
            state = .paused
        }
    }

    func seek(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func stop() {
        removeObservers()
        player?.pause()
        player = nil
        sourceURL = nil
        playableURL = nil
        currentTime = 0
        duration = 0
        state = .idle
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
    }

    private func prepare(url: URL) async throws {
        state = .preparing
        removeObservers()

        guard let originalDuration = AudioPlaybackFileInspector.duration(for: url), originalDuration > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let playbackURL = try await CompletedRecordingPlaybackCache.playbackURL(for: url)
        let item = AVPlayerItem(url: playbackURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        sourceURL = url
        playableURL = playbackURL
        duration = originalDuration
        currentTime = 0
        addObservers(player: player, item: item)
        state = .ready
    }

    private func addObservers(player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = self?.duration ?? 0
                self?.state = .paused
            }
        }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func seek(to seconds: TimeInterval) {
        let target = CompletedRecordingPlaybackPresentation.clampedTime(seconds, duration: duration)
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
    }

    private func fail(_ message: String) {
        removeObservers()
        player = nil
        sourceURL = nil
        playableURL = nil
        currentTime = 0
        duration = 0
        state = .failed(message)
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
    }
}

struct CompletedRecordingMiniPlayer: View {
    @ObservedObject var player: CompletedRecordingAudioPlayer
    let audioURL: URL
    var isDisabled: Bool
    var isCompact: Bool = false

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
            HStack(spacing: isCompact ? 8 : 12) {
                playbackButton(systemImage: "gobackward.10", label: "Back 10 seconds", hint: "Moves playback back by 10 seconds.") {
                    player.seek(by: -10)
                }
                .disabled(isDisabled || player.duration <= 0)

                playbackButton(
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                    label: player.isPlaying ? "Pause" : "Play",
                    hint: player.isPlaying ? "Pauses the recording." : "Plays the recording."
                ) {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        Task { await player.play(url: audioURL) }
                    }
                }
                .disabled(isDisabled || player.isPreparing)

                playbackButton(systemImage: "goforward.10", label: "Forward 10 seconds", hint: "Moves playback forward by 10 seconds.") {
                    player.seek(by: 10)
                }
                .disabled(isDisabled || player.duration <= 0)

                Spacer(minLength: 8)

                Text(CompletedRecordingPlaybackPresentation.timeRangeText(
                    currentTime: player.currentTime,
                    duration: player.duration
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            }

            ProgressView(value: progress)
                .tint(Theme.accent)
                .accessibilityLabel("Playback progress")
                .accessibilityValue(CompletedRecordingPlaybackPresentation.accessibilityProgressValue(
                    currentTime: player.currentTime,
                    duration: player.duration
                ))

            if player.isPreparing {
                Label("Preparing playback", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(isCompact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 8 : 10))
        .overlay(RoundedRectangle(cornerRadius: isCompact ? 8 : 10).stroke(Theme.border))
        .accessibilityElement(children: .contain)
    }

    private func playbackButton(
        systemImage: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 18 : 22, weight: .semibold))
                .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Theme.background.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }
}

@MainActor
enum CompletedRecordingPlaybackCache {
    static func playbackURL(for sourceURL: URL) async throws -> URL {
        guard sourceURL.pathExtension.localizedCaseInsensitiveCompare("caf") == .orderedSame else {
            return sourceURL
        }

        let outputURL = cacheURL(for: sourceURL)
        if isCacheCurrent(sourceURL: sourceURL, outputURL: outputURL) {
            return outputURL
        }

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        exportSession.shouldOptimizeForNetworkUse = false
        try await exportSession.export(to: outputURL, as: .m4a)

        guard let duration = AudioPlaybackFileInspector.duration(for: outputURL), duration > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return outputURL
    }

    static func cacheURL(for sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return cacheDirectory.appendingPathComponent("\(baseName).m4a")
    }

    static func isCacheCurrent(sourceURL: URL, outputURL: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: outputURL.path),
              let sourceDate = try? manager.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date,
              let outputDate = try? manager.attributesOfItem(atPath: outputURL.path)[.modificationDate] as? Date else {
            return false
        }
        return outputDate >= sourceDate
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Transcriber2Beta", isDirectory: true)
            .appendingPathComponent("Playback", isDirectory: true)
    }
}

nonisolated enum CompletedRecordingPlaybackPresentation {
    static func clampedTime(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }

    static func timeRangeText(currentTime: TimeInterval, duration: TimeInterval) -> String {
        "\(timeText(currentTime)) / \(timeText(duration))"
    }

    static func accessibilityProgressValue(currentTime: TimeInterval, duration: TimeInterval) -> String {
        "\(timeText(currentTime)) of \(timeText(duration))"
    }

    static func timeText(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TranscriptListWithNames: View {
    let segments: [TranscriptSegment]
    let names: [String: String]
    var onReassignSpeaker: ((TranscriptSegment.ID, String) -> Void)?
    var onReassignSpeakerGroup: (([TranscriptSegment.ID], String) -> Void)?

    private var speakers: [String] {
        TranscriptSegmentReassignment.availableSpeakers(in: segments)
    }

    var body: some View {
        TranscriptReviewScroll(
            segments: segments,
            speakerNames: names,
            speakerOptions: canReassign ? speakers : [],
            onReassignSpeaker: onReassignSpeaker == nil ? nil : { segmentID, speaker in
                onReassignSpeaker?(segmentID, speaker)
            },
            onReassignSpeakerGroup: onReassignSpeakerGroup ?? { segmentIDs, speaker in
                for segmentID in segmentIDs {
                    onReassignSpeaker?(segmentID, speaker)
                }
            }
        ) {
            EmptyView()
        }
    }

    private var canReassign: Bool {
        onReassignSpeaker != nil || onReassignSpeakerGroup != nil
    }
}

struct TranscriptReviewScroll<Header: View>: View {
    let segments: [TranscriptSegment]
    var speakerNames: [String: String] = [:]
    var speakerOptions: [String] = []
    var stickyHeader: Bool = false
    let header: Header
    var onReassignSpeaker: ((TranscriptSegment.ID, String) -> Void)?
    var onReassignSpeakerGroup: (([TranscriptSegment.ID], String) -> Void)?

    private var turns: [TranscriptDisplayTurn] {
        TranscriptTurnGrouping.group(segments)
    }

    init(
        segments: [TranscriptSegment],
        speakerNames: [String: String] = [:],
        speakerOptions: [String] = [],
        stickyHeader: Bool = false,
        onReassignSpeaker: ((TranscriptSegment.ID, String) -> Void)? = nil,
        onReassignSpeakerGroup: (([TranscriptSegment.ID], String) -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.segments = segments
        self.speakerNames = speakerNames
        self.speakerOptions = speakerOptions
        self.stickyHeader = stickyHeader
        self.onReassignSpeaker = onReassignSpeaker
        self.onReassignSpeakerGroup = onReassignSpeakerGroup
        self.header = header()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 12,
                    pinnedViews: stickyHeader ? [.sectionHeaders] : []
                ) {
                    if stickyHeader {
                        Section {
                            transcriptCards
                        } header: {
                            header
                                .padding(.bottom, 4)
                                .background(Theme.background)
                        }
                    } else {
                        header
                        transcriptCards
                    }
                }
            }
            .onChange(of: segments.count) { _, _ in
                if let last = turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private var transcriptCards: some View {
        ForEach(turns) { turn in
            TranscriptTurnCard(
                turn: turn,
                speakerNames: speakerNames,
                speakerOptions: canReassign ? speakerOptions : []
            ) { speaker in
                if let onReassignSpeakerGroup {
                    onReassignSpeakerGroup(turn.segmentIDs, speaker)
                } else {
                    for segmentID in turn.segmentIDs {
                        onReassignSpeaker?(segmentID, speaker)
                    }
                }
            }
            .id(turn.id)
        }
    }

    private var canReassign: Bool {
        onReassignSpeaker != nil || onReassignSpeakerGroup != nil
    }
}

struct SpeakerRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var recording: Recording
    @State private var names: [String: String] = [:]

    private var speakers: [String] {
        Array(Set(recording.segments.map(\.speaker))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(speakers, id: \.self) { speaker in
                    TextField(
                        TranscriptExporter.displayName(speaker, names: [:]),
                        text: Binding(
                            get: { names[speaker, default: ""] },
                            set: { names[speaker] = $0 }
                        )
                    )
                    .accessibilityLabel("Name for \(TranscriptExporter.displayName(speaker, names: [:]))")
                }
            }
            .navigationTitle("Rename Speakers")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        recording.speakerNames = names
                        dismiss()
                    }
                }
            }
            .onAppear { names = recording.speakerNames }
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}
