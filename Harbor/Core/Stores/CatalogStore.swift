import Foundation

struct Rail: Identifiable {
    let id: String
    let title: String
    let type: String
    var metas: [Meta]
    let base: String
    let catalogId: String
    let extras: [String: String]?
}

@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    private struct LoadKey: Equatable {
        let authKey: String?
        let force: Bool
    }

    private struct InFlightLoad {
        let key: LoadKey
        let generation: UInt
        let task: Task<[Addon], Never>
    }

    @Published private(set) var addons: [Addon] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var errorMessage: String?

    private var loadTask: InFlightLoad?
    private var loadGeneration: UInt = 0
    private var loadedAuthKey: String?

    /// All catalog-capable addons: user's cloud collection merged with Cinemeta.
    func gatherAddons(authKey: String?, force: Bool = false) async -> [Addon] {
        if !force, isLoaded, loadedAuthKey == authKey {
            return addons
        }
        let key = LoadKey(authKey: authKey, force: force)
        if let loadTask, loadTask.key == key {
            return await loadTask.task.value
        }

        loadTask?.task.cancel()
        let existing = loadedAuthKey == authKey ? addons : []
        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return [] }
            return await self.fetchAddons(authKey: authKey, existing: existing)
        }
        loadTask = InFlightLoad(key: key, generation: generation, task: task)
        let result = await task.value
        if loadTask?.key == key, loadTask?.generation == generation {
            loadTask = nil
        }
        return result
    }

    private func fetchAddons(authKey: String?, existing: [Addon]) async -> [Addon] {
        var collected: [Addon] = []
        if let authKey {
            do {
                collected = try await AddonClient.shared.addonCollection(authKey: authKey)
                guard !Task.isCancelled, authKey == AuthStore.shared.authKey else { return [] }
                errorMessage = nil
                AddonManager.shared.applySyncedAddons(collected, authKey: authKey)
            } catch {
                guard authKey == AuthStore.shared.authKey else { return [] }
                errorMessage = error.localizedDescription
                // A transient refresh failure should not discard a collection
                // that was already synced during this session.
                collected = AddonManager.shared.cloudAddons
                if collected.isEmpty {
                    collected = existing.filter { $0.manifest.id != Self.cinemetaManifest.id }
                }
            }
        } else {
            errorMessage = nil
        }
        let cinemeta = Addon(
            transportUrl: AddonClient.cinemetaBase + "/manifest.json",
            manifest: Self.cinemetaManifest,
            flags: AddonFlags(official: true, protected: false)
        )
        if let existingIndex = collected.firstIndex(where: {
            $0.manifest.id == cinemeta.manifest.id
                || AddonClient.baseURL(for: $0.transportUrl) == AddonClient.cinemetaBase
        }) {
            let installedCinemeta = collected.remove(at: existingIndex)
            collected.insert(installedCinemeta, at: 0)
        } else {
            collected.insert(cinemeta, at: 0)
        }
        guard !Task.isCancelled, authKey == AuthStore.shared.authKey else { return [] }
        self.addons = collected
        self.isLoaded = true
        self.loadedAuthKey = authKey
        return collected
    }

    func invalidate() {
        loadTask?.task.cancel()
        loadTask = nil
        loadGeneration &+= 1
        isLoaded = false
    }

    func reset() {
        loadTask?.task.cancel()
        loadTask = nil
        loadGeneration &+= 1
        addons = []
        isLoaded = false
        loadedAuthKey = nil
        errorMessage = nil
    }

    /// Build home rails from every catalog of every addon (deduped by name+type).
    func buildRails(from addons: [Addon], maxRails: Int = 10) -> [Rail] {
        struct PendingRail {
            let rail: Rail
            let order: Int
        }
        var pending: [PendingRail] = []
        var seenKeys = Set<String>()
        var order = 0

        for addon in addons where !(addon.manifest.behaviorHints?.configurationRequired ?? false) {
            let catalogs = addon.manifest.catalogs ?? []
            for cat in catalogs {
                guard !cat.type.isEmpty,
                      !cat.id.isEmpty,
                      cat.type.lowercased() != "addon_catalog",
                      !(cat.extra ?? []).contains(where: { $0.name == "search" && $0.isRequired == true })
                else { continue }

                let name = cat.name ?? cat.id
                let key = Self.normalizeName(name, type: cat.type)
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)

                var extras: [String: String] = [:]
                for extra in cat.extra ?? [] where extra.isRequired == true {
                    if let first = extra.options?.first {
                        extras[extra.name] = first
                    } else {
                        extras[extra.name] = ""
                    }
                }

                pending.append(PendingRail(
                    rail: Rail(
                        id: key,
                        title: name,
                        type: cat.type,
                        metas: [],
                        base: AddonClient.baseURL(for: addon.transportUrl),
                        catalogId: cat.id,
                        extras: extras.isEmpty ? nil : extras
                    ),
                    order: order
                ))
                order += 1
            }
        }

        return pending
            .sorted { $0.order < $1.order }
            .prefix(maxRails)
            .map(\.rail)
    }

    static func normalizeName(_ name: String, type: String) -> String {
        let stripWords = ["movies", "movie", "series", "shows", "show", "tv shows", "tv"]
        var lowered = name.lowercased()
        for word in stripWords {
            lowered = lowered.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: "",
                options: .regularExpression
            )
        }
        let cleaned = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(cleaned)::\(type)"
    }

    static let cinemetaManifest = AddonManifest(
        id: "com.linvo.cinemeta",
        name: "Cinemeta",
        version: "3.0",
        description: "Official Stremio metadata for movies and series.",
        logo: "https://images.metahub.space/logo/medium/tt5491982/img",
        background: nil,
        contactEmail: nil,
        types: ["movie", "series"],
        resources: [
            .detailed(AddonResourceDef(name: "catalog", types: ["movie", "series"], idPrefixes: ["tt"])),
            .detailed(AddonResourceDef(name: "meta", types: ["movie", "series"], idPrefixes: ["tt"])),
        ],
        catalogs: [
            AddonCatalogDef(type: "movie", id: "top", name: "Trending Movies", extra: [
                AddonCatalogExtra(name: "search", isRequired: false, options: nil),
                AddonCatalogExtra(name: "skip", isRequired: false, options: nil),
            ]),
            AddonCatalogDef(type: "series", id: "top", name: "Trending Series", extra: [
                AddonCatalogExtra(name: "search", isRequired: false, options: nil),
                AddonCatalogExtra(name: "skip", isRequired: false, options: nil),
            ]),
            AddonCatalogDef(type: "movie", id: "popular", name: "Popular Movies", extra: nil),
            AddonCatalogDef(type: "series", id: "popular", name: "Popular Series", extra: nil),
            AddonCatalogDef(type: "movie", id: "year", name: "New Movies", extra: nil),
            AddonCatalogDef(type: "series", id: "year", name: "New Series", extra: nil),
        ],
        idPrefixes: ["tt"],
        behaviorHints: nil
    )

    // MARK: - Search

    func search(query: String, skip: Int = 0) async -> [Meta] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        async let movies = AddonClient.shared.catalogPage(
            base: AddonClient.cinemetaBase, type: "movie", id: "top",
            extras: ["search": trimmed, "skip": String(skip)]
        )
        async let series = AddonClient.shared.catalogPage(
            base: AddonClient.cinemetaBase, type: "series", id: "top",
            extras: ["search": trimmed, "skip": String(skip)]
        )
        let m = (try? await movies) ?? []
        let s = (try? await series) ?? []
        return Self.interleavedSearchResults(movies: m, series: s)
    }

    nonisolated static func interleavedSearchResults(movies: [Meta], series: [Meta]) -> [Meta] {
        var results: [Meta] = []
        results.reserveCapacity(movies.count + series.count)
        for index in 0..<max(movies.count, series.count) {
            if index < movies.count { results.append(movies[index]) }
            if index < series.count { results.append(series[index]) }
        }
        return results
    }
}
