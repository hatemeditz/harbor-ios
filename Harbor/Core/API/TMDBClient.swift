import Foundation

enum TMDBMediaKind: String, CaseIterable, Sendable {
    case movie
    case series = "tv"

    var harborType: String {
        switch self {
        case .movie: return "movie"
        case .series: return "series"
        }
    }
}

struct TMDBStreamingProvider: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let providerIDs: [Int]
    let tintHex: String
    let shortMark: String

    static let all: [TMDBStreamingProvider] = [
        .init(id: "netflix", name: "Netflix", providerIDs: [8], tintHex: "E50914", shortMark: "N"),
        .init(id: "disney", name: "Disney+", providerIDs: [337], tintHex: "0E47A1", shortMark: "D+"),
        .init(id: "prime", name: "Prime Video", providerIDs: [9, 119], tintHex: "00A8E1", shortMark: "prime"),
        .init(id: "apple", name: "Apple TV+", providerIDs: [350], tintHex: "FFFFFF", shortMark: "tv+"),
        .init(id: "max", name: "Max", providerIDs: [1899, 384], tintHex: "9B6CFF", shortMark: "max"),
        .init(id: "hulu", name: "Hulu", providerIDs: [15], tintHex: "1CE783", shortMark: "hulu"),
    ]
}

struct TMDBServiceCatalog {
    let movies: [Meta]
    let series: [Meta]
}

struct TMDBCollectionDefinition: Identifiable, Sendable {
    enum Endpoint: Sendable {
        case trendingAll
        case topRated(TMDBMediaKind)
        case discover(TMDBMediaKind)
    }

    let id: String
    let title: String
    let subtitle: String
    let endpoint: Endpoint
    let parameters: [String: String]

    static func requestedCollections(now: Date = Date()) -> [TMDBCollectionDefinition] {
        let recentDocumentaryStart = dateString(daysFrom: now, offset: -540)
        let recentDramaStart = dateString(daysFrom: now, offset: -365)
        let today = dateString(daysFrom: now, offset: 0)

        return [
            .init(
                id: "trending-week",
                title: "Trending This Week",
                subtitle: "What people are watching now",
                endpoint: .trendingAll,
                parameters: [:]
            ),
            .init(
                id: "top-rated",
                title: "Top Rated",
                subtitle: "The audience favorites",
                endpoint: .topRated(.movie),
                parameters: [:]
            ),
            .init(
                id: "award-winning",
                title: "Award Winning",
                subtitle: "Acclaimed modern cinema",
                endpoint: .discover(.movie),
                parameters: [
                    "vote_average.gte": "8.0",
                    "vote_count.gte": "2500",
                    "sort_by": "vote_average.desc",
                ]
            ),
            .init(
                id: "top-history",
                title: "Top Rated History",
                subtitle: "Remarkable stories from the past",
                endpoint: .discover(.movie),
                parameters: [
                    "with_genres": "36",
                    "vote_average.gte": "7.2",
                    "vote_count.gte": "300",
                    "sort_by": "vote_average.desc",
                ]
            ),
            .init(
                id: "new-documentary-series",
                title: "New Documentary Series",
                subtitle: "Recent real stories",
                endpoint: .discover(.series),
                parameters: [
                    "with_genres": "99",
                    "first_air_date.gte": recentDocumentaryStart,
                    "first_air_date.lte": today,
                    "vote_count.gte": "20",
                    "sort_by": "popularity.desc",
                ]
            ),
            .init(
                id: "top-action",
                title: "Top Rated Action",
                subtitle: "Big-screen adrenaline",
                endpoint: .discover(.movie),
                parameters: [
                    "with_genres": "28",
                    "vote_average.gte": "7.2",
                    "vote_count.gte": "1200",
                    "sort_by": "vote_average.desc",
                ]
            ),
            .init(
                id: "new-drama",
                title: "New in Drama",
                subtitle: "Fresh dramatic releases",
                endpoint: .discover(.movie),
                parameters: [
                    "with_genres": "18",
                    "primary_release_date.gte": recentDramaStart,
                    "primary_release_date.lte": today,
                    "vote_count.gte": "75",
                    "sort_by": "popularity.desc",
                ]
            ),
            .init(
                id: "adventure-scifi",
                title: "Adventure + Sci-Fi",
                subtitle: "Journeys beyond the known",
                endpoint: .discover(.movie),
                parameters: [
                    "with_genres": "12|878",
                    "vote_average.gte": "6.8",
                    "vote_count.gte": "800",
                    "sort_by": "popularity.desc",
                ]
            ),
            .init(
                id: "best-80s",
                title: "Best of the 80s",
                subtitle: "Essentials from 1980–1989",
                endpoint: .discover(.movie),
                parameters: [
                    "primary_release_date.gte": "1980-01-01",
                    "primary_release_date.lte": "1989-12-31",
                    "vote_average.gte": "7.2",
                    "vote_count.gte": "500",
                    "sort_by": "vote_count.desc",
                ]
            ),
            .init(
                id: "documentary-animation",
                title: "Documentary + Animation",
                subtitle: "True stories, illustrated",
                endpoint: .discover(.movie),
                parameters: [
                    "with_genres": "99|16",
                    "vote_count.gte": "30",
                    "sort_by": "popularity.desc",
                ]
            ),
            .init(
                id: "cult-classics",
                title: "Cult Classics",
                subtitle: "Beloved and unforgettable",
                endpoint: .discover(.movie),
                parameters: [
                    "primary_release_date.lte": "2005-12-31",
                    "vote_average.gte": "7.5",
                    "vote_count.gte": "600",
                    "sort_by": "vote_count.desc",
                ]
            ),
        ]
    }

    private static func dateString(daysFrom date: Date, offset: Int) -> String {
        let adjusted = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) ?? date
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: adjusted)
    }
}

enum TMDBClientError: LocalizedError {
    case invalidKey
    case invalidURL
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Enter a valid TMDB v3 API key."
        case .invalidURL: return "Harbor could not create the TMDB request."
        case .invalidResponse: return "TMDB returned an unreadable response."
        case .http(401): return "TMDB rejected this API key."
        case .http(429): return "TMDB is temporarily rate limiting requests."
        case .http(let code): return "TMDB request failed (HTTP \(code))."
        }
    }
}

final class TMDBClient: @unchecked Sendable {
    static let shared = TMDBClient()

    private static let apiBase = "https://api.themoviedb.org/3"
    private static let imageBase = "https://image.tmdb.org/t/p"

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    func validate(apiKey: String) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TMDBClientError.invalidKey }
        let _: TMDBConfiguration = try await request(path: "configuration", apiKey: trimmed)
    }

    func collection(
        apiKey: String,
        definition: TMDBCollectionDefinition,
        region: String
    ) async throws -> [Meta] {
        let effectiveRegion = Self.normalizedRegion(region)
        switch definition.endpoint {
        case .trendingAll:
            let page: TMDBPage<TMDBCatalogItem> = try await request(
                path: "trending/all/week",
                apiKey: apiKey,
                parameters: ["page": "1"]
            )
            return page.results.compactMap { item in
                guard let kind = item.resolvedKind else { return nil }
                return item.meta(kind: kind)
            }
        case .topRated(let kind):
            let page: TMDBPage<TMDBCatalogItem> = try await request(
                path: "\(kind.rawValue)/top_rated",
                apiKey: apiKey,
                parameters: ["page": "1", "region": effectiveRegion]
            )
            return page.results.compactMap { $0.meta(kind: kind) }
        case .discover(let kind):
            var parameters = definition.parameters
            parameters["page"] = "1"
            parameters["include_adult"] = "false"
            if kind == .movie { parameters["region"] = effectiveRegion }
            let page: TMDBPage<TMDBCatalogItem> = try await request(
                path: "discover/\(kind.rawValue)",
                apiKey: apiKey,
                parameters: parameters
            )
            return page.results.compactMap { $0.meta(kind: kind) }
        }
    }

    func serviceCatalog(
        apiKey: String,
        provider: TMDBStreamingProvider,
        region: String,
        page: Int = 1
    ) async throws -> TMDBServiceCatalog {
        let effectiveRegion = Self.normalizedRegion(region)
        let providerIDs = provider.providerIDs.map(String.init).joined(separator: "|")
        let common = [
            "page": String(page),
            "sort_by": "popularity.desc",
            "vote_count.gte": "100",
            "watch_region": effectiveRegion,
            "with_watch_monetization_types": "flatrate",
            "with_watch_providers": providerIDs,
        ]
        async let moviePage: TMDBPage<TMDBCatalogItem> = request(
            path: "discover/movie",
            apiKey: apiKey,
            parameters: common.merging(["region": effectiveRegion]) { current, _ in current }
        )
        async let seriesPage: TMDBPage<TMDBCatalogItem> = request(
            path: "discover/tv",
            apiKey: apiKey,
            parameters: common
        )
        let (movies, series) = try await (moviePage, seriesPage)
        return TMDBServiceCatalog(
            movies: movies.results.compactMap { $0.meta(kind: .movie) },
            series: series.results.compactMap { $0.meta(kind: .series) }
        )
    }

    func detailMeta(apiKey: String, meta: Meta) async throws -> Meta {
        guard let reference = TMDBReference(metaID: meta.id) else { return meta }
        let detail: TMDBDetail = try await request(
            path: "\(reference.kind.rawValue)/\(reference.id)",
            apiKey: apiKey,
            parameters: ["append_to_response": "external_ids"]
        )
        let stableID = detail.externalIDs?.imdbID.flatMap { $0.isEmpty ? nil : $0 } ?? meta.id
        var videos: [MetaVideo]? = meta.videos
        if reference.kind == .series {
            videos = await seriesVideos(
                apiKey: apiKey,
                tmdbID: reference.id,
                stableSeriesID: stableID,
                seasons: detail.seasons ?? []
            )
        }
        return Meta(
            id: stableID,
            type: reference.kind.harborType,
            name: detail.title ?? detail.name ?? meta.name,
            poster: Self.imageURL(detail.posterPath, size: "w500") ?? meta.poster,
            background: Self.imageURL(detail.backdropPath, size: "w1280") ?? meta.background,
            logo: meta.logo,
            description: detail.overview ?? meta.description,
            releaseInfo: Self.year(detail.releaseDate ?? detail.firstAirDate) ?? meta.releaseInfo,
            imdbRating: Self.rating(detail.voteAverage) ?? meta.imdbRating,
            genres: detail.genres?.map(\.name) ?? meta.genres,
            runtime: Self.runtime(detail.runtime ?? detail.episodeRunTime?.first) ?? meta.runtime,
            country: detail.originCountry?.first ?? meta.country,
            network: detail.networks?.first?.name ?? meta.network,
            videos: videos
        )
    }

    private func seriesVideos(
        apiKey: String,
        tmdbID: Int,
        stableSeriesID: String,
        seasons: [TMDBSeasonSummary]
    ) async -> [MetaVideo] {
        let seasonNumbers = seasons
            .map(\.seasonNumber)
            .filter { $0 > 0 }
            .prefix(30)
        return await withTaskGroup(of: [MetaVideo].self) { group in
            for seasonNumber in seasonNumbers {
                group.addTask { [self] in
                    guard let season: TMDBSeasonDetail = try? await request(
                        path: "tv/\(tmdbID)/season/\(seasonNumber)",
                        apiKey: apiKey
                    ) else { return [] }
                    return season.episodes.map { episode in
                        MetaVideo(
                            id: "\(stableSeriesID):\(seasonNumber):\(episode.episodeNumber)",
                            name: episode.name,
                            title: episode.name,
                            season: seasonNumber,
                            episode: episode.episodeNumber,
                            released: Self.date(episode.airDate),
                            thumbnail: Self.imageURL(episode.stillPath, size: "w780"),
                            overview: episode.overview
                        )
                    }
                }
            }
            var all: [MetaVideo] = []
            for await season in group { all += season }
            return all.sorted {
                ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0)
            }
        }
    }

    private func request<T: Decodable>(
        path: String,
        apiKey: String,
        parameters: [String: String] = [:]
    ) async throws -> T {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw TMDBClientError.invalidKey }
        guard var components = URLComponents(string: "\(Self.apiBase)/\(path)") else {
            throw TMDBClientError.invalidURL
        }
        var query = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        query.append(URLQueryItem(name: "api_key", value: trimmedKey))
        components.queryItems = query.sorted { $0.name < $1.name }
        guard let url = components.url else { throw TMDBClientError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TMDBClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw TMDBClientError.http(http.statusCode) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TMDBClientError.invalidResponse
        }
    }

    fileprivate static func imageURL(_ path: String?, size: String) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return "\(imageBase)/\(size)\(path)"
    }

    fileprivate static func year(_ value: String?) -> String? {
        guard let value, value.count >= 4 else { return nil }
        return String(value.prefix(4))
    }

    fileprivate static func rating(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return String(format: "%.1f", value)
    }

    private static func runtime(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func normalizedRegion(_ region: String) -> String {
        region.uppercased() == "UK" ? "GB" : region.uppercased()
    }
}

private struct TMDBReference {
    let kind: TMDBMediaKind
    let id: Int

    init?(metaID: String) {
        let components = metaID.split(separator: ":")
        guard components.count == 3,
              components[0] == "tmdb",
              let kind = TMDBMediaKind(rawValue: String(components[1])),
              let id = Int(components[2])
        else { return nil }
        self.kind = kind
        self.id = id
    }
}

private struct TMDBConfiguration: Decodable {}

private struct TMDBPage<Item: Decodable>: Decodable {
    let results: [Item]
}

private struct TMDBCatalogItem: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIDs: [Int]?
    let originCountry: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
        case originCountry = "origin_country"
    }

    var resolvedKind: TMDBMediaKind? {
        switch mediaType {
        case "movie": return .movie
        case "tv": return .series
        default: return nil
        }
    }

    func meta(kind: TMDBMediaKind) -> Meta? {
        guard let displayName = title ?? name, !displayName.isEmpty else { return nil }
        return Meta(
            id: "tmdb:\(kind.rawValue):\(id)",
            type: kind.harborType,
            name: displayName,
            poster: TMDBClient.imageURL(posterPath, size: "w500"),
            background: TMDBClient.imageURL(backdropPath, size: "w1280"),
            logo: nil,
            description: overview,
            releaseInfo: TMDBClient.year(releaseDate ?? firstAirDate),
            imdbRating: TMDBClient.rating(voteAverage),
            genres: genreIDs?.compactMap { TMDBGenre.name(id: $0, kind: kind) },
            runtime: nil,
            country: originCountry?.first,
            network: nil,
            videos: nil
        )
    }
}

private enum TMDBGenre {
    private static let movie: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        53: "Thriller", 10752: "War", 37: "Western",
    ]
    private static let series: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery",
        10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
        10767: "Talk", 10768: "War & Politics", 37: "Western",
    ]

    static func name(id: Int, kind: TMDBMediaKind) -> String? {
        kind == .movie ? movie[id] : series[id]
    }
}

private struct TMDBDetail: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let originCountry: [String]?
    let genres: [TMDBNamedValue]?
    let networks: [TMDBNamedValue]?
    let seasons: [TMDBSeasonSummary]?
    let externalIDs: TMDBExternalIDs?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, runtime, genres, networks, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case episodeRunTime = "episode_run_time"
        case originCountry = "origin_country"
        case externalIDs = "external_ids"
    }
}

private struct TMDBNamedValue: Decodable {
    let name: String
}

private struct TMDBExternalIDs: Decodable {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

private struct TMDBSeasonSummary: Decodable {
    let seasonNumber: Int

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
    }
}

private struct TMDBSeasonDetail: Decodable {
    let episodes: [TMDBEpisode]
}

private struct TMDBEpisode: Decodable {
    let episodeNumber: Int
    let name: String?
    let overview: String?
    let airDate: String?
    let stillPath: String?

    enum CodingKeys: String, CodingKey {
        case name, overview
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case stillPath = "still_path"
    }
}
