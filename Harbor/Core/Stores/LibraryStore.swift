import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSync: Date?

    private init() {}

    // MARK: - Queries

    var continueWatching: [LibraryItem] {
        items
            .filter(\.isContinueWatching)
            .sorted { $0.sortTimestamp > $1.sortTimestamp }
    }

    var watchlist: [LibraryItem] {
        items
            .filter(\.isInWatchlist)
            .sorted { $0.sortTimestamp > $1.sortTimestamp }
    }

    func item(id: String) -> LibraryItem? {
        items.first { $0.id == id }
    }

    // MARK: - Sync

    func refresh(authKey: String, force: Bool = false) async {
        if isLoading { return }
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < 60 { return }
        isLoading = true
        defer {
            isLoading = false
            lastSync = Date()
        }

        do {
            struct MetaPairs: Decodable {
                let pairs: [[String]]
            }
            let rawIds: [[String]] = try await StremioAPI.shared.call(
                "datastoreMeta",
                body: ["authKey": authKey, "collection": "libraryItem"]
            )
            let ids = rawIds.compactMap { $0.first }
            guard !ids.isEmpty else {
                items = []
                return
            }
            var fetched: [LibraryItem] = []
            for chunk in stride(from: 0, to: ids.count, by: 400).map({ Array(ids[$0..<min($0 + 400, ids.count)]) }) {
                let page: [LibraryItem] = try await StremioAPI.shared.call(
                    "datastoreGet",
                    body: [
                        "authKey": authKey,
                        "collection": "libraryItem",
                        "ids": chunk,
                        "all": true,
                    ]
                )
                fetched += page
            }
            items = fetched
        } catch {
            // Keep stale data on failure; surfaced via lastSync.
        }
    }

    // MARK: - Mutations

    func saveProgress(
        authKey: String,
        metaId: String,
        videoId: String?,
        offset: Double,
        duration: Double
    ) async {
        await mutate(authKey: authKey, id: metaId) { item in
            var state = item.state ?? LibraryState()
            state.timeOffset = offset
            state.duration = max(duration, state.duration ?? 0)
            if let videoId {
                state.videoId = videoId
                let parts = videoId.split(separator: ":")
                if parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) {
                    state.season = s
                    state.episode = e
                }
            }
            state.lastWatched = ISO8601DateFormatter().string(from: Date())
            state.timesWatched = state.timesWatched ?? 0
            state.overallTimeWatched = state.overallTimeWatched ?? 0
            state.noNotif = state.noNotif ?? false
            item.state = state
            item.removed = false
        }
    }

    /// Flags an episode/movie as fully watched.
    func markWatched(authKey: String, metaId: String, videoId: String?) async {
        await mutate(authKey: authKey, id: metaId) { item in
            var state = item.state ?? LibraryState()
            state.flaggedWatched = Date().timeIntervalSince1970 * 1000
            state.timeOffset = 0
            if let videoId { state.videoId = videoId }
            state.timesWatched = (state.timesWatched ?? 0) + 1
            state.lastWatched = ISO8601DateFormatter().string(from: Date())
            item.state = state
        }
    }

    func toggleBookmark(authKey: String, meta: Meta) async {
        let existing = item(id: meta.id)
        let shouldRemove = existing.map { !$0.removed && !$0.temp } ?? false
        await mutate(authKey: authKey, id: meta.id) { item in
            if item.name.isEmpty {
                item.name = meta.name
                item.type = meta.type
                item.poster = meta.poster
                item.background = meta.background
                item.posterShape = "poster"
            }
            item.removed = shouldRemove
            item.temp = false
        }
    }

    func removeContinueWatching(authKey: String, id: String) async {
        await mutate(authKey: authKey, id: id) { item in
            item.removed = true
            item.temp = true
        }
    }

    /// Fetch-or-create the cloud item, apply mutation, persist via datastorePut,
    /// and update local cache optimistically.
    private func mutate(
        authKey: String,
        id: String,
        change: @escaping (inout LibraryItem) -> Void
    ) async {
        let now = ISO8601DateFormatter().string(from: Date())
        var target = item(id: id)

        if target == nil {
            // Pull from cloud before creating fresh (another device may have it).
            let remote: [LibraryItem]? = try? await StremioAPI.shared.call(
                "datastoreGet",
                body: ["authKey": authKey, "collection": "libraryItem", "ids": [id], "all": false]
            )
            target = remote?.first
        }

        var item = target ?? LibraryItem(
            id: id,
            type: "movie",
            name: "",
            poster: nil,
            background: nil,
            posterShape: "poster",
            removed: false,
            temp: false,
            ctime: now,
            mtime: now,
            state: nil,
            behaviorHints: LibraryBehaviorHints()
        )

        change(&item)
        item.mtime = now
        if item.ctime == nil { item.ctime = now }
        if item.behaviorHints == nil { item.behaviorHints = LibraryBehaviorHints() }
        if item.posterShape == nil { item.posterShape = "poster" }

        struct PutOK: Decodable {}
        let _: PutOK? = try? await StremioAPI.shared.call(
            "datastorePut",
            body: [
                "authKey": authKey,
                "collection": "libraryItem",
                "changes": [item],
            ]
        )

        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }
}
