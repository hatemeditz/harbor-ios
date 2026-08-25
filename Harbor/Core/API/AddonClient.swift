import Foundation

enum AddonClientError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "The addon URL is invalid. Use a full HTTP or HTTPS manifest URL."
    }
}

final class AddonClient {
    static let shared = AddonClient()
    static let cinemetaBase = "https://v3-cinemeta.strem.io"

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Stremio cloud collection

    func addonCollection(authKey: String) async throws -> [Addon] {
        let result: AddonCollectionResult = try await StremioAPI.shared.call(
            "addonCollectionGet",
            body: ["type": "AddonCollectionGet", "authKey": authKey, "update": true]
        )
        return result.addons
    }

    func setAddonCollection(authKey: String, addons: [Addon]) async throws {
        let raw: [[String: Any]] = try addons.map { addon in
            let encodedManifest = try JSONEncoder().encode(addon.manifest)
            guard let manifest = try JSONSerialization.jsonObject(with: encodedManifest) as? [String: Any] else {
                throw StremioAPIError.decoding
            }
            var dict: [String: Any] = [
                "transportUrl": addon.transportUrl,
                "manifest": manifest,
            ]
            dict["flags"] = [
                "official": addon.flags?.official ?? false,
                "protected": addon.flags?.protected ?? false,
            ]
            return dict
        }
        try await StremioAPI.shared.callIgnoringResult(
            "addonCollectionSet",
            body: ["type": "AddonCollectionSet", "authKey": authKey, "addons": raw]
        )
    }

    // MARK: - Raw addon protocol (GET)

    func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioAPIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func manifest(transportUrl: String) async throws -> AddonManifest {
        let url = try Self.manifestURL(for: transportUrl)
        struct ManifestResult: Decodable { let manifest: AddonManifest? }
        if let result: ManifestResult = try? await fetchJSON(url), let m = result.manifest {
            return m
        }
        return try await fetchJSON(url)
    }

    static func baseURL(for transportUrl: String) -> String {
        var base = transportUrl
        while base.hasSuffix("/") {
            base.removeLast()
        }
        for suffix in ["/manifest.json", "/manifest"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    static func manifestURL(for transportUrl: String) throws -> URL {
        try validatedURL(baseURL(for: transportUrl) + "/manifest.json")
    }

    static func catalogURL(
        base: String,
        type: String,
        id: String,
        extras: [String: String] = [:]
    ) throws -> URL {
        var path = "\(baseURL(for: base))/catalog/\(encodePathValue(type))/\(encodePathValue(id))"
        if !extras.isEmpty {
            let pairs = extras.map {
                "\(encodePathValue($0.key))=\(encodePathValue($0.value))"
            }.sorted().joined(separator: "&")
            path += "/" + pairs
        }
        path += ".json"
        return try validatedURL(path)
    }

    static func metaURL(base: String, type: String, id: String) throws -> URL {
        try validatedURL("\(baseURL(for: base))/meta/\(encodePathValue(type))/\(encodePathValue(id)).json")
    }

    static func streamURL(base: String, type: String, id: String) throws -> URL {
        try validatedURL("\(baseURL(for: base))/stream/\(encodePathValue(type))/\(encodePathValue(id)).json")
    }

    static func subtitlesURL(base: String, type: String, id: String) throws -> URL {
        try validatedURL("\(baseURL(for: base))/subtitles/\(encodePathValue(type))/\(encodePathValue(id)).json")
    }

    private static func encodePathValue(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&=%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func validatedURL(_ string: String) throws -> URL {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            throw AddonClientError.invalidURL
        }
        return url
    }

    struct CatalogResult: Codable {
        let metas: [Meta]?
        let meta: Meta?
    }

    struct MetaDetailResult: Codable {
        let meta: Meta?
    }

    func catalogPage(
        base: String,
        type: String,
        id: String,
        extras: [String: String] = [:]
    ) async throws -> [Meta] {
        let url = try Self.catalogURL(base: base, type: type, id: id, extras: extras)
        do {
            let result: CatalogResult = try await fetchJSON(url)
            return result.metas ?? []
        } catch let error as StremioAPIError where error.isNotFound {
            return []
        }
    }

    func metaDetail(base: String?, type: String, id: String) async throws -> Meta? {
        let effectiveBase = base ?? Self.cinemetaBase
        let url = try Self.metaURL(base: effectiveBase, type: type, id: id)
        do {
            let result: MetaDetailResult = try await fetchJSON(url)
            return result.meta
        } catch let error as StremioAPIError where error.isNotFound {
            return nil
        }
    }
}

extension StremioAPIError {
    var isNotFound: Bool {
        if case .http(let code) = self { return code == 404 }
        return false
    }
}
