import SwiftUI

struct DetailView: View {
    let nav: MetaNavigation

    @State private var fullMeta: Meta?
    @State private var isLoadingDetail = false
    @State private var isBookmarked = false
    @State private var selectedSeason: Int?

    @ObservedObject private var library = LibraryStore.shared

    private var displayMeta: Meta { fullMeta ?? nav.meta }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                titleBlock
                actionRow
                aboutSection
                if displayMeta.type == "series" {
                    episodesSection
                }
                Color.clear.frame(height: 40)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: StreamTarget.self) { target in
            StreamsSheet(target: target)
        }
        .task { await load() }
        .onReceive(library.$items) { _ in
            refreshBookmarkFlag()
        }
        .onAppear { refreshBookmarkFlag() }
    }

    // MARK: - Data

    private func load() async {
        guard fullMeta == nil, !isLoadingDetail else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        fullMeta = try? await AddonClient.shared.metaDetail(
            base: nav.base,
            type: nav.meta.type,
            id: nav.meta.id
        )
        refreshBookmarkFlag()
    }

    private func refreshBookmarkFlag() {
        isBookmarked = library.item(id: nav.meta.id)?.isInWatchlist ?? false
    }

    private func toggleBookmark() {
        guard let authKey = AuthStore.shared.authKey else {
            return
        }
        Task {
            await LibraryStore.shared.toggleBookmark(authKey: authKey, meta: displayMeta)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: (fullMeta?.background ?? nav.meta.background) ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Theme.surfaceRaised, Theme.background],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .frame(height: 240)
            .clipped()

            LinearGradient(
                colors: [.clear, Theme.background.opacity(0.95)],
                startPoint: .center, endPoint: .bottom
            )
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterCard(
                meta: Meta(
                    id: displayMeta.id,
                    type: displayMeta.type,
                    name: displayMeta.name,
                    poster: displayMeta.poster ?? nav.meta.poster,
                    background: nil, logo: nil, description: nil,
                    releaseInfo: nil, imdbRating: nil, genres: nil,
                    runtime: nil, country: nil, network: nil, videos: nil
                ),
                width: 96,
                showTitle: false
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(displayMeta.name)
                    .font(.title2.bold())
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if let year = displayMeta.releaseInfo, !year.isEmpty {
                        Badge(text: year)
                    }
                    if let runtime = displayMeta.runtime, !runtime.isEmpty {
                        Badge(text: runtime)
                    }
                    if let rating = displayMeta.imdbRating, !rating.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                            Text(rating)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceRaised, in: Capsule())
                    }
                }

                if let genres = displayMeta.genres, !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, -56)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: toggleBookmark) {
                Label(
                    isBookmarked ? "In Watchlist" : "Watchlist",
                    systemImage: isBookmarked ? "checkmark.circle.fill" : "plus.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(isBookmarked ? Theme.accent : Theme.textPrimary)
            }
            .buttonStyle(.plain)

            if displayMeta.type == "movie" {
                NavigationLink(value: StreamTarget(
                    metaId: displayMeta.id,
                    type: displayMeta.type,
                    title: displayMeta.name,
                    videoId: nil,
                    base: nav.base
                )) {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var aboutSection: some View {
        if let description = fullMeta?.description ?? nav.meta.description,
           !description.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
    }

    // MARK: - Episodes

    private var videos: [MetaVideo] {
        (fullMeta?.videos ?? nav.meta.videos ?? [])
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    private var seasons: [Int] {
        Array(Set(videos.compactMap(\.season))).sorted()
    }

    private var activeSeason: Int {
        selectedSeason ?? seasons.first ?? 1
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Episodes")
                .font(.headline)
                .padding(.horizontal, 16)

            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { season in
                            Button {
                                selectedSeason = season
                            } label: {
                                Text("S\(season)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        season == activeSeason ? Theme.accent : Theme.surfaceRaised,
                                        in: Capsule()
                                    )
                                    .foregroundColor(season == activeSeason ? .white : Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(videos.filter { ($0.season ?? 1) == activeSeason }) { video in
                    EpisodeRow(
                        video: video,
                        metaId: displayMeta.id,
                        watched: isEpisodeWatched(video),
                        base: nav.base
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 18)
    }

    private func isEpisodeWatched(_ video: MetaVideo) -> Bool {
        guard let item = library.item(id: nav.meta.id),
              let state = item.state else { return false }
        if (state.flaggedWatched ?? 0) > 0,
           let se = item.episodeFromVideoId,
           video.season == se.season, video.episode == se.episode {
            return true
        }
        return false
    }
}

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.surfaceRaised, in: Capsule())
            .foregroundColor(Theme.textPrimary)
    }
}

struct EpisodeRow: View {
    let video: MetaVideo
    let metaId: String
    let watched: Bool
    let base: String?

    var body: some View {
        NavigationLink(
            value: StreamTarget(
                metaId: metaId,
                type: "series",
                title: video.displayTitle,
                videoId: video.id,
                base: base
            )
        ) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    AsyncImage(url: URL(string: video.thumbnail ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Theme.surfaceRaised
                        }
                    }
                    .frame(width: 110, height: 62)
                    .clipped()

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.85))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if watched {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.accent)
                        }
                        Text(video.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundColor(Theme.textPrimary)
                    }
                    if let overview = video.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
