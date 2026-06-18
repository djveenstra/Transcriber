import Combine
import Foundation
import Testing
@testable import Transcriber

@MainActor
@Suite(.serialized)
struct MicrophoneTestSessionTests {
    @Test func normalizedRMSClampsToMeterRange() {
        #expect(AudioLevelMeter.normalizedRMS([]) == 0)
        #expect(AudioLevelMeter.normalizedRMS([0.0625]) == 0.5)
        #expect(AudioLevelMeter.normalizedRMS([-0.0625, 0.0625]) == 0.5)
        #expect(AudioLevelMeter.normalizedRMS([0.25]) == 1)
        #expect(AudioLevelMeter.normalizedLevel(.nan) == 0)
    }

    @Test func startAndStopDriveMeteringStateWithoutRecordingURL() async {
        let recorder = FakeMicrophoneTestRecorder()
        let session = MicrophoneTestSession(recorder: recorder)

        await session.start()
        #expect(session.state == .testing)
        #expect(recorder.startMeteringCallCount == 1)
        #expect(recorder.stopCallCount == 0)
        #expect(recorder.recordingURLs.isEmpty)

        recorder.publish(level: 0.42)
        #expect(session.level == 0.42)

        session.stop()
        #expect(session.state == .idle)
        #expect(session.level == 0)
        #expect(recorder.stopCallCount == 1)
        #expect(recorder.recordingURLs.isEmpty)
    }

    @Test func deniedPermissionFailsWithoutStartingCapture() async {
        let recorder = FakeMicrophoneTestRecorder()
        recorder.permissionResult = false
        let session = MicrophoneTestSession(recorder: recorder)

        await session.start()

        #expect(session.state == .failed("Microphone permission was denied."))
        #expect(recorder.startMeteringCallCount == 0)
        #expect(recorder.stopCallCount == 0)
        #expect(recorder.recordingURLs.isEmpty)
    }

    @Test func stopDuringPendingStartPreventsLateCapture() async {
        let recorder = FakeMicrophoneTestRecorder()
        recorder.permissionResult = nil
        let session = MicrophoneTestSession(recorder: recorder)

        let startTask = Task { await session.start() }
        while recorder.pendingPermissionContinuation == nil {
            await Task.yield()
        }

        #expect(session.state == .starting)
        session.stop()
        #expect(session.state == .idle)

        recorder.resumePermission(true)
        await startTask.value

        #expect(session.state == .idle)
        #expect(recorder.startMeteringCallCount == 0)
        #expect(recorder.stopCallCount == 1)
        #expect(recorder.recordingURLs.isEmpty)
    }

    @Test func startFailureStopsPartialCaptureAndReturnsToFailedState() async {
        let recorder = FakeMicrophoneTestRecorder()
        recorder.startError = TestMicError.startFailed
        let session = MicrophoneTestSession(recorder: recorder)

        await session.start()

        #expect(session.state == .failed("Could not start the microphone test."))
        #expect(session.level == 0)
        #expect(recorder.startMeteringCallCount == 1)
        #expect(recorder.stopCallCount == 1)
        #expect(recorder.recordingURLs.isEmpty)
    }
}

@MainActor
private final class FakeMicrophoneTestRecorder: MicrophoneTestRecording {
    var level: Float = 0
    var levelUpdates: AnyPublisher<Float, Never> { subject.eraseToAnyPublisher() }
    var permissionResult: Bool? = true
    var startError: (any Error)?
    var startMeteringCallCount = 0
    var stopCallCount = 0
    var recordingURLs: [URL] = []
    var pendingPermissionContinuation: CheckedContinuation<Bool, Never>?

    private let subject = PassthroughSubject<Float, Never>()

    func requestPermission() async -> Bool {
        if let permissionResult {
            return permissionResult
        }
        return await withCheckedContinuation { continuation in
            pendingPermissionContinuation = continuation
        }
    }

    func startMetering() throws {
        startMeteringCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() -> (any Error)? {
        stopCallCount += 1
        return nil
    }

    func publish(level: Float) {
        self.level = level
        subject.send(level)
    }

    func resumePermission(_ granted: Bool) {
        let continuation = pendingPermissionContinuation
        pendingPermissionContinuation = nil
        continuation?.resume(returning: granted)
    }
}

private enum TestMicError: Error {
    case startFailed
}
