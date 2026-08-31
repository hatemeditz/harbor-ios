import SwiftUI

struct DetailView: View {
    let nav: MetaNavigation

    @State private var fullMeta: Meta?
    @State private var isLoadingDetail = false
    @State private var isBookmarked = false
    @State private var selectedSeason: Int?
    @State private var didLogOpen = false
    @State private var moviePlaybackSessionId = UUID()

    @ObservedObject private var library = LibraryStore.shared

    private var displayMeta: Meta { fullMeta ?? nav.meta }

    private var episodeTargetMeta: Meta {
        let meta = displayMeta
        return Meta(
            id: meta.id,
            type: meta.type,
            name: meta.name,
            poster: meta.poster ?? nav.meta.poster,
            background: meta.background ?? nav.meta.background,
            logo: meta.logo,
            description: meta.description,
            releaseInfo: meta.releaseInfo,
            imdbRating: meta.imdbRating,
            genres: meta.genres,
            runtime: meta.runtime,
            country: meta.country,
            network: meta.network,
            videos: meta.videos
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
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
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: StreamTarget.self) { target in
            StreamsSheet(target: target)
        }
        .task { await load() }
        .onReceive(library.$items) { _ in
            refreshBookmarkFlag()
        }
        .onAppear {
            refreshBookmarkFlag()
            AnalyticsService.shared.setCurrentScreen(.detail, screenClass: "DetailView")
            if !didLogOpen {
                didLogOpen = true
                AnalyticsService.shared.log(
                    displayMeta.type == "series" ? .seriesOpened : .movieOpened,
                    parameters: AnalyticsService.shared.mediaParameters(
                        mediaType: displayMeta.type,
                        mediaId: displayMeta.id,
                        source: nav.source
                    )
                )
            }
        }
    }

    // MARK: - Data

    private func load() async {
        guard fullMeta == nil, !isLoadingDetail else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        if nav.meta.id.hasPrefix("tmdb:"), TMDBSettingsStore.shared.hasAPIKey {
            fullMeta = try? await TMDBClient.shared.detailMeta(
                apiKey: TMDBSettingsStore.shared.apiKey,
                meta: nav.meta
            )
        } else {
            fullMeta = try? await AddonClient.shared.metaDetail(
                base: nav.base,
                type: nav.meta.type,
                id: nav.meta.id
            )
        }
        refreshBookmarkFlag()
    }

    private func refreshBookmarkFlag() {
        isBookmarked = library.item(id: displayMeta.id)?.isBookmarked
            ?? library.item(id: nav.meta.id)?.isBookmarked
            ?? false
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
            .frame(height: 490)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.16), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [Theme.background.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(displayMeta.type == "series" ? "HARBOR SERIES" : "HARBOR MOVIE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2.2)
                    .foregroundColor(Theme.accent)

                if let logo = displayMeta.logo, !logo.isEmpty {
                    AsyncImage(url: URL(string: logo)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            detailTitle
                        }
                    }
                    .frame(maxWidth: 260, maxHeight: 92, alignment: .leading)
                } else {
                    detailTitle
                }

                HStack(spacing: 8) {
                    if let year = displayMeta.releaseInfo, !year.isEmpty {
                        Badge(text: year)
                    }
                    if let runtime = displayMeta.runtime, !runtime.isEmpty {
                        Badge(text: runtime)
                    }
                    if let rating = displayMeta.imdbRating, !rating.isEmpty {
                        HStack(spacing: 3) {
                            Text("IMDb")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 2))
                            Text(rating).font(.caption.weight(.semibold))
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

                if let description = displayMeta.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(3)
                        .frame(maxWidth: 340, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(height: 490)
        .ignoresSafeArea(edges: .top)
    }

    private var detailTitle: some View {
        Text(displayMeta.name)
            .font(.system(size: 36, weight: .bold, design: .serif))
            .tracking(-1)
            .foregroundColor(Theme.textPrimary)
            .lineLimit(3)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if displayMeta.type == "movie" {
                NavigationLink(value: StreamTarget(
                    metaId: displayMeta.id,
                    type: displayMeta.type,
                    title: displayMeta.name,
                    videoId: nil,
                    base: nav.base,
                    metaName: displayMeta.name,
                    poster: displayMeta.poster ?? nav.meta.poster,
                    background: displayMeta.background ?? nav.meta.background,
                    analyticsSource: nav.source,
                    playbackSessionId: moviePlaybackSessionId
                )) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HarborPrimaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsService.shared.log(
                        .playClicked,
                        parameters: AnalyticsService.shared.mediaParameters(
                            mediaType: displayMeta.type,
                            mediaId: displayMeta.id,
                            source: nav.source,
                            playbackSessionId: moviePlaybackSessionId
                        )
                    )
                    let usedSessionId = moviePlaybackSessionId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if moviePlaybackSessionId == usedSessionId {
                            moviePlaybackSessionId = UUID()
                        }
                    }
                })
            }

            Button(action: toggleBookmark) {
                Label(
                    isBookmarked ? "Saved" : "Watchlist",
                    systemImage: isBookmarked ? "checkmark" : "plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HarborSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var aboutSection: some View {
        if let description = fullMeta?.description ?? nav.meta.description,
           !description.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HarborSectionHeader(title: "About", subtitle: "Story and details")
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
            HarborSectionHeader(
                title: "Episodes",
                subtitle: "Season \(activeSeason)"
            )
                .padding(.horizontal, 16)

            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { season in
                            HarborFilterPill(
                                title: "Season \(season)",
                                selected: season == activeSeason
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSeason = season
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if isLoadingDetail && videos.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if videos.isEmpty {
                Text("Episode information is not available for this series.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(videos.filter { ($0.season ?? 1) == activeSeason }) { video in
                        EpisodeRow(
                            video: video,
                            meta: episodeTargetMeta,
                            watched: isEpisodeWatched(video),
                            base: nav.base,
                            source: nav.source
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
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
    let meta: Meta
    let watched: Bool
    let base: String?
    let source: HarborNavigationSource
    @State private var playbackSessionId = UUID()

    var body: some View {
        NavigationLink(
            value: StreamTarget(
                metaId: meta.id,
                type: "series",
                title: video.displayTitle,
                videoId: video.id,
                base: base,
                metaName: meta.name,
                poster: meta.poster,
                background: meta.background,
                analyticsSource: source,
                playbackSessionId: playbackSessionId,
                analyticsSeasonNumber: video.season,
                analyticsEpisodeNumber: video.episode
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            let parameters = AnalyticsService.shared.mediaParameters(
                mediaType: "series",
                mediaId: meta.id,
                source: source,
                playbackSessionId: playbackSessionId,
                seasonNumber: video.season,
                episodeNumber: video.episode
            )
            AnalyticsService.shared.log(.playClicked, parameters: parameters)
            let usedSessionId = playbackSessionId
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if playbackSessionId == usedSessionId {
                    playbackSessionId = UUID()
                }
            }
        })
    }
}
