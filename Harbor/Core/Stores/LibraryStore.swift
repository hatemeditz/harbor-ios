import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var errorMessage: String?

    private var mutationTasks: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    private init() {}

    func reset() {
        mutationTasks.values.forEach { $0.task.cancel() }
        mutationTasks = [:]
        items = []
        isLoading = false
        lastSync = nil
        errorMessage = nil
    }

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
        errorMessage = nil
        defer { isLoading = false }

        do {
            // This is Stremio's full-library pull contract. datastoreMeta
            // returns heterogeneous [id, millisecondTimestamp] tuples and is
            // intended for clients that maintain their own incremental cache.
            let response: LossyArray<LibraryItem> = try await StremioAPI.shared.call(
                "datastoreGet",
                body: [
                    "authKey": authKey,
                    "collection": "libraryItem",
                    "ids": [],
                    "all": true,
                ]
            )
            guard AuthStore.shared.authKey == authKey else { return }
            items = response.elements
            lastSync = Date()
        } catch {
            // Keep stale data and allow the next refresh to retry immediately.
            if AuthStore.shared.authKey == authKey {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Mutations

    func saveProgress(
        authKey: String,
        target: StreamTarget,
        offset: Double,
        duration: Double
    ) async {
        await mutate(authKey: authKey, id: target.metaId) { item in
            Self.applyMetadata(from: target, to: &item)
            var state = item.state ?? LibraryState()
            let videoChanged = target.videoId != nil
                && state.videoId != nil
                && state.videoId != target.videoId
            if videoChanged {
                state.overallTimeWatched = (state.overallTimeWatched ?? 0) + (state.timeWatched ?? 0)
                state.flaggedWatched = 0
            }
            state.timeOffset = (state.flaggedWatched ?? 0) > 0 ? 0 : offset
            state.timeWatched = offset
            state.duration = videoChanged ? duration : max(duration, state.duration ?? 0)
            if let videoId = target.videoId {
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
            if item.removed {
                item.temp = true
            }
            item.removed = false
        }
    }

    /// Flags an episode/movie as fully watched.
    func markWatched(authKey: String, target: StreamTarget) async {
        await mutate(authKey: authKey, id: target.metaId) { item in
            Self.applyMetadata(from: target, to: &item)
            var state = item.state ?? LibraryState()
            state.flaggedWatched = 1
            state.timeOffset = 0
            if let videoId = target.videoId { state.videoId = videoId }
            state.timesWatched = (state.timesWatched ?? 0) + 1
            state.lastWatched = ISO8601DateFormatter().string(from: Date())
            item.state = state
            if item.removed {
                item.temp = true
            }
            item.removed = false
        }
    }

    private static func applyMetadata(from target: StreamTarget, to item: inout LibraryItem) {
        item.type = target.type
        if item.name.isEmpty {
            item.name = target.metaName
        }
        if item.poster == nil {
            item.poster = target.poster
        }
        if item.background == nil {
            item.background = target.background
        }
    }

    func toggleBookmark(authKey: String, meta: Meta) async {
        let existing = item(id: meta.id)
        let shouldRemove = existing?.isBookmarked ?? false
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
            var state = item.state ?? LibraryState()
            state.timeOffset = 0
            item.state = state
            item.removed = true
            item.temp = false
        }
    }

    /// Fetch-or-create the cloud item, apply mutation, persist via datastorePut,
    /// and update local cache optimistically.
    private func mutate(
        authKey: String,
        id: String,
        change: @escaping (inout LibraryItem) -> Void
    ) async {
        let previous = mutationTasks[id]?.task
        let token = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await performMutation(authKey: authKey, id: id, change: change)
        }
        mutationTasks[id] = (token, task)
        await task.value
        if mutationTasks[id]?.token == token {
            mutationTasks[id] = nil
        }
    }

    private func performMutation(
        authKey: String,
        id: String,
        change: @escaping (inout LibraryItem) -> Void
    ) async {
        let now = ISO8601DateFormatter().string(from: Date())
        var target = item(id: id)

        if target == nil {
            // Pull from cloud before creating fresh (another device may have it).
            let remote: LossyArray<LibraryItem>? = try? await StremioAPI.shared.call(
                "datastoreGet",
                body: ["authKey": authKey, "collection": "libraryItem", "ids": [id], "all": false]
            )
            target = remote?.elements.first
        }

        var item = target ?? LibraryItem(
            id: id,
            type: "movie",
            name: "",
            poster: nil,
            background: nil,
            posterShape: "poster",
            removed: false,
            temp: true,
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

        do {
            // JSONSerialization cannot encode an arbitrary Codable struct
            // embedded in [String: Any], so bridge it through JSONEncoder.
            let encoded = try JSONEncoder().encode(item)
            guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                throw StremioAPIError.decoding
            }
            try await StremioAPI.shared.callIgnoringResult(
                "datastorePut",
                body: [
                    "authKey": authKey,
                    "collection": "libraryItem",
                    "changes": [object],
                ]
            )

            guard AuthStore.shared.authKey == authKey else { return }
            errorMessage = nil
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = item
            } else {
                items.append(item)
            }
        } catch {
            // Do not claim a local success when the cloud write failed.
            if AuthStore.shared.authKey == authKey {
                errorMessage = error.localizedDescription
            }
        }
    }
}
