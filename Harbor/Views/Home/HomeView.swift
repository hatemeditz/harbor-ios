import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var rails: [Rail] = []
    @Published var hero: Meta?
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
        guard !built.isEmpty else {
            if rails.isEmpty { hero = nil }
            return
        }

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
                    hero = pages[index].first
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
        hero = loaded.lazy.compactMap { $0.metas.first }.first
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var library = LibraryStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.rails.isEmpty && viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.accent)
                        Text("Loading catalogs")
                            .foregroundColor(Theme.textSecondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 180)
                } else if viewModel.rails.isEmpty && library.continueWatching.isEmpty {
                    ContentUnavailableCompat(
                        icon: "sparkles.tv",
                        title: "No catalogs",
                        message: "Sign in to pull your installed addon catalogs."
                    )
                    .padding(.top, 120)
                } else {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if !library.continueWatching.isEmpty {
                            continueWatchingRow
                        }
                        ForEach(viewModel.rails) { rail in
                            RailRow(rail: rail)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .background(Theme.background)
            .navigationTitle("Home")
            .refreshable {
                await viewModel.load(forceAddonRefresh: true)
                if let authKey = AuthStore.shared.authKey {
                    await LibraryStore.shared.refresh(authKey: authKey, force: true)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
                if let authKey = AuthStore.shared.authKey {
                    await LibraryStore.shared.refresh(authKey: authKey)
                }
            }
            .navigationDestination(for: MetaNavigation.self) { nav in
                DetailView(nav: nav)
            }
        }
    }

    private var continueWatchingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Watching")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(library.continueWatching.prefix(20)) { item in
                        NavigationLink(value: MetaNavigation(meta: item.asMeta(), base: nil)) {
                            ContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
