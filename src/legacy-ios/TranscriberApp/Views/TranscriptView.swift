import SwiftUI

/// Displays the full transcript of a recording with speaker labels and colors.
struct TranscriptView: View {
    let recording: Recording
    @State private var selectedFormat: ExportFormat = .text

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Header info
                headerSection

                Divider()

                // Transcript segments
                ForEach(recording.segments) { segment in
                    segmentRow(segment)
                }
            }
            .padding()
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        ShareLink(
                            item: TranscriptExporter.export(segments: recording.segments, format: format),
                            subject: Text(recording.title),
                            message: Text("Transcript")
                        ) {
                            Label("Share as \(format.displayName)", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(recording.formattedDuration, systemImage: "clock")
                Spacer()
                Label("\(recording.numSpeakers) speaker\(recording.numSpeakers == 1 ? "" : "s")",
                      systemImage: "person.2")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(recording.formattedDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func segmentRow(_ segment: MergedSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SpeakerBadge(name: segment.speakerName, colorIndex: segment.speakerColorIndex)
                Text(segment.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
