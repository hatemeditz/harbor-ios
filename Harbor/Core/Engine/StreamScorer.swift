import Foundation

/// Trust + score + rank — a focused port of Harbor's harbor-core pipeline.
enum StreamScorer {
    static func score(raw: RawStream, id: Int) -> ScoredStream? {
        let parsed = TitleParser.parse(title: raw.title, description: raw.description)

        // Hard trust rejections.
        if parsed.isJunk { return nil }
        if let url = raw.url, url.isEmpty, raw.infoHash == nil { return nil }
        if raw.url == nil && raw.infoHash == nil { return nil }

        var score = 0
        var playable = false

        switch parsed.resolution {
        case .uhd2160: score += 400
        case .fhd1080: score += 300
        case .hd720: score += 200
        case .sd: score += 90
        case .unknown: score += 60
        }

        switch parsed.hdr {
        case .dolbyVision: score += 85
        case .hdr10Plus: score += 80
        case .hdr10: score += 60
        case .hlg: score += 45
        case .none: break
        }

        score += min(parsed.audioScore, 120)

        switch parsed.source {
        case .remux: score += 70
        case .bluRay: score += 55
        case .webDl: score += 50
        case .webRip: score += 25
        case .hdtv: score += 12
        case .cam: score -= 350
        case .unknown: break
        }

        if let value = raw.url,
           let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            // `notWebReady` is a browser-player hint. Harbor uses native VLC,
            // so a valid direct HTTP(S) URL from a debrid addon is playable.
            playable = true
            score += 150
        } else if let hash = raw.infoHash, !hash.isEmpty {
            // Debrid-resolvable only when the addon returned a URL; bare hashes
            // are listed but not directly playable on iOS.
            playable = false
            score += 20
        }

        if let seeders = parsed.seeders {
            score += Int(min(log10(Double(seeders + 1)) * 30, 90))
        }

        if let size = parsed.sizeGB {
            // Plausibility window per resolution.
            let plausible: ClosedRange<Double>
            switch parsed.resolution {
            case .uhd2160: plausible = 8...95
            case .fhd1080: plausible = 1.2...25
            case .hd720: plausible = 0.5...8
            default: plausible = 0.2...4
            }
            score += plausible.contains(size) ? 25 : -40
        }

        if parsed.isMultiLanguage { score += 10 }

        return ScoredStream(
            id: id,
            raw: withAddonName(raw),
            parsed: parsed,
            score: score,
            playable: playable
        )
    }

    private static func withAddonName(_ raw: RawStream) -> RawStream {
        var copy = raw
        if copy.addonName == nil { copy.addonName = "Addon" }
        return copy
    }

    static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        // Strip leading "[addon] " prefixes some addons add.
        if cleaned.hasPrefix("[") , let close = cleaned.firstIndex(of: "]") {
            cleaned = String(cleaned[cleaned.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return cleaned.isEmpty ? title : cleaned
    }

    static func sort(_ streams: [ScoredStream]) -> [ScoredStream] {
        streams.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.parsed.resolution.rawValue > $1.parsed.resolution.rawValue
        }
    }
}
