import SwiftUI

struct LibraryView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var segment = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Section", selection: $segment) {
                    Text("Watchlist").tag(0)
                    Text("Continue Watching").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                switch segment {
                case 0: grid(library.watchlist, emptyIcon: "bookmark.slash", emptyText: "Your watchlist is empty")
                default: cwList
                }
            }
            .background(Theme.background)
            .navigationTitle("Library")
            .refreshable { await sync() }
            .task { await sync() }
            .navigationDestination(for: MetaNavigation.self) { nav in
                DetailView(nav: nav)
            }
        }
    }

    private func sync() async {
        guard let authKey = AuthStore.shared.authKey else { return }
        await library.refresh(authKey: authKey)
    }

    @ViewBuilder
    private func grid(_ items: [LibraryItem], emptyIcon: String, emptyText: String) -> some View {
        if items.isEmpty {
            ContentUnavailableCompat(icon: emptyIcon, title: emptyText, message: "")
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    NavigationLink(value: MetaNavigation(meta: item.asMeta(), base: nil)) {
                        PosterCard(meta: item.asMeta(), width: 104)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            removeBookmark(item)
                        } label: {
                            Label("Remove from watchlist", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var cwList: some View {
        Group {
            if library.continueWatching.isEmpty {
                ContentUnavailableCompat(
                    icon: "play.rectangle.on.rectangle",
                    title: "Nothing in progress",
                    message: "Titles you start watching appear here."
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(library.continueWatching) { item in
                        NavigationLink(value: MetaNavigation(meta: item.asMeta(), base: nil)) {
                            ContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                hideFromCW(item)
                            } label: {
                                Label("Hide from Continue Watching", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func removeBookmark(_ item: LibraryItem) {
        guard let authKey = AuthStore.shared.authKey else { return }
        Task {
            await library.toggleBookmark(authKey: authKey, meta: item.asMeta())
        }
    }

    private func hideFromCW(_ item: LibraryItem) {
        guard let authKey = AuthStore.shared.authKey else { return }
        Task {
            await library.removeContinueWatching(authKey: authKey, id: item.id)
        }
    }
}
