import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Meta] = []
    @Published var isSearching = false
    @Published var hasSearched = false

    private var debounceTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var nextSkip = 50
    private var canLoadMore = false

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
        }
    }

    func loadMoreIfNeeded(current: Meta) {
        guard let last = results.last, current.id == last.id, current.type == last.type,
              !isSearching, canLoadMore else { return }
        pageTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let skip = nextSkip
        pageTask = Task {
            await search(query: q, skip: skip, appending: true)
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
            Group {
                if viewModel.results.isEmpty {
                    emptyState
                } else {
                    resultsGrid
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
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.results) { meta in
                    NavigationLink(value: MetaNavigation(meta: meta, base: nil)) {
                        PosterCard(meta: meta, width: 104)
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
                message: "Nothing matched \"\(viewModel.query)\"."
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
