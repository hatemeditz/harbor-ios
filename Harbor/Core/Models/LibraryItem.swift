import Foundation

struct LibraryItem: Codable, Identifiable, Equatable {
    let id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var posterShape: String?
    var removed: Bool
    var temp: Bool
    var ctime: String?
    var mtime: String
    var state: LibraryState?
    var behaviorHints: LibraryBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case name
        case poster
        case background
        case posterShape
        case removed
        case temp
        case ctime = "_ctime"
        case mtime = "_mtime"
        case state
        case behaviorHints
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id && lhs.mtime == rhs.mtime
    }
}

struct LibraryState: Codable, Equatable {
    var timeOffset: Double?
    var duration: Double?
    var timeWatched: Double?
    var overallTimeWatched: Double?
    var timesWatched: Int?
    var flaggedWatched: Double?
    var videoId: String?
    var watched: String?
    var lastWatched: String?
    var season: Int?
    var episode: Int?
    var noNotif: Bool?
    var lastVidReleased: String?

    enum CodingKeys: String, CodingKey {
        case timeOffset
        case duration
        case timeWatched
        case overallTimeWatched
        case timesWatched
        case flaggedWatched
        case videoId = "video_id"
        case watched
        case lastWatched
        case season
        case episode
        case noNotif
        case lastVidReleased
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeOffset = try c.decodeIfPresent(Double.self, forKey: .timeOffset)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        timeWatched = try c.decodeIfPresent(Double.self, forKey: .timeWatched)
        overallTimeWatched = try c.decodeIfPresent(Double.self, forKey: .overallTimeWatched)
        timesWatched = try c.decodeIfPresent(Int.self, forKey: .timesWatched)
        flaggedWatched = try c.decodeIfPresent(Double.self, forKey: .flaggedWatched)
        videoId = try c.decodeIfPresent(String.self, forKey: .videoId)
        watched = try c.decodeIfPresent(String.self, forKey: .watched)
        lastWatched = try c.decodeIfPresent(String.self, forKey: .lastWatched)
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        noNotif = try c.decodeIfPresent(Bool.self, forKey: .noNotif)
        lastVidReleased = try c.decodeIfPresent(String.self, forKey: .lastVidReleased)
    }
}

struct LibraryBehaviorHints: Codable, Equatable {
    var defaultVideoId: String?
    var featuredVideoId: String?
    var hasScheduledVideos: Bool?

    enum CodingKeys: String, CodingKey {
        case defaultVideoId = "defaultVideoId"
        case featuredVideoId = "featuredVideoId"
        case hasScheduledVideos = "hasScheduledVideos"
    }

    init(defaultVideoId: String? = nil, featuredVideoId: String? = nil, hasScheduledVideos: Bool = false) {
        self.defaultVideoId = defaultVideoId
        self.featuredVideoId = featuredVideoId
        self.hasScheduledVideos = hasScheduledVideos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultVideoId = try c.decodeIfPresent(String.self, forKey: .defaultVideoId)
        featuredVideoId = try c.decodeIfPresent(String.self, forKey: .featuredVideoId)
        hasScheduledVideos = try c.decodeIfPresent(Bool.self, forKey: .hasScheduledVideos)
    }
}

extension LibraryItem {
    /// Episode info encoded in a Stremio video_id ("tt123:1:4").
    var episodeFromVideoId: (season: Int, episode: Int)? {
        guard let vid = state?.videoId else { return nil }
        let parts = vid.split(separator: ":")
        guard parts.count >= 3,
              let season = Int(parts[parts.count - 2]),
              let episode = Int(parts[parts.count - 1])
        else { return nil }
        return (season, episode)
    }

    var isContinueWatching: Bool {
        if removed && !temp { return false }
        guard let state else { return false }
        if (state.timeOffset ?? 0) > 0 { return true }
        return false
    }

    var isInWatchlist: Bool {
        !removed && !temp && (state?.timeOffset ?? 0) <= 0 && (state?.flaggedWatched ?? 0) <= 0
    }

    var isWatchedFlagged: Bool {
        (state?.flaggedWatched ?? 0) > 0
    }

    var progressRatio: Double {
        guard let state else { return 0 }
        guard let duration = state.duration, duration > 0 else { return 0 }
        return min(max((state.timeOffset ?? 0) / duration, 0), 1)
    }

    var sortTimestamp: TimeInterval {
        if let lastWatched = state?.lastWatched, let t = Self.parseISO(lastWatched) {
            return t
        }
        return Self.parseISO(mtime) ?? 0
    }

    private static func parseISO(_ string: String) -> TimeInterval? {
        ISO8601DateFormatter().date(from: string)?.timeIntervalSince1970
    }

    func asMeta() -> Meta {
        Meta(
            id: id,
            type: type == "series" ? "series" : "movie",
            name: name,
            poster: poster,
            background: background,
            logo: nil,
            description: nil,
            releaseInfo: nil,
            imdbRating: nil,
            genres: nil,
            runtime: nil,
            country: nil,
            network: nil,
            videos: nil
        )
    }
}
