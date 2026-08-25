import Foundation

struct StreamResponse: Decodable {
    let streams: [RawStream]

    private enum CodingKeys: String, CodingKey {
        case streams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streams = try container.decodeIfPresent(LossyArray<RawStream>.self, forKey: .streams)?.elements ?? []
    }
}

struct RawStream: Codable {
    let title: String?
    let description: String?
    let url: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: StreamBehaviorHints?
    let sources: [String]?

    /// Set after fetch — which addon produced this stream.
    var addonName: String?
}

struct StreamBehaviorHints: Codable {
    let notWebReady: Bool?
    let bingeGroup: String?
}

enum ResolutionRank: Int {
    case unknown = 0
    case sd = 1
    case hd720 = 2
    case fhd1080 = 3
    case uhd2160 = 4

    var label: String {
        switch self {
        case .unknown: return "?"
        case .sd: return "SD"
        case .hd720: return "720p"
        case .fhd1080: return "1080p"
        case .uhd2160: return "4K"
        }
    }
}

enum HDRKind: String {
    case none
    case hlg = "HLG"
    case hdr10 = "HDR10"
    case hdr10Plus = "HDR10+"
    case dolbyVision = "DV"
}

enum SourceKind: String {
    case unknown
    case remux = "REMUX"
    case bluRay = "BluRay"
    case webDl = "WEB-DL"
    case webRip = "WEBRip"
    case hdtv = "HDTV"
    case cam = "CAM/TS"
}

struct ParsedStream {
    var resolution: ResolutionRank = .unknown
    var hdr: HDRKind = .none
    var audioScore: Int = 0
    var hasAtmos: Bool = false
    var isLosslessAudio: Bool = false
    var source: SourceKind = .unknown
    var codec: String?
    var releaseGroup: String?
    var sizeGB: Double?
    var seeders: Int?
    var isMultiLanguage: Bool = false
    var isJunk: Bool = false
}

struct ScoredStream: Identifiable {
    let id: Int
    let raw: RawStream
    let parsed: ParsedStream
    let score: Int
    let playable: Bool

    var tierLabel: String { parsed.resolution.label }
}
