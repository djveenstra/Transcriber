import AVFoundation
import Combine
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @StateObject private var sharedInbox = SharedAudioInbox.shared

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
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(recording.title).font(.headline)
                                    if recording.transcriptionNeedsRetry {
                                        Label("Needs transcription", systemImage: "text.badge.exclamationmark")
                                            .font(.caption)
                                            .foregroundStyle(Theme.accent)
                                    }
                                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
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
            .onAppear { sharedInbox.refresh() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let recording = recordings[offset]
            try? FileManager.default.removeItem(at: recording.audioURL)
            modelContext.delete(recording)
        }
    }
}

struct SharedAudioDetailView: View {
    let item: SharedAudioItem
    @ObservedObject var inbox: SharedAudioInbox
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = TranscriptionSession()
    @StateObject private var playback = AudioPlaybackController()
    @State private var hasSavedTranscript = false

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
                ProgressView(value: session.progress)
                    .tint(Theme.accent)
                    .frame(maxWidth: 420)
                Text(processingMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("You can leave this screen open while Transcriber works on-device.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            case .completed:
                VStack(spacing: 12) {
                    if let note = session.completionNote {
                        Label(note, systemImage: "person.crop.circle.badge.questionmark")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                            .padding()
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    TranscriptList(segments: session.finalSegments)
                }
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
                        Task {
                            await session.importAudio(item.url)
                            saveTranscriptIfCompleted()
                        }
                    } label: {
                        Label("Transcribe Recording", systemImage: "text.quote")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                } else if session.state == .completed {
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
        .onDisappear { playback.stop() }
    }

    private var processingMessage: String {
        if case let .processing(message) = session.state {
            return message
        }
        return "Preparing transcription"
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
        guard session.state == .completed, !hasSavedTranscript else { return }
        session.saveCompletedRecording(in: modelContext)
        hasSavedTranscript = true
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
    @StateObject private var retrySession = TranscriptionSession()

    var body: some View {
        VStack(spacing: 12) {
            if case let .processing(message) = retrySession.state {
                Spacer()
                ProgressView(value: retrySession.progress)
                    .tint(Theme.accent)
                    .frame(maxWidth: 420)
                Text(message).font(.headline)
                Spacer()
            } else {
                if recording.transcriptionNeedsRetry {
                    ContentUnavailableView(
                        "Recording Saved",
                        systemImage: "waveform.badge.exclamationmark",
                        description: Text("The audio is safe, but its final transcript still needs to be created.")
                    )
                } else {
                    TranscriptListWithNames(segments: recording.segments, names: recording.speakerNames)
                }
            }
            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Label(player?.isPlaying == true ? "Pause" : "Play", systemImage: player?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Rename Speakers") { showingNames = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(recording.segments.isEmpty)
                TranscriptShareMenu(segments: recording.segments, speakerNames: recording.speakerNames)
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
                .disabled(recording.segments.isEmpty)
            }
            if recording.transcriptionNeedsRetry {
                Button {
                    Task {
                        await retrySession.retryTranscription(for: recording, in: modelContext)
                        try? modelContext.save()
                    }
                } label: {
                    Label("Create Transcript", systemImage: "text.quote")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent))
            }
            if recording.diarizationNeedsRetry {
                Label("Speaker labels could not finish. The transcript and audio are safe.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                Button {
                    Task {
                        await retrySession.retrySpeakerLabels(for: recording)
                        try? modelContext.save()
                    }
                } label: {
                    Label("Retry Speaker Labels", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding()
        .background(Theme.background)
        .navigationTitle(recording.title)
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
}

struct TranscriptListWithNames: View {
    let segments: [TranscriptSegment]
    let names: [String: String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(segments) { TranscriptCard(segment: $0, speakerNames: names) }
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
