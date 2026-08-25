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

    @Published private(set) var addons: [Addon] = []
    @Published private(set) var isLoaded = false

    private var loadTask: Task<Void, Never>?

    /// All catalog-capable addons: user's cloud collection merged with Cinemeta.
    func gatherAddons(authKey: String?) async -> [Addon] {
        var collected: [Addon] = []
        if let authKey {
            collected = (try? await AddonClient.shared.addonCollection(authKey: authKey)) ?? []
        }
        let seen = Set(collected.map(\.transportUrl))
        let cinemeta = Addon(
            transportUrl: AddonClient.cinemetaBase + "/manifest.json",
            manifest: Self.cinemetaManifest,
            flags: AddonFlags(official: true, protected: false)
        )
        if !seen.contains(cinemeta.transportUrl) {
            collected.append(cinemeta)
        }
        await MainActor.run {
            self.addons = collected
            self.isLoaded = true
        }
        return collected
    }

    func invalidate() {
        isLoaded = false
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

                let key = Self.normalizeName(cat.name, type: cat.type)
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
                        title: cat.name,
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
        id: "com.stremio.cinemeta",
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
            .detailed(AddonResourceDef(name: "stream", types: ["movie", "series"], idPrefixes: ["tt"])),
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
        return m + s
    }
}
