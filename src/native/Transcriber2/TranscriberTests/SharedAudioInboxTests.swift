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

    @Test func isAudioFileFiltersSupportedExtensionsAndRejectsOddFormats() {
        for fileExtension in ["m4a", "mp3", "wav", "caf", "aiff", "aif", "aac", "flac"] {
            #expect(URL(fileURLWithPath: "/tmp/sample.\(fileExtension)").isAudioFile)
        }

        for filename in ["sample", "sample.m4a.tmp", ".hidden", "sample.wav/notes.txt"] {
            #expect(!URL(fileURLWithPath: "/tmp/\(filename)").isAudioFile)
        }
    }

    @Test func isAudioFileHandlesLargePlaceholderWithoutInspectingContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-import-sanity")
            .appendingPathExtension("m4a")
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 12 * 1_024 * 1_024)
        try handle.close()

        #expect(url.isAudioFile)
    }
}
