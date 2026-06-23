import Foundation
import Testing
@testable import Transcriber

struct ProcessingDiagnosticsTests {
    @Test func formattingCoversLoadTranscriptionAndRealtimeSpeed() {
        #expect(DiagnosticsMetricFormatter.formatSeconds(1.24) == "1.2 seconds")
        #expect(DiagnosticsMetricFormatter.formatSeconds(nil) == "Not measured")
        #expect(DiagnosticsMetricFormatter.speedDescription(audioDuration: 9, processingTime: 4.5) == "2.0× real time")
        #expect(DiagnosticsMetricFormatter.speedDescription(audioDuration: 9, processingTime: 0) == "Not measured")
    }

    @Test func presentationIncludesRequiredDiagnosticRowsAndStaysCollapsedByDefault() {
        let diagnostics = ProcessingDiagnostics(
            audioFileName: "sample.caf",
            finalTranscriptionModelID: "model-a",
            finalTranscriptionModelName: "Model A",
            modelLoadTime: 1.2,
            transcriptionTime: 4.5,
            audioDuration: 9,
            diarizationTime: 0.8,
            transcriptionFallbackUsed: true,
            diarizationFallbackUsed: false,
            speakerLabelStatus: .complete,
            failureMessage: nil,
            diarizationCurrentStage: .process,
            diarizationCurrentStageElapsed: 0.4,
            diarizationTimedOutStage: .modelLoad,
            diarizationTimedOutAfter: 300,
            diarizationStageTimings: [
                DiarizationStageTiming(stage: .audioInspection, duration: 0.1),
                DiarizationStageTiming(stage: .conversionPrep, duration: 0.2),
            ]
        )

        let presentation = DiagnosticsPresentation.make(for: diagnostics)
        let rows = Dictionary(uniqueKeysWithValues: presentation.rows.map { ($0.label, $0.value) })

        #expect(DiagnosticsPresentation.isExpandedByDefault == false)
        #expect(rows["Model"] == "Model A")
        #expect(rows["Model load"] == "1.2 seconds")
        #expect(rows["Transcription"] == "4.5 seconds")
        #expect(rows["Audio length"] == "9.0 seconds")
        #expect(rows["Speed"] == "2.0× real time")
        #expect(rows["Speaker labeling"] == "0.8 seconds")
        #expect(rows["Diarization stage"] == "Sortformer processing · 0.4 seconds")
        #expect(rows["Timed out during"] == "Model/resource loading · 300.0 seconds")
        #expect(rows["Audio inspection"] == "0.1 seconds")
        #expect(rows["Audio conversion/prep"] == "0.2 seconds")
        #expect(rows["Transcription fallback"] == "Yes")
        #expect(rows["Diarization fallback"] == "No")
        #expect(rows["Speaker labels"] == "Complete")
    }
}

@MainActor
struct RecordingDiagnosticsTests {
    @Test func recordingSummaryUsesDerivedFieldsWithoutInventingTimings() {
        let recording = Recording(
            title: "Saved Recording",
            durationSeconds: 42,
            audioFileName: "saved.caf",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 1_000, speaker: "SPEAKER_00", text: "Hello")
            ],
            finalTranscriptionModelID: "openai_whisper-base.en"
        )

        let diagnostics = ProcessingDiagnostics.derivedSummary(for: recording, activity: nil)

        #expect(diagnostics.audioDuration == 42)
        #expect(diagnostics.modelLoadTime == nil)
        #expect(diagnostics.transcriptionTime == nil)
        #expect(diagnostics.speakerLabelStatus == .complete)
        #expect(!diagnostics.isSessionOnly)
    }
}
