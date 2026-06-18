import SwiftUI

/// Animated audio level visualization during recording.
/// Shows a series of bars that react to the current audio level.
struct WaveformView: View {
    let level: Float
    @State private var animatedLevels: [Float] = Array(repeating: 0.1, count: 30)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<animatedLevels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.red.opacity(0.7))
                    .frame(width: 4, height: max(4, CGFloat(animatedLevels[index]) * 50))
            }
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                // Shift levels to the left, add new level on the right
                animatedLevels.removeFirst()
                // Add some randomness for visual interest
                let randomizedLevel = newLevel * Float.random(in: 0.7...1.3)
                animatedLevels.append(min(1.0, randomizedLevel))
            }
        }
    }
}

#Preview {
    WaveformView(level: 0.5)
        .frame(height: 60)
        .padding()
}
