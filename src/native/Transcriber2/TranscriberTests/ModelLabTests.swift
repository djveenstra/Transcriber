import Foundation
import Testing
@testable import Transcriber

struct ModelLabTests {
    @Test func iOSTabStructureMatchesPRDPrimaryTabs() {
        #expect(RootTab.iOSPrimaryTabs == [.dashboard, .library, .modelLab, .settings])
        #expect(!RootTab.iOSPrimaryTabs.contains { tab in
            String(describing: tab).localizedCaseInsensitiveContains("record")
        })
    }

    @Test func reportIncludesLoadAndTranscriptionTimeSeparately() {
        let result = ModelLabResult(
            modelID: "model-a",
            modelName: "Model A",
            loadTime: 1.25,
            transcriptionTime: 4.5,
            audioDuration: 9,
            modelSize: "2 KB",
            modelStatus: "Ready",
            modelStatusDetail: "Ready on this device.",
            transcript: "Hello from Model Lab.",
            error: nil
        )

        let report = ModelLabReport.report(for: [result])

        #expect(report.contains("Model load time:"))
        #expect(report.contains("Processing time:"))
        #expect(report.contains("Speed: 2.0"))
        #expect(report.contains("Model size: 2 KB"))
        #expect(report.contains("Model status: Ready"))
        #expect(report.contains("Failure status: None"))
        #expect(report.contains("Transcript:"))
        #expect(report.contains("Hello from Model Lab."))
    }

    @Test func reportIncludesFailureStatusAndTranscriptPlaceholder() {
        let result = ModelLabResult(
            modelID: "model-b",
            modelName: "Model B",
            loadTime: 0.4,
            transcriptionTime: 0,
            audioDuration: 9,
            modelSize: "Size not reported yet",
            modelStatus: "Missing or corrupt",
            modelStatusDetail: "Files are missing or incomplete.",
            transcript: "",
            error: "Model could not load."
        )

        let report = ModelLabReport.report(for: [result])

        #expect(report.contains("Failure status: Failed"))
        #expect(report.contains("Error: Model could not load."))
        #expect(report.contains("Speed: Not measured"))
    }

    @Test func diagnosticsSnapshotUsesModelRegistryStatusAndSizeFormatting() {
        let descriptor = ModelRegistry.descriptor(
            for: FinalTranscriptionModelChoice.choice(for: WhisperModelChoice.defaultID)
        )
        let file = ModelFileSnapshot(
            isPresent: true,
            hasCacheFootprint: true,
            wasPreviouslyDownloaded: true,
            sizeBytes: 2_048
        )

        let diagnostics = ModelLabModelDiagnostics.snapshot(
            for: descriptor,
            download: .idle,
            file: file,
            verification: .ready
        )

        #expect(diagnostics.status == ModelStatus.ready.label)
        #expect(diagnostics.statusDetail == ModelStatus.ready.detail)
        #expect(diagnostics.size == ModelRegistry.formattedSize(file.sizeBytes))
    }
}
