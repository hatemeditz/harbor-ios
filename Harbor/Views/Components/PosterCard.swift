import SwiftUI

struct PosterCard: View {
    let meta: Meta
    var width: CGFloat = 122
    var showTitle = true

    private var posterHeight: CGFloat { width * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: meta.poster ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder.overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(Theme.textSecondary.opacity(0.5))
                        )
                    } else {
                        placeholder
                    }
                }
                .frame(width: width, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let rating = meta.imdbRating, !rating.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(rating)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(6)
                }
            }

            if showTitle {
                Text(meta.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                if let year = meta.releaseInfo, !year.isEmpty {
                    Text(year)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: width)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surfaceRaised)
            .frame(width: width, height: posterHeight)
    }
}

struct ContentUnavailableCompat: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Theme.textSecondary)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct RailRow: View {
    let rail: Rail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rail.title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(rail.metas.prefix(24))) { meta in
                        NavigationLink(value: meta) {
                            PosterCard(meta: meta)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
