import Foundation

struct SubtitleResponse: Decodable {
    let subtitles: [RawSubtitle]

    private enum CodingKeys: String, CodingKey {
        case subtitles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = try container.decodeIfPresent(LossyArray<RawSubtitle>.self, forKey: .subtitles)?.elements ?? []
    }
}

struct RawSubtitle: Decodable, Hashable {
    let id: String?
    let url: String
    let lang: String
    let subtitleFileName: String?
    let movieReleaseName: String?
}

struct AddonSubtitle: Identifiable, Hashable {
    let id: String
    let raw: RawSubtitle
    let addonId: String
    let addonName: String

    var languageCode: String {
        SubtitleLanguages.canonicalCode(raw.lang)
    }

    var displayName: String {
        raw.subtitleFileName ?? raw.movieReleaseName ?? raw.id ?? "Subtitle"
    }
}

enum SubtitleLanguages {
    private static let iso3To2: [String: String] = [
        "alb": "sq", "sqi": "sq", "ara": "ar", "arm": "hy", "hye": "hy",
        "baq": "eu", "eus": "eu", "ben": "bn", "bos": "bs", "bul": "bg",
        "cat": "ca", "chi": "zh", "zho": "zh", "cze": "cs", "ces": "cs",
        "dan": "da", "dut": "nl", "nld": "nl", "eng": "en", "est": "et", "fin": "fi",
        "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "gre": "el",
        "ell": "el", "geo": "ka", "kat": "ka", "glg": "gl", "heb": "he",
        "hin": "hi", "hrv": "hr", "scr": "hr", "hun": "hu", "ice": "is",
        "isl": "is", "ind": "id", "ita": "it", "jpn": "ja", "kaz": "kk",
        "kor": "ko", "kur": "ku", "lav": "lv", "lit": "lt", "mac": "mk",
        "mkd": "mk", "may": "ms", "msa": "ms", "nor": "no", "per": "fa",
        "fas": "fa", "pol": "pl",
        "por": "pt", "pob": "pt-BR", "rum": "ro", "ron": "ro", "rus": "ru",
        "scc": "sr", "slo": "sk", "slk": "sk", "slv": "sl", "spa": "es", "srp": "sr",
        "swe": "sv", "tha": "th", "tur": "tr", "ukr": "uk", "vie": "vi",
    ]

    static func canonicalCode(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        let lowered = normalized.lowercased()
        if let mapped = iso3To2[lowered] { return mapped }
        if lowered.count == 2 { return lowered }
        let parts = lowered.split(separator: "-")
        if parts.count >= 2, parts[0].count == 2, parts[1].count == 2 {
            return "\(parts[0])-\(parts[1].uppercased())"
        }
        if let first = parts.first {
            let base = String(first)
            if let mapped = iso3To2[base] { return mapped }
            if base.count == 2 { return base }
        }
        return lowered
    }

    static func displayName(for code: String) -> String {
        let canonical = canonicalCode(code)
        if let localized = Locale.current.localizedString(forLanguageCode: canonical) {
            return localized.capitalized
        }
        return canonical.uppercased()
    }

    static func code(forTrackName name: String) -> String? {
        let lowered = name.lowercased()
        guard !lowered.contains("disable"), !lowered.contains("off") else { return nil }

        let candidates = Set(iso3To2.values).union(iso3To2.keys)
        for candidate in candidates {
            let canonical = canonicalCode(candidate)
            let localized = displayName(for: canonical).lowercased()
            let baseCode = canonical.components(separatedBy: "-").first ?? canonical
            let english = Locale(identifier: "en").localizedString(
                forLanguageCode: baseCode
            )?.lowercased()
            if lowered.contains(localized) || (english.map { lowered.contains($0) } ?? false)
                || containsToken(candidate, in: lowered)
                || containsToken(canonical, in: lowered) {
                return canonical
            }
        }
        return nil
    }

    private static func containsToken(_ token: String, in value: String) -> Bool {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains(token.lowercased())
    }
}
