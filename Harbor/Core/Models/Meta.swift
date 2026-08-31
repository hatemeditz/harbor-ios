import Foundation

struct Meta: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let runtime: String?
    let country: String?
    let network: String?
    let videos: [MetaVideo]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
    }

    static func == (lhs: Meta, rhs: Meta) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type
    }
}

struct MetaVideo: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let title: String?
    let season: Int?
    let episode: Int?
    let released: Date?
    let thumbnail: String?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case season
        case episode
        case released
        case thumbnail
        case description
        case overview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        if let str = try c.decodeIfPresent(String.self, forKey: .released) {
            released = Self.parseDate(str)
        } else {
            released = nil
        }
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        overview = try c.decodeIfPresent(String.self, forKey: .description)
            ?? c.decodeIfPresent(String.self, forKey: .overview)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(episode, forKey: .episode)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try c.encodeIfPresent(overview, forKey: .description)
    }

    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) {
            return date
        }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: string)
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let name, !name.isEmpty { return name }
        if let season, let episode { return "S\(season)E\(episode)" }
        return id
    }

    var episodeNumber: Int? { episode }
    var seasonNumber: Int? { season }
}

/// Navigation payload carrying the originating addon base so detail can fetch
/// meta from the right source (falls back to Cinemeta).
struct MetaNavigation: Hashable {
    let meta: Meta
    let base: String?
    let source: HarborNavigationSource

    init(meta: Meta, base: String?, source: HarborNavigationSource = .unknown) {
        self.meta = meta
        self.base = base
        self.source = source
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(meta.id)
        hasher.combine(meta.type)
        hasher.combine(source)
    }

    static func == (lhs: MetaNavigation, rhs: MetaNavigation) -> Bool {
        lhs.meta.id == rhs.meta.id && lhs.meta.type == rhs.meta.type && lhs.source == rhs.source
    }
}
