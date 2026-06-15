import SwiftUI

/// App settings: model selection, storage info, about.
struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @AppStorage("whisperModel") private var whisperModel = "base"
    @AppStorage("clusteringThreshold") private var clusteringThreshold = 0.75

    var body: some View {
        NavigationStack {
            Form {
                Section("Transcription Model") {
                    Picker("Whisper Model", selection: $whisperModel) {
                        Text("Tiny (75 MB, fastest)").tag("tiny")
                        Text("Base (140 MB, balanced)").tag("base")
                    }
                    Text("Larger models are more accurate but use more memory and battery.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Speaker Detection") {
                    VStack(alignment: .leading) {
                        Text("Sensitivity: \(String(format: "%.0f%%", clusteringThreshold * 100))")
                        Slider(value: $clusteringThreshold, in: 0.5...0.95, step: 0.05)
                    }
                    Text("Higher = detects more speakers. Lower = merges similar voices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    HStack {
                        Text("Models")
                        Spacer()
                        Text(modelStorageSize)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Recordings")
                        Spacer()
                        Text(recordingStorageSize)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Powered by")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("whisper.cpp (OpenAI Whisper)")
                            .font(.caption)
                        Text("Silero VAD")
                            .font(.caption)
                        Text("WeSpeaker (speaker embeddings)")
                            .font(.caption)
                    }
                    Text("All processing happens on your device. No data is sent to any server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var modelStorageSize: String {
        // Approximate total model size
        "~350 MB"
    }

    private var recordingStorageSize: String {
        // Calculate actual recordings size
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docsPath = docs?.path else { return "0 MB" }

        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(atPath: docsPath) {
            while let file = enumerator.nextObject() as? String {
                if file.hasSuffix(".wav") {
                    let fullPath = (docsPath as NSString).appendingPathComponent(file)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }
        }

        let mb = totalSize / (1024 * 1024)
        if mb < 1 { return "< 1 MB" }
        return "\(mb) MB"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ModelManager.shared)
}
