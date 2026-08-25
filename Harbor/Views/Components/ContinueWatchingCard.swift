import SwiftUI

struct ContinueWatchingCard: View {
    let item: LibraryItem
    var width: CGFloat = 208

    private var height: CGFloat { width * 9 / 16 }
    private var ratio: Double { item.progressRatio }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: (item.background ?? item.poster) ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.surfaceRaised
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let se = item.episodeFromVideoId {
                        Text("S\(se.season) · E\(se.episode)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    } else if let type = item.type as String?, type == "series" {
                        Text("Series")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(Theme.accent)
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(width: width - 12, height: 3)
                .padding(.bottom, 4)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(resumeLabel)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(width: width)
    }

    private var resumeLabel: String {
        guard let state = item.state else { return "" }
        let offset = state.timeOffset ?? 0
        guard offset > 0 else { return "Start over" }
        let minutes = Int(offset / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m watched" : "\(mins)m watched"
    }
}
