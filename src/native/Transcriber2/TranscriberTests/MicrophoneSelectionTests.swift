import Foundation
import Testing
@testable import Transcriber

@Suite(.serialized)
struct MicrophoneSelectionTests {
    @Test func defaultSelectionIsAutomatic() throws {
        let suiteName = "MicrophoneSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MicrophoneSelectionStore(defaults: defaults)

        #expect(store.selectedID == MicrophoneSelectionStore.automaticID)
        #expect(store.selectedInput(in: sampleInputs) == nil)
    }

    @Test func selectedMicrophonePersistsInDefaults() throws {
        let suiteName = "MicrophoneSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MicrophoneSelectionStore(defaults: defaults)
        store.setSelectedID("bluetooth-airpods")

        #expect(defaults.string(forKey: MicrophoneSelectionStore.selectionKey) == "bluetooth-airpods")
        #expect(store.selectedID == "bluetooth-airpods")
    }

    @Test func choicesPutAutomaticFirstAndRepresentInputKinds() {
        let choices = MicrophoneSelectionStore.choices(for: sampleInputs)

        #expect(choices.first == .automatic)
        #expect(choices.map(\.id) == [
            MicrophoneSelectionStore.automaticID,
            "built-in",
            "bluetooth-airpods",
            "usb-interface",
        ])
        #expect(choices[1].name == "Built-in - iPhone Microphone")
        #expect(choices[2].name == "Bluetooth/headset - Daniel's AirPods")
        #expect(choices[3].name == "USB Audio Interface")
    }

    @Test func selectionResolutionReturnsKnownInputAndFallsBackForAutomaticOrUnknown() {
        #expect(MicrophoneSelectionStore.selectedInput(id: MicrophoneSelectionStore.automaticID, in: sampleInputs) == nil)
        #expect(MicrophoneSelectionStore.selectedInput(id: nil, in: sampleInputs) == nil)
        #expect(MicrophoneSelectionStore.selectedInput(id: "missing", in: sampleInputs) == nil)
        #expect(MicrophoneSelectionStore.selectedInput(id: "built-in", in: sampleInputs) == sampleInputs[0])
    }

    @Test func routeResolutionKeepsAutomaticAndUnknownIDsOnDefaultPath() {
        #expect(MicrophoneSelectionStore.resolvedRoute(for: nil, inputs: sampleInputs) == .automatic)
        #expect(MicrophoneSelectionStore.resolvedRoute(for: MicrophoneSelectionStore.automaticID, inputs: sampleInputs) == .automatic)
        #expect(MicrophoneSelectionStore.resolvedRoute(for: "missing", inputs: sampleInputs) == .fallbackToDefault(missingID: "missing"))
        #expect(MicrophoneSelectionStore.resolvedRoute(for: "bluetooth-airpods", inputs: sampleInputs) == .selected(sampleInputs[1]))
    }

    @Test func recordingRouteUsesSelectedInputWhenPresent() {
        let route = MicrophoneSelectionStore.recordingRoute(for: "bluetooth-airpods", inputs: sampleInputs)

        #expect(route.selectedInput == sampleInputs[1])
        #expect(route.activeInput == sampleInputs[1])
        #expect(route.activeDisplayName == "Daniel's AirPods")
        #expect(route.notice == nil)
        #expect(route.usedFallback == false)
    }

    @Test func recordingRouteFallsBackToBestAvailableInputWhenSelectedIsMissing() {
        let route = MicrophoneSelectionStore.recordingRoute(for: "missing", inputs: sampleInputs)

        #expect(route.selectedInput == nil)
        #expect(route.activeInput == sampleInputs[0])
        #expect(route.activeDisplayName == "iPhone Microphone")
        #expect(route.notice == "Recording with iPhone Microphone because the selected microphone was unavailable.")
        #expect(route.usedFallback == true)
    }

    @Test func recordingRouteUsesSystemDefaultWhenAutomaticOrNoInputsAvailable() {
        let automatic = MicrophoneSelectionStore.recordingRoute(
            for: MicrophoneSelectionStore.automaticID,
            inputs: sampleInputs
        )
        let noInputs = MicrophoneSelectionStore.recordingRoute(for: "missing", inputs: [])

        #expect(automatic.selectedInput == nil)
        #expect(automatic.activeDisplayName == MicrophoneRecordingRoute.systemDefaultInputName)
        #expect(automatic.notice == nil)
        #expect(noInputs.selectedInput == nil)
        #expect(noInputs.activeInput == nil)
        #expect(noInputs.activeDisplayName == MicrophoneRecordingRoute.systemDefaultInputName)
        #expect(noInputs.notice == "Recording with the system default input because the selected microphone was unavailable.")
    }

    private var sampleInputs: [MicrophoneInput] {
        [
            MicrophoneInput(id: "built-in", name: "iPhone Microphone", kind: .builtIn),
            MicrophoneInput(id: "bluetooth-airpods", name: "Daniel's AirPods", kind: .bluetoothHeadset),
            MicrophoneInput(id: "usb-interface", name: "USB Audio Interface", kind: .named),
        ]
    }
}
