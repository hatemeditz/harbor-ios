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
