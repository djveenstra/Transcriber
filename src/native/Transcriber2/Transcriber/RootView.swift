import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            RecordingView()
                .tabItem { Label("Record", systemImage: "mic.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "waveform") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .background(Theme.background)
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
