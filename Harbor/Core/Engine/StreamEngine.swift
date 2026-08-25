import Foundation

@MainActor
final class StreamEngine: ObservableObject {
    struct AddonProgress: Identifiable {
        let id: String
        let name: String
        var state: State

        enum State {
            case pending
            case done(Int)
            case failed
        }
    }

    @Published var streams: [ScoredStream] = []
    @Published var progress: [AddonProgress] = []
    @Published var isLoading = false

    private var nextId = 0
    private var loadToken = UUID()

    /// All addons that declare a `stream` resource usable for this target.
    func streamAddons(for target: StreamTarget) async -> [Addon] {
        let all = await CatalogStore.shared.gatherAddons(authKey: AuthStore.shared.authKey)
        return all.filter { addon in
            guard !(addon.manifest.behaviorHints?.configurationRequired ?? false) else { return false }
            let resources = addon.manifest.resources ?? []
            let hasStreamResource = resources.contains { resource in
                switch resource {
                case .named(let name):
                    return name == "stream"
                case .detailed(let def):
                    if def.name != "stream" { return false }
                    if let types = def.types, !types.isEmpty, !types.contains(target.type) { return false }
                    return true
                }
            }
            guard hasStreamResource else { return false }

            if let types = addon.manifest.types, !types.isEmpty, !types.contains(target.type) {
                return false
            }
            if let prefixes = addon.manifest.idPrefixes, !prefixes.isEmpty,
               !prefixes.contains(where: { target.metaId.hasPrefix($0) }) {
                return false
            }
            return true
        }
    }

    func load(target: StreamTarget) async {
        loadToken = UUID()
        let token = loadToken
        isLoading = true
        streams = []
        nextId = 0

        let stremioId = target.videoId ?? target.metaId
        let addons = await streamAddons(for: target)

        progress = addons.map { addon in
            AddonProgress(id: addon.id, name: addon.manifest.name, state: .pending)
        }

        guard !addons.isEmpty else {
            isLoading = false
            return
        }

        await withTaskGroup(of: (String, [RawStream]?, Bool).self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        let response: StreamResponse = try await AddonClient.shared.fetchJSON(
                            AddonClient.streamURL(
                                base: AddonClient.baseURL(for: addon.transportUrl),
                                type: target.type,
                                id: stremioId
                            )
                        )
                        return (addon.id, response.streams ?? [], true)
                    } catch {
                        return (addon.id, nil, false)
                    }
                }
            }

            for await (addonId, rawStreams, ok) in group {
                guard token == loadToken else { return }
                if let index = progress.firstIndex(where: { $0.id == addonId }) {
                    progress[index].state = ok ? .done(rawStreams?.count ?? 0) : .failed
                }

                var batch: [ScoredStream] = []
                for var raw in (rawStreams ?? []) {
                    raw.addonName = progress.first { $0.id == addonId }?.name
                    nextId += 1
                    if let scored = StreamScorer.score(raw: raw, id: nextId) {
                        batch.append(scored)
                    }
                }
                streams = StreamScorer.sort(streams + batch)
            }
        }

        if token == loadToken {
            isLoading = false
        }
    }

    func cancel() {
        loadToken = UUID()
    }
}
