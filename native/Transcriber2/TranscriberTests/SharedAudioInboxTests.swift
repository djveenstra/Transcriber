import Foundation
import Testing
@testable import Transcriber

struct SharedAudioInboxTests {
    @Test func nameRecoversTitleFromUUIDPrefixedFilename() {
        let uuid = UUID().uuidString
        let url = URL(fileURLWithPath: "/tmp/\(uuid)__My Recording.m4a")

        #expect(SharedAudioItem(url: url).name == "My Recording")
    }

    @Test func nameFallsBackToFilenameWithoutUUIDPrefix() {
        let url = URL(fileURLWithPath: "/tmp/Some Recording.m4a")

        #expect(SharedAudioItem(url: url).name == "Some Recording")
    }

    @Test func nameFallsBackWhenPrefixIsNotAValidUUID() {
        let url = URL(fileURLWithPath: "/tmp/not-a-uuid__My Recording.m4a")

        #expect(SharedAudioItem(url: url).name == "not-a-uuid__My Recording")
    }

    @Test func isAudioFileRecognizesKnownExtensionsCaseInsensitively() {
        #expect(URL(fileURLWithPath: "/tmp/a.M4A").isAudioFile)
        #expect(URL(fileURLWithPath: "/tmp/a.wav").isAudioFile)
        #expect(URL(fileURLWithPath: "/tmp/a.flac").isAudioFile)
        #expect(!URL(fileURLWithPath: "/tmp/a.txt").isAudioFile)
    }
}
