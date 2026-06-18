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

    static func resolvedRoute(for selectedID: String?, inputs: [MicrophoneInput]) -> MicrophoneRouteResolution {
        guard let selectedID, selectedID != automaticID else { return .automatic }
        guard let input = selectedInput(id: selectedID, in: inputs) else {
            return .fallbackToDefault(missingID: selectedID)
        }
        return .selected(input)
    }
}

@MainActor
final class MicrophoneService: ObservableObject {
    static let shared = MicrophoneService()

    @Published private(set) var inputs: [MicrophoneInput] = []

    private let store: MicrophoneSelectionStore

    init(store: MicrophoneSelectionStore = MicrophoneSelectionStore()) {
        self.store = store
    }

    var selectedID: String {
        store.selectedID
    }

    var choices: [MicrophoneChoice] {
        MicrophoneSelectionStore.choices(for: inputs)
    }

    @discardableResult
    func refreshInputs() -> [MicrophoneInput] {
        inputs = Self.discoverInputs()
        return inputs
    }

    func routeResolution() -> MicrophoneRouteResolution {
        MicrophoneSelectionStore.resolvedRoute(for: selectedID, inputs: inputs)
    }

    @discardableResult
    func applyPreferredInputForRecording() -> MicrophoneRouteResolution {
        let inputs = refreshInputs()
        let selectedID = store.selectedID
        guard selectedID != MicrophoneSelectionStore.automaticID else {
#if os(iOS)
            try? AVAudioSession.sharedInstance().setPreferredInput(nil)
#endif
            return .automatic
        }

        guard let input = MicrophoneSelectionStore.selectedInput(id: selectedID, in: inputs) else {
            return .fallbackToDefault(missingID: selectedID)
        }

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        guard let port = session.availableInputs?.first(where: { $0.uid == input.id }) else {
            return .fallbackToDefault(missingID: selectedID)
        }
        do {
            try session.setPreferredInput(port)
        } catch {
            return .fallbackToDefault(missingID: selectedID)
        }
        return .selected(input)
#else
        return .platformRoutingUnavailable(input)
#endif
    }

    private static func discoverInputs() -> [MicrophoneInput] {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
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
