import Foundation
import Testing
@testable import Transcriber

@MainActor
struct DashboardTests {
    @Test func recentAttentionFiltersAndSortsByRecordingStatus() {
        let older = Date(timeIntervalSinceReferenceDate: 10)
        let newer = Date(timeIntervalSinceReferenceDate: 30)
        let newest = Date(timeIntervalSinceReferenceDate: 50)
        let items = [
            item(title: "Complete", date: newest, status: .complete),
            item(title: "Needs Labels", date: older, status: .speakerLabelsFailed),
            item(title: "Needs Transcript", date: newer, status: .needsTranscription),
        ]

        let attention = DashboardRecordingAttention.recentNeedingAttention(from: items)

        #expect(attention.map(\.title) == ["Needs Transcript", "Needs Labels"])
        #expect(attention.allSatisfy { DashboardRecordingAttention.needsAttention(status: $0.status) })
    }

    @Test func recentAttentionLimitIsAppliedAfterFilteringAndSorting() {
        let items = [
            item(title: "Old", date: Date(timeIntervalSinceReferenceDate: 1), status: .recordingSaved),
            item(title: "Middle", date: Date(timeIntervalSinceReferenceDate: 2), status: .transcribing),
            item(title: "New", date: Date(timeIntervalSinceReferenceDate: 3), status: .speakerLabeling),
        ]

        let attention = DashboardRecordingAttention.recentNeedingAttention(from: items, limit: 2)

        #expect(attention.map(\.title) == ["New", "Middle"])
    }

    @Test func manyRecordingsRemainBoundedSortedAndFiltered() {
        let items = (0..<2_000).map { index in
            item(
                title: "Recording \(index)",
                date: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                status: index.isMultiple(of: 4) ? .complete : .needsTranscription
            )
        }

        let attention = DashboardRecordingAttention.recentNeedingAttention(from: items, limit: 25)

        #expect(attention.count == 25)
        #expect(attention.allSatisfy { $0.status == .needsTranscription })
        #expect(attention.map(\.createdAt) == attention.map(\.createdAt).sorted(by: >))
        #expect(attention.first?.title == "Recording 1999")
    }

    @Test func modelWarningsCoverMissingDownloadingRepairingAndFailedStates() throws {
        #expect(DashboardModelStatus.warning(for: .ready, modelName: "Base English Default") == nil)

        let missing = try #require(DashboardModelStatus.warning(
            for: .notDownloaded,
            modelName: "Base English Default"
        ))
        #expect(missing.contains("not downloaded"))

        let downloading = try #require(DashboardModelStatus.warning(
            for: .downloading(progress: 0.2, message: "Downloading model files."),
            modelName: "Base English Default"
        ))
        #expect(downloading.contains("downloading"))

        let repairing = try #require(DashboardModelStatus.warning(
            for: .downloading(progress: 0.2, message: "Repairing model files."),
            modelName: "Base English Default"
        ))
        #expect(repairing.contains("being repaired"))

        let failed = try #require(DashboardModelStatus.warning(
            for: .failed("Network failed."),
            modelName: "Base English Default"
        ))
        #expect(failed.contains("Network failed."))
    }

    @Test func microphoneSummaryReportsUnavailableSavedInputWithoutInventingActiveHardware() {
        let summary = DashboardMicrophoneStatus.summary(
            selectedID: "missing-mic",
            visibleSelectedID: MicrophoneSelectionStore.automaticID,
            choices: [.automatic]
        )

        #expect(summary.value == "Automatic")
        #expect(summary.needsAttention)
        #expect(summary.detail.contains("Saved input unavailable"))
    }

    private func item(
        title: String,
        date: Date,
        status: RecordingStatus
    ) -> DashboardRecordingAttentionItem {
        DashboardRecordingAttentionItem(
            audioFileName: "\(title).caf",
            title: title,
            createdAt: date,
            status: status,
            durationText: "0:42",
            modelName: "Base English Default",
            speakerLabelText: "Speaker labels not available yet"
        )
    }
}
