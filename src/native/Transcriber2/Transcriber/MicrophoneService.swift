import AVFoundation
import Combine
import Foundation

enum MicrophoneInputKind: String, CaseIterable, Sendable {
    case builtIn
    case bluetoothHeadset
    case named

    var label: String {
        switch self {
        case .builtIn:
            "Built-in"
        case .bluetoothHeadset:
            "Bluetooth/headset"
        case .named:
            "Named input"
        }
    }
}

struct MicrophoneInput: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: MicrophoneInputKind

    var pickerLabel: String {
        switch kind {
        case .builtIn:
            "Built-in - \(name)"
        case .bluetoothHeadset:
            "Bluetooth/headset - \(name)"
        case .named:
            name
        }
    }
}

struct MicrophoneChoice: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case automatic
        case input(MicrophoneInput)
    }

    let id: String
    let name: String
    let detail: String
    let kind: Kind

    static let automatic = MicrophoneChoice(
        id: MicrophoneSelectionStore.automaticID,
        name: "Automatic",
        detail: "Use the system default input.",
        kind: .automatic
    )
}

enum MicrophoneRouteResolution: Equatable, Sendable {
    case automatic
    case selected(MicrophoneInput)
    case fallbackToDefault(missingID: String)
    case platformRoutingUnavailable(MicrophoneInput)
}

struct MicrophoneRecordingRoute: Equatable, Sendable {
    static let systemDefaultInputName = "System default input"
    static let unavailableSelectionName = "the selected microphone"

    let selectedInput: MicrophoneInput?
    let activeInput: MicrophoneInput?
    let activeDisplayName: String
    let notice: String?

    var usedFallback: Bool {
        notice != nil
    }

    static func automatic() -> MicrophoneRecordingRoute {
        MicrophoneRecordingRoute(
            selectedInput: nil,
            activeInput: nil,
            activeDisplayName: systemDefaultInputName,
            notice: nil
        )
    }

    static func selected(_ input: MicrophoneInput) -> MicrophoneRecordingRoute {
        MicrophoneRecordingRoute(
            selectedInput: input,
            activeInput: input,
            activeDisplayName: input.name,
            notice: nil
        )
    }

    static func fallback(to input: MicrophoneInput?, missingName: String = unavailableSelectionName) -> MicrophoneRecordingRoute {
        let activeName = input?.name ?? systemDefaultInputName
        let noticeActiveName = input?.name ?? "the system default input"
        return MicrophoneRecordingRoute(
            selectedInput: nil,
            activeInput: input,
            activeDisplayName: activeName,
            notice: "Recording with \(noticeActiveName) because \(missingName) was unavailable."
        )
    }
}

struct MicrophoneSelectionStore: Sendable {
    static let automaticID = "automatic"
    static let selectionKey = "selectedMicrophoneInputID"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedID: String {
        defaults.string(forKey: Self.selectionKey) ?? Self.automaticID
    }

    func setSelectedID(_ id: String) {
        defaults.set(id, forKey: Self.selectionKey)
    }

    func selectedInput(in inputs: [MicrophoneInput]) -> MicrophoneInput? {
        Self.selectedInput(id: selectedID, in: inputs)
    }

    static func selectedInput(id: String?, in inputs: [MicrophoneInput]) -> MicrophoneInput? {
        guard let id, id != automaticID else { return nil }
        return inputs.first { $0.id == id }
    }

    static func choices(for inputs: [MicrophoneInput]) -> [MicrophoneChoice] {
        [.automatic] + inputs.map {
            MicrophoneChoice(
                id: $0.id,
                name: $0.pickerLabel,
                detail: $0.kind.label,
                kind: .input($0)
            )
        }
    }

    static func visibleSelectionID(for selectedID: String?, inputs: [MicrophoneInput]) -> String {
        guard let selectedID, selectedID != automaticID else { return automaticID }
        return selectedInput(id: selectedID, in: inputs) == nil ? automaticID : selectedID
    }

    static func resolvedRoute(for selectedID: String?, inputs: [MicrophoneInput]) -> MicrophoneRouteResolution {
        guard let selectedID, selectedID != automaticID else { return .automatic }
        guard let input = selectedInput(id: selectedID, in: inputs) else {
            return .fallbackToDefault(missingID: selectedID)
        }
        return .selected(input)
    }

    static func recordingRoute(for selectedID: String?, inputs: [MicrophoneInput]) -> MicrophoneRecordingRoute {
        guard let selectedID, selectedID != automaticID else {
            return .automatic()
        }
        guard let selected = selectedInput(id: selectedID, in: inputs) else {
            return .fallback(to: bestAvailableInput(in: inputs))
        }
        return .selected(selected)
    }

    static func bestAvailableInput(in inputs: [MicrophoneInput]) -> MicrophoneInput? {
        inputs.first
    }
}

@MainActor
final class MicrophoneService: ObservableObject {
    static let shared = MicrophoneService()

    @Published private(set) var inputs: [MicrophoneInput] = []

    private let store: MicrophoneSelectionStore
    private let discoverInputsProvider: @MainActor (_ configureAudioSession: Bool) -> [MicrophoneInput]
    private let routeRefreshRetryIntervals: [Duration]
    private var delayedRouteRefreshTask: Task<Void, Never>?
    private var captureActive = false
#if os(iOS)
    private var routeChangeCancellable: AnyCancellable?
#endif

    init(
        store: MicrophoneSelectionStore = MicrophoneSelectionStore(),
        discoverInputs: @escaping @MainActor (_ configureAudioSession: Bool) -> [MicrophoneInput] = {
            MicrophoneService.discoverInputs(configureAudioSession: $0)
        },
        routeRefreshRetryIntervals: [Duration] = MicrophoneService.defaultRouteRefreshRetryIntervals
    ) {
        self.store = store
        discoverInputsProvider = discoverInputs
        self.routeRefreshRetryIntervals = routeRefreshRetryIntervals
#if os(iOS)
        routeChangeCancellable = NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshInputsAfterRouteChange()
                }
            }
#endif
    }

    var selectedID: String {
        store.selectedID
    }

    var choices: [MicrophoneChoice] {
        MicrophoneSelectionStore.choices(for: inputs)
    }

    var visibleSelectedID: String {
        MicrophoneSelectionStore.visibleSelectionID(for: selectedID, inputs: inputs)
    }

    @discardableResult
    func refreshInputs(configureAudioSession: Bool = true) -> [MicrophoneInput] {
        inputs = discoverInputsProvider(configureAudioSession)
        return inputs
    }

    @discardableResult
    func refreshInputsAfterRouteChange() -> [MicrophoneInput] {
        scheduleRouteRefreshRetries()
        return refreshInputs(configureAudioSession: false)
    }

    func cancelPendingRouteRefresh() {
        delayedRouteRefreshTask?.cancel()
        delayedRouteRefreshTask = nil
    }

    func noteCaptureStarted() {
        captureActive = true
    }

    func noteCaptureStopped() {
        captureActive = false
    }

    func routeResolution() -> MicrophoneRouteResolution {
        MicrophoneSelectionStore.resolvedRoute(for: selectedID, inputs: inputs)
    }

    @discardableResult
    func applyPreferredInputForRecording() -> MicrophoneRecordingRoute {
        cancelPendingRouteRefresh()
        let inputs = refreshInputs(configureAudioSession: false)
        let selectedID = store.selectedID
        let route = MicrophoneSelectionStore.recordingRoute(for: selectedID, inputs: inputs)
        guard selectedID != MicrophoneSelectionStore.automaticID else {
#if os(iOS)
            try? AVAudioSession.sharedInstance().setPreferredInput(nil)
            return route
#else
            return Self.systemDefaultRecordingRoute()
#endif
        }

#if os(iOS)
        var appliedRoute = route
        let session = AVAudioSession.sharedInstance()
        guard let input = appliedRoute.activeInput else {
            try? session.setPreferredInput(nil)
            return appliedRoute
        }
        guard let port = session.availableInputs?.first(where: { $0.uid == input.id }) else {
            appliedRoute = MicrophoneRecordingRoute.fallback(to: nil)
            try? session.setPreferredInput(nil)
            return appliedRoute
        }
        do {
            try session.setPreferredInput(port)
        } catch {
            appliedRoute = MicrophoneRecordingRoute.fallback(to: nil)
            try? session.setPreferredInput(nil)
            return appliedRoute
        }
        return appliedRoute
#else
        if route.usedFallback {
            return .fallback(to: nil)
        }
        return Self.systemDefaultRecordingRoute()
#endif
    }

    @discardableResult
    func applySystemDefaultInputForRecording() -> MicrophoneRecordingRoute {
        cancelPendingRouteRefresh()
        _ = refreshInputs(configureAudioSession: false)
#if os(iOS)
        try? AVAudioSession.sharedInstance().setPreferredInput(nil)
        return .automatic()
#else
        return Self.systemDefaultRecordingRoute()
#endif
    }

    private static func discoverInputs(configureAudioSession: Bool) -> [MicrophoneInput] {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if configureAudioSession {
            try? session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try? session.setActive(true)
        }
        return (session.availableInputs ?? []).map(Self.input(from:))
#else
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map(Self.input(from:))
#endif
    }

    private static func systemDefaultRecordingRoute() -> MicrophoneRecordingRoute {
#if os(iOS)
        .automatic()
#else
        MicrophoneRecordingRoute(
            selectedInput: nil,
            activeInput: nil,
            activeDisplayName: AVCaptureDevice.default(for: .audio)?.localizedName
                ?? MicrophoneRecordingRoute.systemDefaultInputName,
            notice: nil
        )
#endif
    }

    private static var defaultRouteRefreshRetryIntervals: [Duration] {
#if os(iOS)
        [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)]
#else
        []
#endif
    }

    private func scheduleRouteRefreshRetries() {
        delayedRouteRefreshTask?.cancel()
        let intervals = routeRefreshRetryIntervals
        guard !intervals.isEmpty else { return }
        delayedRouteRefreshTask = Task { @MainActor [weak self] in
            for interval in intervals {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.refreshInputs(configureAudioSession: !self.captureActive)
            }
        }
    }

#if os(iOS)
    private static func input(from port: AVAudioSessionPortDescription) -> MicrophoneInput {
        MicrophoneInput(id: port.uid, name: port.portName, kind: kind(for: port.portType))
    }

    private static func kind(for port: AVAudioSession.Port) -> MicrophoneInputKind {
        switch port {
        case .builtInMic:
            .builtIn
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            .bluetoothHeadset
        default:
            .named
        }
    }
#else
    private static func input(from device: AVCaptureDevice) -> MicrophoneInput {
        let name = device.localizedName
        return MicrophoneInput(id: device.uniqueID, name: name, kind: kind(forName: name))
    }

    private static func kind(forName name: String) -> MicrophoneInputKind {
        let normalized = name.lowercased()
        if normalized.contains("built-in") || normalized.contains("macbook") {
            return .builtIn
        }
        if normalized.contains("bluetooth") || normalized.contains("headset") || normalized.contains("airpods") {
            return .bluetoothHeadset
        }
        return .named
    }
#endif
}
