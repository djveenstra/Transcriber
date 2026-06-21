import AVFoundation
import Combine
import SwiftData
import SwiftUI

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

            HStack(spacing: 10) {
                RecordingMetadataLabel(
                    systemImage: "timer",
                    text: RecordingLibraryMetadata.durationText(seconds: recording.durationSeconds)
                )
                RecordingMetadataLabel(
                    systemImage: "cpu",
                    text: RecordingLibraryMetadata.modelName(for: recording.finalTranscriptionModelID)
                )
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
            .lineLimit(1)
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

            HStack(spacing: 12) {
                if allowsPlaybackAndTranscription {
                    Button {
                        playback.toggle(url: item.url)
                    } label: {
                        Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        playback.stop()
                        processingTask = Task {
                            await session.importAudio(item.url)
                            if !Task.isCancelled {
                                saveTranscriptIfCompleted()
                            }
                            processingTask = nil
                        }
                    } label: {
                        Label("Transcribe Recording", systemImage: "text.quote")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
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
                    }
                    TranscriptShareMenu(segments: session.finalSegments)
                        .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                }
            }

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
        .storageErrorAlert(session)
        .onDisappear {
            playback.stop()
        }
    }

    private func sharedProcessingTimeline(cancelTitle: String) -> some View {
        ProcessingTimelineView(
            phase: session.currentProcessingPhase ?? .preparingModel,
            progress: session.progress,
            startedAt: session.processingStartedAt,
            canCancel: session.canCancelProcessing,
            cancelTitle: cancelTitle,
            cancelAction: cancelProcessing
        )
    }

    private var sharedCompletedTranscriptContent: some View {
        VStack(spacing: 12) {
            if session.isIdentifyingSpeakers {
                sharedProcessingTimeline(cancelTitle: "Cancel Speaker Labels")
            }
            SpeakerLabelStatusView(
                presentation: session.speakerLabelStatusPresentation,
                retryAction: sharedSpeakerLabelRetryAction
            )
            TranscriptList(segments: session.finalSegments)
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
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        do {
#if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
#endif
            if player == nil {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
            }
            player?.prepareToPlay()
            isPlaying = player?.play() == true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
#endif
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @State private var player: AVAudioPlayer?
    @State private var showingNames = false
    @State private var storageErrorMessage: String?
    @StateObject private var retrySession = TranscriptionSession()
    @StateObject private var audioAvailability = RecordingAudioAvailabilityStore.shared
    @StateObject private var statusActivityStore = RecordingStatusActivityStore.shared
    @State private var retryTask: Task<Void, Never>?

    private var isAudioMissing: Bool {
        audioAvailability.isAudioMissing(for: recording)
    }

    var body: some View {
        VStack(spacing: 12) {
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
                    SpeakerLabelStatusView(
                        presentation: speakerLabelPresentation,
                        retryAction: speakerLabelRetryAction
                    )
                    TranscriptListWithNames(
                        segments: recording.segments,
                        names: recording.speakerNames,
                        onReassignSpeaker: reassignSegment
                    )
                }
            }
            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Label(player?.isPlaying == true ? "Pause" : "Play", systemImage: player?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isAudioMissing)
                Button("Rename Speakers") { showingNames = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(recording.segments.isEmpty)
                TranscriptShareMenu(segments: recording.segments, speakerNames: recording.speakerNames)
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .disabled(recording.segments.isEmpty)
            }
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
        .padding()
        .background(Theme.background)
        .navigationTitle(recording.title)
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
    }

    private func togglePlayback() {
        if player?.isPlaying == true {
            player?.pause()
        } else {
            if player == nil { player = try? AVAudioPlayer(contentsOf: recording.audioURL) }
            player?.play()
        }
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
            cancelAction: cancelRetryProcessing
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
        let currentSegments = recording.segments
        let updatedSegments = TranscriptSegmentReassignment.reassign(
            segmentID: segmentID,
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

struct TranscriptListWithNames: View {
    let segments: [TranscriptSegment]
    let names: [String: String]
    var onReassignSpeaker: ((TranscriptSegment.ID, String) -> Void)?

    private var speakers: [String] {
        TranscriptSegmentReassignment.availableSpeakers(in: segments)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { segment in
                    TranscriptCard(
                        segment: segment,
                        speakerNames: names,
                        speakerOptions: onReassignSpeaker == nil ? [] : speakers
                    ) { speaker in
                        onReassignSpeaker?(segment.id, speaker)
                    }
                }
            }
        }
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
