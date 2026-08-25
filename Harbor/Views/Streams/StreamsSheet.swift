import SwiftUI

/// Placeholder — the ranked stream engine lands in M6.
struct StreamsSheet: View {
    let target: StreamTarget

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "water.waves")
                .font(.system(size: 40))
                .foregroundColor(Theme.accent)
            Text("Stream Engine")
                .font(.title3.bold())
            Text("Ranked streams arrive in Milestone 6.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
