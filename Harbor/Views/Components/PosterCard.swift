import SwiftUI

struct PosterCard: View {
    let meta: Meta
    var width: CGFloat = 122
    var showTitle = true
    var showTypeBadge = false

    private var posterHeight: CGFloat { width * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if showTypeBadge {
                        Text(meta.type == "series" ? "SHOW" : "MOVIE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.82), in: Capsule())
                            .padding(5)
                    }
                }

                if let rating = meta.imdbRating, !rating.isEmpty {
                    HStack(spacing: 3) {
                        Text("IMDb")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 2))
                        Text(rating)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.8), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(5)
                }
            }

            if showTitle {
                Text(meta.name)
                    .font(.caption.weight(.semibold))
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
        RoundedRectangle(cornerRadius: Theme.cardRadius)
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
    var source: HarborNavigationSource = .home

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HarborSectionHeader(title: rail.title, subtitle: rail.type.capitalized)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(rail.metas.prefix(24))) { meta in
                        NavigationLink(value: MetaNavigation(meta: meta, base: rail.base, source: source)) {
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

struct TopTenRailRow: View {
    let rail: Rail
    var source: HarborNavigationSource = .home

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSectionHeader(title: "Top 10", subtitle: rail.title)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(rail.metas.prefix(10).enumerated()), id: \.element.id) { index, meta in
                        NavigationLink(value: MetaNavigation(meta: meta, base: rail.base, source: source)) {
                            ZStack(alignment: .bottomLeading) {
                                Text("\(index + 1)")
                                    .font(.system(size: 116, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.background)
                                    .shadow(color: .white.opacity(0.38), radius: 1.2)
                                    .frame(width: 82, alignment: .leading)
                                    .offset(x: 2, y: 4)

                                PosterCard(meta: meta, width: 108, showTitle: false)
                                    .offset(x: 44)
                            }
                            .frame(width: 154, height: 168, alignment: .bottomLeading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
