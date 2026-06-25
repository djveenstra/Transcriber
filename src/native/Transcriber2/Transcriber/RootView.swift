import SwiftUI

struct RootView: View {
    @State private var selectedTab: RootTab = .dashboard
    @State private var recordingFlow: RecordingFlow?

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                onRecord: {
                    recordingFlow = .record(UUID())
                },
                onImport: {
                    recordingFlow = .importAudio(UUID())
                },
                onModelLab: modelLabAction
            )
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(RootTab.dashboard)
            LibraryView()
                .tabItem { Label("Library", systemImage: "waveform") }
                .tag(RootTab.library)
            NavigationStack {
                ModelLabView()
            }
                .tabItem { Label("Model Lab", systemImage: "speedometer") }
                .tag(RootTab.modelLab)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.background)
        .sheet(item: $recordingFlow) { flow in
            RecordingView(
                startRequestID: flow.startRequestID,
                importRequestID: flow.importRequestID
            )
        }
    }

    private var modelLabAction: (() -> Void)? {
        { selectedTab = .modelLab }
    }
}

enum RootTab: Hashable, Sendable {
    case dashboard
    case library
    case modelLab
    case settings

    static let iOSPrimaryTabs: [RootTab] = [.dashboard, .library, .modelLab, .settings]
    static let macPrimaryTabs: [RootTab] = [.dashboard, .library, .modelLab, .settings]
}

private enum RecordingFlow: Identifiable {
    case record(UUID)
    case importAudio(UUID)

    var id: UUID {
        switch self {
        case let .record(id), let .importAudio(id):
            id
        }
    }

    var startRequestID: UUID? {
        if case let .record(id) = self { id } else { nil }
    }

    var importRequestID: UUID? {
        if case let .importAudio(id) = self { id } else { nil }
    }
}

enum Theme {
    static let background = Color(red: 0.005, green: 0.012, blue: 0.035)
    static let surface = Color(red: 0.018, green: 0.045, blue: 0.105)
    static let border = Color(red: 0.10, green: 0.20, blue: 0.38)
    static let accent = Color(red: 0.18, green: 0.48, blue: 1.00)
    static let muted = Color(red: 0.61, green: 0.69, blue: 0.82)
    static let speakerColors: [Color] = [.purple, .orange, .pink, .cyan, .blue, .yellow, .red, .indigo]
}
