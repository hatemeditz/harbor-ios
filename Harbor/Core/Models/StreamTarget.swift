import Foundation

/// Navigation value describing "show streams for this title/episode".
struct StreamTarget: Hashable {
    let metaId: String
    let type: String
    let title: String
    let videoId: String?
    let base: String?
    let metaName: String
    let poster: String?
    let background: String?
    let analyticsSource: HarborNavigationSource
    let playbackSessionId: UUID
    let analyticsSeasonNumber: Int?
    let analyticsEpisodeNumber: Int?

    init(
        metaId: String,
        type: String,
        title: String,
        videoId: String?,
        base: String?,
        metaName: String,
        poster: String?,
        background: String?,
        analyticsSource: HarborNavigationSource = .unknown,
        playbackSessionId: UUID = UUID(),
        analyticsSeasonNumber: Int? = nil,
        analyticsEpisodeNumber: Int? = nil
    ) {
        self.metaId = metaId
        self.type = type
        self.title = title
        self.videoId = videoId
        self.base = base
        self.metaName = metaName
        self.poster = poster
        self.background = background
        self.analyticsSource = analyticsSource
        self.playbackSessionId = playbackSessionId
        self.analyticsSeasonNumber = analyticsSeasonNumber
        self.analyticsEpisodeNumber = analyticsEpisodeNumber
    }

    static func == (lhs: StreamTarget, rhs: StreamTarget) -> Bool {
        lhs.metaId == rhs.metaId && lhs.type == rhs.type
            && lhs.videoId == rhs.videoId && lhs.base == rhs.base
            && lhs.playbackSessionId == rhs.playbackSessionId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(metaId)
        hasher.combine(type)
        hasher.combine(videoId)
        hasher.combine(base)
        hasher.combine(playbackSessionId)
    }

    var seasonNumber: Int? { analyticsSeasonNumber ?? episodeCoordinates?.season }
    var episodeNumber: Int? { analyticsEpisodeNumber ?? episodeCoordinates?.episode }

    private var episodeCoordinates: (season: Int, episode: Int)? {
        guard let videoId else { return nil }
        let parts = videoId.split(separator: ":")
        guard parts.count >= 3,
              let season = Int(parts[parts.count - 2]),
              let episode = Int(parts[parts.count - 1])
        else { return nil }
        return (season, episode)
    }
}
