import SwiftUI
import UIKit

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var rails: [Rail] = []
    @Published var isLoading = false

    private var loadedOnce = false

    func loadIfNeeded() async {
        guard !loadedOnce, !isLoading else { return }
        await load()
    }

    func load(forceAddonRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            loadedOnce = true
        }

        let addons = await CatalogStore.shared.gatherAddons(
            authKey: AuthStore.shared.authKey,
            force: forceAddonRefresh
        )
        let built = CatalogStore.shared.buildRails(from: addons, maxRails: 10)
        guard !built.isEmpty else { return }

        var pages = Array(repeating: [Meta](), count: built.count)
        var publishedInitialRail = false
        await withTaskGroup(of: (Int, [Meta]).self) { group in
            for (index, rail) in built.enumerated() {
                group.addTask {
                    let metas = try? await AddonClient.shared.catalogPage(
                        base: rail.base,
                        type: rail.type,
                        id: rail.catalogId,
                        extras: rail.extras ?? [:]
                    )
                    return (index, metas ?? [])
                }
            }
            for await (index, metas) in group {
                guard index < pages.count else { continue }
                pages[index] = Array(metas.prefix(24))
                if rails.isEmpty, !publishedInitialRail,
                   built[index].base == AddonClient.cinemetaBase,
                   !pages[index].isEmpty {
                    var firstRail = built[index]
                    firstRail.metas = pages[index]
                    rails = [firstRail]
                    publishedInitialRail = true
                }
            }
        }

        let loaded = built.enumerated().compactMap { index, rail -> Rail? in
            guard !pages[index].isEmpty else { return nil }
            var populated = rail
            populated.metas = pages[index]
            return populated
        }
        // Keep the last good catalog snapshot if a refresh temporarily fails.
        guard !loaded.isEmpty else { return }
        rails = loaded
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var tmdbSettings = TMDBSettingsStore.shared
    @ObservedObject private var tmdbCatalog = TMDBCatalogStore.shared
    @AppStorage("harbor.region") private var region = "US"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var featuredIndex = 0

    private var adaptiveLayout: HarborAdaptiveLayout {
        .resolve(
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private var usesExpandedMetrics: Bool { adaptiveLayout == .pad }
    private var horizontalPadding: CGFloat { usesExpandedMetrics ? 28 : 16 }
    private var heroHeight: CGFloat { usesExpandedMetrics ? 530 : 450 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    homeHeader

                    if !featuredNavigations.isEmpty {
                        featuredCarousel
                    }

                    if viewModel.rails.isEmpty && viewModel.isLoading && tmdbCatalog.homeTrending.isEmpty {
                        loadingState
                    } else if viewModel.rails.isEmpty
                                && library.continueWatching.isEmpty
                                && tmdbCatalog.homeTrending.isEmpty {
                        ContentUnavailableCompat(
                            icon: "sparkles.tv",
                            title: "No catalogs",
                            message: tmdbSettings.hasAPIKey
                                ? "Harbor could not load your catalogs. Pull to retry."
                                : "Connect TMDB or sign in to pull your installed addon catalogs."
                        )
                        .frame(minHeight: 320)
                    } else {
                        if !library.continueWatching.isEmpty {
                            continueWatchingRow
                        }

                        if tmdbSettings.hasAPIKey {
                            TMDBStreamingProvidersRow()
                        } else {
                            TMDBKeyPrompt(compact: true)
                                .padding(.horizontal, horizontalPadding)
                        }

                        if !tmdbCatalog.homeTrending.isEmpty {
                            AdaptiveMediaRail(
                                title: "Top 10 Trending This Week",
                                subtitle: "Powered by TMDB · Updated weekly",
                                metas: tmdbCatalog.homeTrending,
                                source: .home,
                                ranked: true
                            )
                        } else if let firstRail = viewModel.rails.first {
                            TopTenRailRow(rail: firstRail)
                        }

                        ForEach(Array(viewModel.rails.dropFirst())) { rail in
                            RailRow(rail: rail)
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.load(forceAddonRefresh: true)
                await tmdbCatalog.loadHome(
                    apiKey: tmdbSettings.apiKey,
                    region: region,
                    force: true
                )
                if let authKey = AuthStore.shared.authKey {
                    await LibraryStore.shared.refresh(authKey: authKey, force: true)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
                await tmdbCatalog.loadHome(apiKey: tmdbSettings.apiKey, region: region)
                if let authKey = AuthStore.shared.authKey {
                    await LibraryStore.shared.refresh(authKey: authKey)
                }
            }
            .navigationDestination(for: MetaNavigation.self) { nav in
                DetailView(nav: nav)
            }
            .onChange(of: featuredNavigations.count) { count in
                if featuredIndex >= count {
                    featuredIndex = 0
                }
            }
            .onChange(of: tmdbSettings.apiKey) { apiKey in
                Task { await tmdbCatalog.loadHome(apiKey: apiKey, region: region, force: true) }
            }
            .onChange(of: region) { value in
                Task { await tmdbCatalog.loadHome(apiKey: tmdbSettings.apiKey, region: value, force: true) }
            }
            .onAppear {
                AnalyticsService.shared.setCurrentScreen(.home, screenClass: "HomeView")
            }
        }
    }

    private var homeHeader: some View {
        HStack {
            HarborWordmark()
                .accessibilityIdentifier("harbor.home.wordmark")
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var featuredNavigations: [MetaNavigation] {
        if !tmdbCatalog.homeTrending.isEmpty {
            return tmdbCatalog.homeTrending.prefix(usesExpandedMetrics ? 5 : 4).map {
                MetaNavigation(meta: $0, base: nil, source: .home)
            }
        }
        guard let rail = viewModel.rails.first else { return [] }
        return rail.metas.prefix(4).map {
            MetaNavigation(meta: $0, base: rail.base, source: .home)
        }
    }

    private var featuredCarousel: some View {
        VStack(spacing: 9) {
            TabView(selection: $featuredIndex) {
                ForEach(Array(featuredNavigations.enumerated()), id: \.element.meta.id) { index, navigation in
                    featuredHero(navigation)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: heroHeight)

            if featuredNavigations.count > 1 {
                HStack(spacing: 6) {
                    ForEach(featuredNavigations.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == featuredIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(width: index == featuredIndex ? 24 : 7, height: 4)
                            .animation(.easeInOut(duration: 0.2), value: featuredIndex)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func featuredHero(_ navigation: MetaNavigation) -> some View {
        let meta = navigation.meta
        return ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: meta.background ?? meta.poster ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Theme.surfaceRaised, Theme.surface, Theme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.2), Theme.background.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [Theme.background.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 11) {
                Text("FEATURED \(meta.type == "series" ? "SERIES" : "MOVIE")")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(2.2)
                    .foregroundColor(Theme.accent)

                if let logo = meta.logo, !logo.isEmpty {
                    AsyncImage(url: URL(string: logo)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Text(meta.name)
                                .font(.system(size: 34, weight: .bold, design: .serif))
                        }
                    }
                    .frame(maxWidth: 245, maxHeight: 82, alignment: .leading)
                } else {
                    Text(meta.name)
                        .font(.system(size: usesExpandedMetrics ? 44 : 34, weight: .bold, design: .serif))
                        .tracking(-1)
                        .lineLimit(2)
                }

                heroMetadata(meta)

                if let description = meta.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.74))
                        .lineLimit(3)
                        .frame(maxWidth: usesExpandedMetrics ? 510 : 330, alignment: .leading)
                }

                HStack(spacing: 10) {
                    NavigationLink(value: navigation) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(HarborPrimaryButtonStyle())

                    Button { toggleHeroBookmark(meta) } label: {
                        Label(
                            isBookmarked(meta) ? "Saved" : "Watchlist",
                            systemImage: isBookmarked(meta) ? "checkmark" : "plus"
                        )
                    }
                    .buttonStyle(HarborSecondaryButtonStyle())
                }
            }
            .padding(usesExpandedMetrics ? 28 : 18)
        }
        .frame(height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, usesExpandedMetrics ? 28 : 12)
    }

    private func heroMetadata(_ meta: Meta) -> some View {
        HStack(spacing: 7) {
            if let rating = meta.imdbRating, !rating.isEmpty {
                Text("IMDb \(rating)")
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
            }
            if let year = meta.releaseInfo, !year.isEmpty { Text(year) }
            if let runtime = meta.runtime, !runtime.isEmpty { Text(runtime) }
            Text(meta.type == "series" ? "Series" : "Movie")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.white.opacity(0.8))
    }

    private func isBookmarked(_ meta: Meta) -> Bool {
        library.item(id: meta.id)?.isBookmarked ?? false
    }

    private func toggleHeroBookmark(_ meta: Meta) {
        guard let authKey = AuthStore.shared.authKey else { return }
        Task { await library.toggleBookmark(authKey: authKey, meta: meta) }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.accent)
            Text("Curating Harbor")
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private var continueWatchingRow: some View {
        VStack(alignment: .leading, spacing: 11) {
            HarborSectionHeader(
                title: "Continue Watching",
                subtitle: "Pick up exactly where you left off"
            )
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(library.continueWatching.prefix(20)) { item in
                        NavigationLink(value: MetaNavigation(
                            meta: item.asMeta(),
                            base: nil,
                            source: .continueWatching
                        )) {
                            ContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}
