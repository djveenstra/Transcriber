import Combine
import Foundation

@MainActor
protocol MicrophoneTestRecording: AnyObject {
    var level: Float { get }
    var levelUpdates: AnyPublisher<Float, Never> { get }

    func requestPermission() async -> Bool
    func startMetering() throws
    @discardableResult func stop() -> (any Error)?
}

extension AudioRecorder: MicrophoneTestRecording {}

@MainActor
final class MicrophoneTestSession: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case testing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0

    private let recorder: any MicrophoneTestRecording
    private var levelSubscription: AnyCancellable?
    private var startGeneration = 0

    init(recorder: any MicrophoneTestRecording = AudioRecorder()) {
        self.recorder = recorder
        levelSubscription = recorder.levelUpdates.sink { [weak self] level in
            self?.level = AudioLevelMeter.normalizedLevel(level)
        }
    }

    var isTesting: Bool {
        if case .testing = state { return true }
        return false
    }

    var isBusy: Bool {
        if case .starting = state { return true }
        return false
    }

    func start() async {
        guard !isTesting, !isBusy else { return }
        startGeneration += 1
        let generation = startGeneration
        state = .starting

        let granted = await recorder.requestPermission()
        guard generation == startGeneration, state == .starting else { return }
        guard granted else {
            level = 0
            state = .failed("Microphone permission was denied.")
            return
        }

        do {
            try recorder.startMetering()
            level = AudioLevelMeter.normalizedLevel(recorder.level)
            state = .testing
        } catch {
            recorder.stop()
            level = 0
            state = .failed("Could not start the microphone test.")
        }
    }

    func stop() {
        startGeneration += 1
        guard state != .idle else { return }
        recorder.stop()
        level = 0
        state = .idle
    }
}
