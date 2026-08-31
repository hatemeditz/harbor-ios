import Combine
import Foundation

@MainActor
final class TMDBSettingsStore: ObservableObject {
    enum ValidationState: Equatable {
        case idle
        case checking
        case valid
        case invalid
    }

    static let shared = TMDBSettingsStore()
    private static let keychainAccount = "tmdb-api-key"

    @Published private(set) var apiKey: String
    @Published private(set) var validationState: ValidationState
    @Published private(set) var errorMessage: String?

    var hasAPIKey: Bool { !apiKey.isEmpty }

    private init() {
        let stored = Keychain.string(for: Self.keychainAccount) ?? ""
        apiKey = stored
        validationState = stored.isEmpty ? .idle : .valid
    }

    @discardableResult
    func verifyAndSave(_ candidate: String) async -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationState = .invalid
            errorMessage = "Enter your TMDB v3 API key."
            return false
        }
        validationState = .checking
        errorMessage = nil
        do {
            try await TMDBClient.shared.validate(apiKey: trimmed)
            Keychain.set(trimmed, for: Self.keychainAccount)
            apiKey = trimmed
            validationState = .valid
            return true
        } catch {
            validationState = .invalid
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "TMDB validation failed."
            return false
        }
    }

    func removeAPIKey() {
        Keychain.delete(account: Self.keychainAccount)
        apiKey = ""
        validationState = .idle
        errorMessage = nil
        TMDBCatalogStore.shared.reset()
    }
}

struct TMDBShelf: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let metas: [Meta]
}

struct TMDBGenreDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let movieGenreID: Int
    let tintHex: String
    let symbol: String

    var collection: TMDBCollectionDefinition {
        TMDBCollectionDefinition(
            id: "genre-\(id)",
            title: name,
            subtitle: "Popular \(name.lowercased()) movies",
            endpoint: .discover(.movie),
            parameters: [
                "with_genres": String(movieGenreID),
                "vote_count.gte": "100",
                "sort_by": "popularity.desc",
            ]
        )
    }

    static let all: [TMDBGenreDefinition] = [
        .init(id: "action", name: "Action", movieGenreID: 28, tintHex: "A43B2B", symbol: "bolt.fill"),
        .init(id: "adventure", name: "Adventure", movieGenreID: 12, tintHex: "26734D", symbol: "map.fill"),
        .init(id: "animation", name: "Animation", movieGenreID: 16, tintHex: "267A8A", symbol: "sparkles"),
        .init(id: "comedy", name: "Comedy", movieGenreID: 35, tintHex: "B77A22", symbol: "face.smiling.fill"),
        .init(id: "crime", name: "Crime", movieGenreID: 80, tintHex: "604431", symbol: "building.columns.fill"),
        .init(id: "documentary", name: "Documentary", movieGenreID: 99, tintHex: "32684A", symbol: "camera.fill"),
        .init(id: "drama", name: "Drama", movieGenreID: 18, tintHex: "355F91", symbol: "theatermasks.fill"),
        .init(id: "family", name: "Family", movieGenreID: 10751, tintHex: "718A2D", symbol: "figure.2.and.child.holdinghands"),
        .init(id: "fantasy", name: "Fantasy", movieGenreID: 14, tintHex: "743E86", symbol: "wand.and.stars"),
        .init(id: "history", name: "History", movieGenreID: 36, tintHex: "805D35", symbol: "clock.fill"),
        .init(id: "horror", name: "Horror", movieGenreID: 27, tintHex: "5B2525", symbol: "moon.stars.fill"),
        .init(id: "mystery", name: "Mystery", movieGenreID: 9648, tintHex: "605E28", symbol: "magnifyingglass"),
        .init(id: "romance", name: "Romance", movieGenreID: 10749, tintHex: "9B3F61", symbol: "heart.fill"),
        .init(id: "scifi", name: "Sci-Fi", movieGenreID: 878, tintHex: "57459B", symbol: "atom"),
        .init(id: "thriller", name: "Thriller", movieGenreID: 53, tintHex: "285A68", symbol: "waveform.path.ecg"),
        .init(id: "western", name: "Western", movieGenreID: 37, tintHex: "986332", symbol: "sun.horizon.fill"),
    ]
}

@MainActor
final class TMDBCatalogStore: ObservableObject {
    static let shared = TMDBCatalogStore()

    @Published private(set) var homeTrending: [Meta] = []
    @Published private(set) var shelves: [TMDBShelf] = []
    @Published private(set) var isLoadingHome = false
    @Published private(set) var isLoadingDiscovery = false
    @Published private(set) var errorMessage: String?

    private var homeSignature: String?
    private var discoverySignature: String?

    private init() {}

    func loadHome(apiKey: String, region: String, force: Bool = false) async {
        let signature = "\(apiKey)|\(region)"
        guard !apiKey.isEmpty else {
            homeTrending = []
            homeSignature = nil
            return
        }
        guard force || homeSignature != signature else { return }
        guard !isLoadingHome else { return }
        isLoadingHome = true
        defer { isLoadingHome = false }
        guard let trending = TMDBCollectionDefinition.requestedCollections().first else { return }
        do {
            let metas = try await TMDBClient.shared.collection(
                apiKey: apiKey,
                definition: trending,
                region: region
            )
            guard !metas.isEmpty else { return }
            homeTrending = Array(metas.prefix(10))
            homeSignature = signature
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "TMDB is unavailable."
        }
    }

    func loadDiscovery(apiKey: String, region: String, force: Bool = false) async {
        let signature = "\(apiKey)|\(region)"
        guard !apiKey.isEmpty else {
            shelves = []
            discoverySignature = nil
            return
        }
        guard force || discoverySignature != signature else { return }
        guard !isLoadingDiscovery else { return }
        isLoadingDiscovery = true
        defer { isLoadingDiscovery = false }

        let definitions = TMDBCollectionDefinition.requestedCollections()
        var loaded = Array<[Meta]?>(repeating: nil, count: definitions.count)
        await withTaskGroup(of: (Int, [Meta]).self) { group in
            for (index, definition) in definitions.enumerated() {
                group.addTask {
                    let metas = try? await TMDBClient.shared.collection(
                        apiKey: apiKey,
                        definition: definition,
                        region: region
                    )
                    return (index, metas ?? [])
                }
            }
            for await (index, metas) in group {
                guard index < loaded.count else { continue }
                loaded[index] = metas
            }
        }

        let populated = definitions.enumerated().compactMap { index, definition -> TMDBShelf? in
            guard let metas = loaded[index], !metas.isEmpty else { return nil }
            return TMDBShelf(
                id: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                metas: Array(metas.prefix(24))
            )
        }
        guard !populated.isEmpty else {
            errorMessage = "TMDB did not return any discovery collections."
            return
        }
        shelves = populated
        homeTrending = Array((populated.first { $0.id == "trending-week" }?.metas ?? []).prefix(10))
        homeSignature = signature
        discoverySignature = signature
        errorMessage = nil
    }

    func reset() {
        homeTrending = []
        shelves = []
        homeSignature = nil
        discoverySignature = nil
        errorMessage = nil
    }
}
