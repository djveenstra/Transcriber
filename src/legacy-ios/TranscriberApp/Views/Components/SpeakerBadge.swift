import SwiftUI

/// A colored badge showing a speaker's name.
/// Each speaker gets a distinct color for easy visual identification.
struct SpeakerBadge: View {
    let name: String
    let colorIndex: Int

    /// Predefined speaker colors (supports up to 8 speakers)
    private static let colors: [Color] = [
        .blue, .green, .orange, .purple,
        .pink, .teal, .indigo, .mint,
    ]

    private var color: Color {
        Self.colors[colorIndex % Self.colors.count]
    }

    var body: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 10) {
        SpeakerBadge(name: "Speaker 1", colorIndex: 0)
        SpeakerBadge(name: "Speaker 2", colorIndex: 1)
        SpeakerBadge(name: "Speaker 3", colorIndex: 2)
        SpeakerBadge(name: "Speaker 4", colorIndex: 3)
    }
}
