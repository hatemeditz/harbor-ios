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

    static func == (lhs: StreamTarget, rhs: StreamTarget) -> Bool {
        lhs.metaId == rhs.metaId && lhs.type == rhs.type
            && lhs.videoId == rhs.videoId && lhs.base == rhs.base
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(metaId)
        hasher.combine(type)
        hasher.combine(videoId)
        hasher.combine(base)
    }
}
