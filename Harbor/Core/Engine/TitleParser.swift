import Foundation

/// Extracts quality signals from torrent/stream titles — a focused port of
/// Harbor's harbor-core parse stage.
enum TitleParser {
    static func parse(title: String?, description: String?) -> ParsedStream {
        var out = ParsedStream()
        let combined = "\(title ?? "") \(description ?? "")".lowercased()

        // Junk filter
        let junkTokens = ["sample", "trailer", "\\bproof\\b", "extras", "-scenelinks", "rarbg.com"]
        for token in junkTokens where combined.range(of: token, options: .regularExpression) != nil {
            out.isJunk = true
            break
        }

        // Resolution
        if combined.range(of: "2160|\\b4k\\b|uhd", options: .regularExpression) != nil {
            out.resolution = .uhd2160
        } else if combined.contains("1080") {
            out.resolution = .fhd1080
        } else if combined.contains("720") {
            out.resolution = .hd720
        } else if combined.range(of: "\\b480p\\b|dvdrip|dvd-r|\\bdvd\\b|\\bdvdr\\b", options: .regularExpression) != nil {
            out.resolution = .sd
        }

        // HDR
        if combined.range(of: "dolby.?vision|\\bdv\\b|dovi", options: .regularExpression) != nil {
            out.hdr = .dolbyVision
        } else if combined.range(of: "hdr10\\+|hdrplus", options: .regularExpression) != nil {
            out.hdr = .hdr10Plus
        } else if combined.range(of: "\\bhdr\\b", options: .regularExpression) != nil {
            out.hdr = .hdr10
        } else if combined.range(of: "\\bhlg\\b", options: .regularExpression) != nil {
            out.hdr = .hlg
        }

        // Audio
        if combined.contains("atmos") {
            out.hasAtmos = true
            out.audioScore += 55
        }
        if combined.range(of: "truehd|true-hd", options: .regularExpression) != nil {
            out.isLosslessAudio = true
            out.audioScore += 45
        }
        if combined.range(of: "dts-?hd(\\b|ma)|dts:x|\\bdtsx\\b", options: .regularExpression) != nil {
            out.isLosslessAudio = true
            out.audioScore += 40
        }
        if combined.range(of: "\\bflac\\b|lossless", options: .regularExpression) != nil {
            out.isLosslessAudio = true
            out.audioScore += 25
        }
        if combined.range(of: "ddp|dd\\+|eac3|dolby digital plus", options: .regularExpression) != nil {
            out.audioScore += 15
        }
        if combined.range(of: "\\bac3\\b|\\bdd5|\\bdd7|5\\.1|7\\.1", options: .regularExpression) != nil {
            out.audioScore += 8
        }

        // Source
        if combined.range(of: "\\bremux\\b", options: .regularExpression) != nil {
            out.source = .remux
        } else if combined.range(of: "blu-?ray|bdrip|brrip|\\bbdmv\\b", options: .regularExpression) != nil {
            out.source = .bluRay
        } else if combined.range(of: "web-?dl|webdl", options: .regularExpression) != nil {
            out.source = .webDl
        } else if combined.range(of: "webrip|web-?rip", options: .regularExpression) != nil {
            out.source = .webRip
        } else if combined.range(of: "\\bhdtv\\b|\\bpdtv\\b", options: .regularExpression) != nil {
            out.source = .hdtv
        } else if combined.range(
            of: "\\bcam\\b|hdcam|\\bts\\b|telesync|\\btc\\b|telecine|screener",
            options: .regularExpression
        ) != nil {
            out.source = .cam
        }

        // Codec
        if combined.range(of: "\\bx265\\b|\\bhevc\\b|\\bh265\\b|\\.h\\.265", options: .regularExpression) != nil {
            out.codec = "HEVC"
        } else if combined.range(of: "\\bx264\\b|\\bavc\\b|\\bh264\\b|\\.h\\.264", options: .regularExpression) != nil {
            out.codec = "AVC"
        } else if combined.range(of: "\\bav1\\b", options: .regularExpression) != nil {
            out.codec = "AV1"
        }

        // Release group — last hyphen-delimited token of the title.
        if let title, let lastHyphen = title.lastIndex(of: "-") {
            let candidate = title[title.index(after: lastHyphen)...].trimmingCharacters(in: .whitespaces)
            if candidate.count >= 2, candidate.count <= 12,
               candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\ ")) == nil {
                out.releaseGroup = candidate.uppercased()
            }
        }

        // Size
        if let match = combined.range(
            of: "[0-9]+(?:\\.[0-9]+)?\\s*(gb|mb)",
            options: .regularExpression
        ) {
            let token = combined[match]
            let parts = token.split(separator: " ")
            if let value = Double(parts.first.map(String.init)?.replacingOccurrences(of: ",", with: ".") ?? "") {
                if token.hasSuffix("gb") || token.hasSuffix("gb.") {
                    out.sizeGB = value
                } else {
                    out.sizeGB = value / 1024.0
                }
            }
        }

        // Seeders
        if let match = combined.range(of: "seeders?:?\\s*([0-9]+)", options: .regularExpression) {
            let digits = combined[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            out.seeders = Int(digits)
        }

        out.isMultiLanguage = combined.range(of: "\\bmulti\\b|dual.?audio", options: .regularExpression) != nil

        return out
    }
}
