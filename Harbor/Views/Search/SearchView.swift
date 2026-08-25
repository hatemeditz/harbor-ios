import SwiftUI

enum CatalogSearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case movie = "Movies"
    case series = "Series"

    var id: String { rawValue }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Meta] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var scope: CatalogSearchScope = .all

    private var debounceTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var nextSkip = 50
    private var canLoadMore = false

    var visibleResults: [Meta] {
        switch scope {
        case .all: return results
        case .movie: return results.filter { $0.type == "movie" }
        case .series: return results.filter { $0.type == "series" }
        }
    }

    func queryChanged() {
        debounceTask?.cancel()
        pageTask?.cancel()
        nextSkip = 50
        canLoadMore = false
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search(query: q, skip: 0, appending: false)
            await loadUntilScopeHasResults(query: q)
        }
    }

    func scopeChanged() {
        guard hasSearched, !isSearching, visibleResults.isEmpty, canLoadMore else { return }
        pageTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        pageTask = Task {
            await loadUntilScopeHasResults(query: q)
        }
    }

    func loadMoreIfNeeded(current: Meta) {
        guard let last = visibleResults.last, current.id == last.id, current.type == last.type,
              !isSearching, canLoadMore else { return }
        pageTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let skip = nextSkip
        pageTask = Task {
            await search(query: q, skip: skip, appending: true)
            await loadUntilScopeHasResults(query: q)
        }
    }

    private func loadUntilScopeHasResults(query requestedQuery: String) async {
        while !Task.isCancelled,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery,
              visibleResults.isEmpty,
              canLoadMore {
            let skip = nextSkip
            await search(query: requestedQuery, skip: skip, appending: true)
        }
    }

    private func search(query requestedQuery: String, skip: Int, appending: Bool) async {
        isSearching = true
        defer {
            if query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery {
                isSearching = false
            }
        }
        hasSearched = true
        let found = await CatalogStore.shared.search(query: requestedQuery, skip: skip)
        guard !Task.isCancelled,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery
        else { return }
        var seen = appending ? Set(results.map { "\($0.id)|\($0.type)" }) : Set<String>()
        let unique = found.filter { meta in
            seen.insert("\(meta.id)|\(meta.type)").inserted
        }
        if appending {
            results += unique
            canLoadMore = !unique.isEmpty
            nextSkip += 50
        } else {
            results = unique
            nextSkip = 50
            canLoadMore = !unique.isEmpty
        }
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.hasSearched {
                    Picker("Type", selection: $viewModel.scope) {
                        ForEach(CatalogSearchScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                Group {
                    if viewModel.visibleResults.isEmpty {
                        emptyState
                    } else {
                        resultsGrid
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Search")
            .navigationDestination(for: MetaNavigation.self) { nav in
                DetailView(nav: nav)
            }
            .searchable(text: $viewModel.query, prompt: "Movies & series")
            .onChange(of: viewModel.query) { _ in
                viewModel.queryChanged()
            }
            .onChange(of: viewModel.scope) { _ in
                viewModel.scopeChanged()
            }
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.visibleResults) { meta in
                    NavigationLink(value: MetaNavigation(meta: meta, base: nil)) {
                        PosterCard(meta: meta, width: 104, showTypeBadge: true)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(current: meta)
                    }
                }
            }
            .padding(16)

            if viewModel.isSearching {
                ProgressView().tint(Theme.accent).padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isSearching {
            VStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text("Searching")
                    .foregroundColor(Theme.textSecondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasSearched {
            ContentUnavailableCompat(
                icon: "magnifyingglass",
                title: "No results",
                message: viewModel.scope == .all
                    ? "Nothing matched \"\(viewModel.query)\"."
                    : "No \(viewModel.scope.rawValue.lowercased()) matched \"\(viewModel.query)\"."
            )
        } else {
            ContentUnavailableCompat(
                icon: "magnifyingglass",
                title: "Search",
                message: "Find any movie or series via Cinemeta."
            )
        }
    }
}
