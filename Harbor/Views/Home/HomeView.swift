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

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            loadedOnce = true
        }

        let addons = await CatalogStore.shared.gatherAddons(authKey: AuthStore.shared.authKey)
        let built = CatalogStore.shared.buildRails(from: addons, maxRails: 10)
        guard !built.isEmpty else {
            rails = []
            return
        }
        rails = built

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
                guard index < rails.count else { continue }
                rails[index].metas = Array(metas.prefix(24))
                if hero == nil, let candidate = metas.first {
                    hero = candidate
                }
            }
        }
        // Drop rails that came back empty.
        rails.removeAll { $0.metas.isEmpty }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

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
                } else if viewModel.rails.isEmpty {
                    ContentUnavailableCompat(
                        icon: "sparkles.tv",
                        title: "No catalogs",
                        message: "Sign in to pull your installed addon catalogs."
                    )
                    .padding(.top, 120)
                } else {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(viewModel.rails) { rail in
                            RailRow(rail: rail)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .background(Theme.background)
            .navigationTitle("Home")
            .refreshable { await viewModel.load() }
            .task { await viewModel.loadIfNeeded() }
            .navigationDestination(for: Meta.self) { meta in
                DetailView(meta: meta)
            }
        }
    }
}
