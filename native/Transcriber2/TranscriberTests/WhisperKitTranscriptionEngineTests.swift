import Testing
import WhisperKit
@testable import Transcriber

struct WhisperKitTranscriptionEngineTests {
    @Test func windowBoundsAreConsistent() {
        #expect(
            WhisperKitTranscriptionEngine.liveMaxSamples - WhisperKitTranscriptionEngine.liveDiscardSamples
                == WhisperKitTranscriptionEngine.liveRetainSamples
        )
    }

    @Test func discardCountIsZeroAtOrBelowMax() {
        #expect(WhisperKitTranscriptionEngine.discardCount(forSampleCount: WhisperKitTranscriptionEngine.liveMaxSamples) == 0)
        #expect(WhisperKitTranscriptionEngine.discardCount(forSampleCount: WhisperKitTranscriptionEngine.liveMaxSamples - 1) == 0)
    }

    @Test func discardCountFallsBackToRetainWindowOnceMaxIsExceeded() {
        let sampleCount = WhisperKitTranscriptionEngine.liveMaxSamples + 1
        let discarded = WhisperKitTranscriptionEngine.discardCount(forSampleCount: sampleCount)

        #expect(discarded == WhisperKitTranscriptionEngine.liveDiscardSamples)
        #expect(sampleCount - discarded == WhisperKitTranscriptionEngine.liveRetainSamples + 1)
    }

    @Test func offsetMsConvertsDiscardedSamplesToMilliseconds() {
        #expect(WhisperKitTranscriptionEngine.offsetMs(forDiscardedSampleCount: 0) == 0)
        #expect(WhisperKitTranscriptionEngine.offsetMs(forDiscardedSampleCount: WhisperKit.sampleRate) == 1_000)
        #expect(WhisperKitTranscriptionEngine.offsetMs(forDiscardedSampleCount: WhisperKit.sampleRate / 2) == 500)
    }
}
