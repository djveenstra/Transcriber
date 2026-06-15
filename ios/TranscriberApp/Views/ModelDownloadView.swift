import SwiftUI

/// Shown on first launch while models are being downloaded.
/// Shows progress and explains what's happening.
struct ModelDownloadView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var isDownloading = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App icon / branding
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Transcriber")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Record and transcribe memos with\nspeaker identification — 100% on-device")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Download section
            if isDownloading {
                downloadProgressView
            } else if let error = modelManager.errorMessage {
                errorView(error)
            } else {
                setupPromptView
            }

            Spacer()
        }
        .padding(30)
    }

    private var setupPromptView: some View {
        VStack(spacing: 16) {
            Text("First-time setup requires downloading AI models (~350 MB).\nAfter this, the app works completely offline.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                isDownloading = true
                Task {
                    await modelManager.downloadMissingModels()
                }
            } label: {
                Label("Download Models", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var downloadProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: modelManager.downloadProgress) {
                Text(modelManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(Int(modelManager.downloadProgress * 100))%")
                .font(.title2)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)

            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                isDownloading = true
                Task {
                    await modelManager.downloadMissingModels()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ModelDownloadView()
        .environmentObject(ModelManager.shared)
}
