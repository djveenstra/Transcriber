import SwiftUI

struct RootView: View {
    @State private var selectedTab: RootTab = .dashboard
    @State private var recordingStartRequestID: UUID?
    @State private var recordingImportRequestID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                onRecord: {
                    recordingStartRequestID = UUID()
                    selectedTab = .record
                },
                onImport: {
                    recordingImportRequestID = UUID()
                    selectedTab = .record
                }
            )
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(RootTab.dashboard)
            RecordingView(
                startRequestID: recordingStartRequestID,
                importRequestID: recordingImportRequestID
            )
                .tabItem { Label("Record", systemImage: "mic.fill") }
                .tag(RootTab.record)
            LibraryView()
                .tabItem { Label("Library", systemImage: "waveform") }
                .tag(RootTab.library)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.background)
    }
}

private enum RootTab: Hashable {
    case dashboard
    case record
    case library
    case settings
}

enum Theme {
    static let background = Color(red: 0.005, green: 0.012, blue: 0.035)
    static let surface = Color(red: 0.018, green: 0.045, blue: 0.105)
    static let border = Color(red: 0.10, green: 0.20, blue: 0.38)
    static let accent = Color(red: 0.18, green: 0.48, blue: 1.00)
    static let muted = Color(red: 0.61, green: 0.69, blue: 0.82)
    static let speakerColors: [Color] = [.purple, .orange, .pink, .cyan, .blue, .yellow, .red, .indigo]
}
