import Foundation

@MainActor
final class SubtitleEngine: ObservableObject {
    @Published private(set) var subtitles: [AddonSubtitle] = []
    @Published private(set) var addonNames: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var loadToken = UUID()

    func load(target: StreamTarget) async {
        let token = UUID()
        loadToken = token
        subtitles = []
        addonNames = []
        errorMessage = nil
        isLoading = true

        let addons = await subtitleAddons(for: target)
        guard loadToken == token else { return }
        addonNames = addons.map(\.displayName)
        guard !addons.isEmpty else {
            isLoading = false
            return
        }

        let videoId = target.videoId ?? target.metaId
        var gathered: [AddonSubtitle] = []
        var reachableAddons = 0

        await withTaskGroup(of: (Addon, [RawSubtitle]?).self) { group in
            for addon in addons {
                group.addTask {
                    do {
                        let response: SubtitleResponse = try await AddonClient.shared.fetchJSON(
                            try AddonClient.subtitlesURL(
                                base: addon.transportUrl,
                                type: target.type,
                                id: videoId
                            )
                        )
                        return (addon, response.subtitles)
                    } catch {
                        return (addon, nil)
                    }
                }
            }

            for await (addon, response) in group {
                guard loadToken == token else { return }
                guard let response else { continue }
                reachableAddons += 1
                for (index, raw) in response.enumerated() where URL(string: raw.url) != nil {
                    let rawId = raw.id ?? String(index)
                    gathered.append(AddonSubtitle(
                        id: "\(addon.id)|\(rawId)|\(index)",
                        raw: raw,
                        addonId: addon.id,
                        addonName: addon.displayName
                    ))
                }
            }
        }

        guard loadToken == token else { return }
        var seen = Set<String>()
        subtitles = gathered.filter { item in
            seen.insert("\(item.languageCode)|\(item.raw.url)").inserted
        }.sorted {
            ($0.languageCode, $0.addonName, $0.displayName)
                < ($1.languageCode, $1.addonName, $1.displayName)
        }
        if reachableAddons == 0 {
            errorMessage = "Your subtitle addons are installed, but none could be reached."
        }
        isLoading = false
    }

    func options(for languageCode: String) -> [AddonSubtitle] {
        let code = SubtitleLanguages.canonicalCode(languageCode)
        return subtitles.filter { $0.languageCode == code }
    }

    func cachedFile(for subtitle: AddonSubtitle) async throws -> URL {
        guard let remoteURL = URL(string: subtitle.raw.url),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { throw AddonClientError.invalidURL }
        return try await SubtitleFileCache.shared.file(for: remoteURL)
    }

    private func subtitleAddons(for target: StreamTarget) async -> [Addon] {
        let all = await CatalogStore.shared.gatherAddons(authKey: AuthStore.shared.authKey)
        return all.filter { addon in
            guard !(addon.manifest.behaviorHints?.configurationRequired ?? false) else { return false }
            let supportsResource = (addon.manifest.resources ?? []).contains { resource in
                switch resource {
                case .named(let name):
                    return name == "subtitles"
                case .detailed(let definition):
                    guard definition.name == "subtitles" else { return false }
                    if let types = definition.types, !types.isEmpty, !types.contains(target.type) {
                        return false
                    }
                    if let prefixes = definition.idPrefixes, !prefixes.isEmpty,
                       !prefixes.contains(where: { target.metaId.hasPrefix($0) }) {
                        return false
                    }
                    return true
                }
            }
            guard supportsResource else { return false }
            if let types = addon.manifest.types, !types.isEmpty, !types.contains(target.type) {
                return false
            }
            if let prefixes = addon.manifest.idPrefixes, !prefixes.isEmpty,
               !prefixes.contains(where: { target.metaId.hasPrefix($0) }) {
                return false
            }
            return true
        }
    }
}

private actor SubtitleFileCache {
    static let shared = SubtitleFileCache()

    private var files: [URL: URL] = [:]

    func file(for remoteURL: URL) async throws -> URL {
        if let cached = files[remoteURL], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioAPIError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw StremioAPIError.decoding }

        let supported = ["srt", "vtt", "ass", "ssa", "sub"]
        let remoteExtension = remoteURL.pathExtension.lowercased()
        let fileExtension = supported.contains(remoteExtension) ? remoteExtension : "srt"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarborSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let localURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: localURL, options: .atomic)
        files[remoteURL] = localURL
        return localURL
    }
}
