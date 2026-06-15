import SwiftUI
import SwiftData

/// Shows a list of all past recordings with their transcripts.
struct LibraryView: View {
    @Query(sort: \Recording.dateCreated, order: .reverse) private var recordings: [Recording]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsList
                }
            }
            .navigationTitle("Library")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No recordings yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Your transcribed recordings will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var recordingsList: some View {
        List {
            ForEach(recordings) { recording in
                NavigationLink(destination: TranscriptView(recording: recording)) {
                    RecordingRow(recording: recording)
                }
            }
            .onDelete(perform: deleteRecordings)
        }
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            // Delete audio file
            if let audioURL = recording.audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            modelContext.delete(recording)
        }
    }
}

/// A single row in the library list.
struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label("\(recording.numSpeakers) speaker\(recording.numSpeakers == 1 ? "" : "s")",
                      systemImage: "person.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(recording.formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: Recording.self, inMemory: true)
}
