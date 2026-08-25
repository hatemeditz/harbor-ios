import Foundation

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
            body: ["authKey": authKey, "type": "user", "update": false]
        )
        return result.addons
    }

    func setAddonCollection(authKey: String, addons: [Addon]) async throws {
        struct SetResult: Decodable { var success: Bool? }
        let raw: [[String: Any]] = addons.map { addon in
            var dict: [String: Any] = [
                "transportUrl": addon.transportUrl,
                "transportName": "",
                "manifest": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(addon.manifest))) as? [String: Any] ?? [:],
            ]
            dict["flags"] = ["official": false, "protected": false]
            return dict
        }
        _ = try await StremioAPI.shared.call(
            "addonCollectionSet",
            body: ["authKey": authKey, "type": "user", "addons": raw]
        ) as SetResult
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
        let url = Self.manifestURL(for: transportUrl)
        struct ManifestResult: Decodable { let manifest: AddonManifest? }
        if let result: ManifestResult = try? await fetchJSON(url), let m = result.manifest {
            return m
        }
        return try await fetchJSON(url)
    }

    static func baseURL(for transportUrl: String) -> String {
        var base = transportUrl
        for suffix in ["/manifest.json", "/manifest"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    static func manifestURL(for transportUrl: String) -> URL {
        URL(string: baseURL(for: transportUrl) + "/manifest.json")!
    }

    static func catalogURL(
        base: String,
        type: String,
        id: String,
        extras: [String: String] = [:]
    ) -> URL {
        var path = "\(baseURL(for: base))/catalog/\(type)/\(id)"
        if !extras.isEmpty {
            let pairs = extras.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")
            path += "/" + pairs
        }
        path += ".json"
        return URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)!
    }

    static func metaURL(base: String, type: String, id: String) -> URL {
        URL(string: "\(baseURL(for: base))/meta/\(type)/\(id).json")!
    }

    static func streamURL(base: String, type: String, id: String) -> URL {
        URL(string: "\(baseURL(for: base))/stream/\(type)/\(id).json")!
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
        let url = Self.catalogURL(base: base, type: type, id: id, extras: extras)
        do {
            let result: CatalogResult = try await fetchJSON(url)
            return result.metas ?? []
        } catch let error as StremioAPIError where error.isNotFound {
            return []
        }
    }

    func metaDetail(base: String?, type: String, id: String) async throws -> Meta? {
        let effectiveBase = base ?? Self.cinemetaBase
        let url = Self.metaURL(base: effectiveBase, type: type, id: id)
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
