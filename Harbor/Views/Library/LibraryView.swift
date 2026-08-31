import SwiftUI

struct LibraryView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var segment = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    HarborPageHeader(
                        title: "My Library",
                        eyebrow: "Your Harbor",
                        subtitle: "Saved stories and unfinished voyages"
                    )
                    .accessibilityIdentifier("harbor.library.header")

                    HStack(spacing: 8) {
                        HarborFilterPill(title: "Watchlist", selected: segment == 0) {
                            withAnimation(.easeInOut(duration: 0.2)) { segment = 0 }
                        }
                        HarborFilterPill(title: "Continue Watching", selected: segment == 1) {
                            withAnimation(.easeInOut(duration: 0.2)) { segment = 1 }
                        }
                        Spacer()
                    }

                    if let error = library.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }

                    HarborSectionHeader(
                        title: segment == 0 ? "Saved for Later" : "Continue Watching",
                        subtitle: segment == 0
                            ? "\(library.watchlist.count) titles"
                            : "\(library.continueWatching.count) in progress"
                    )

                    switch segment {
                    case 0:
                        grid(
                            library.watchlist,
                            emptyIcon: "bookmark.slash",
                            emptyText: "Your watchlist is empty"
                        )
                    default:
                        cwList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await sync(force: true) }
            .task { await sync() }
            .navigationDestination(for: MetaNavigation.self) { nav in
                DetailView(nav: nav)
            }
            .onAppear {
                AnalyticsService.shared.setCurrentScreen(.library, screenClass: "LibraryView")
            }
        }
    }

    private func sync(force: Bool = false) async {
        guard let authKey = AuthStore.shared.authKey else { return }
        await library.refresh(authKey: authKey, force: force)
    }

    @ViewBuilder
    private func grid(_ items: [LibraryItem], emptyIcon: String, emptyText: String) -> some View {
        if items.isEmpty {
            ContentUnavailableCompat(icon: emptyIcon, title: emptyText, message: "")
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    NavigationLink(value: MetaNavigation(
                        meta: item.asMeta(),
                        base: nil,
                        source: .watchlist
                    )) {
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
                        NavigationLink(value: MetaNavigation(
                            meta: item.asMeta(),
                            base: nil,
                            source: .continueWatching
                        )) {
                            libraryContinueCard(item)
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
            }
        }
    }

    private func libraryContinueCard(_ item: LibraryItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: (item.background ?? item.poster) ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Theme.surfaceRaised, Theme.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 178)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(continueWatchingSubtitle(item))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(Theme.accent)
                            .frame(width: geometry.size.width * item.progressRatio)
                    }
                }
                .frame(height: 3)
                .padding(.top, 4)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 178)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }

    private func continueWatchingSubtitle(_ item: LibraryItem) -> String {
        if let episode = item.episodeFromVideoId {
            return "Season \(episode.season) · Episode \(episode.episode)"
        }
        return item.type == "series" ? "Continue series" : "Continue movie"
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
