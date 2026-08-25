import Foundation

enum StremioAPIError: LocalizedError {
    case http(Int)
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Network error (\(code))"
        case .server(let message): return message
        case .decoding: return "Unexpected response from Stremio."
        }
    }

    var invalidatesSession: Bool {
        switch self {
        case .http(let code):
            return code == 401 || code == 403
        case .server(let message):
            let normalized = message.lowercased()
            return normalized.contains("session does not exist")
                || normalized.contains("invalid auth")
                || normalized.contains("invalid session")
        case .decoding:
            return false
        }
    }
}

final class StremioAPI {
    static let shared = StremioAPI()
    private let base = URL(string: "https://api.strem.io/api")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Generic call

    private struct ServerError: Decodable {
        let code: Int?
        let message: String?
    }

    private struct Envelope<Result: Decodable>: Decodable {
        let result: Result?
        let error: ServerError?
    }

    private struct IgnoredEnvelope: Decodable {
        let error: ServerError?
        let hasResult: Bool

        private enum CodingKeys: String, CodingKey {
            case result
            case error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.decodeIfPresent(ServerError.self, forKey: .error)
            hasResult = container.contains(.result)
        }
    }

    private func request(_ path: String, body: [String: Any]) async throws -> Data {
        // appendingPathComponent is intentional here. A relative URL resolves
        // "login" against /api as a sibling (/login), which Stremio answers
        // with 404; the API endpoints live below /api (/api/login).
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioAPIError.http(http.statusCode)
        }
        return data
    }

    func call<Result: Decodable>(_ path: String, body: [String: Any]) async throws -> Result {
        let data = try await request(path, body: body)
        do {
            let envelope = try JSONDecoder().decode(Envelope<Result>.self, from: data)
            if let error = envelope.error {
                throw StremioAPIError.server(error.message ?? "Stremio request failed.")
            }
            guard let result = envelope.result else {
                throw StremioAPIError.decoding
            }
            return result
        } catch let error as StremioAPIError {
            throw error
        } catch {
            throw StremioAPIError.decoding
        }
    }

    func callIgnoringResult(_ path: String, body: [String: Any]) async throws {
        let data = try await request(path, body: body)
        do {
            let envelope = try JSONDecoder().decode(IgnoredEnvelope.self, from: data)
            if let error = envelope.error {
                throw StremioAPIError.server(error.message ?? "Stremio request failed.")
            }
            guard envelope.hasResult else {
                throw StremioAPIError.decoding
            }
        } catch let error as StremioAPIError {
            throw error
        } catch {
            throw StremioAPIError.decoding
        }
    }

    // MARK: - Endpoints

    func login(email: String, password: String) async throws -> LoginResponse {
        try await call("login", body: [
            "email": email,
            "password": password,
            "facebook": false,
        ])
    }

    func getUser(authKey: String) async throws -> StremioUser {
        try await call("getUser", body: ["authKey": authKey])
    }

    func logout(authKey: String) async throws {
        try await callIgnoringResult("logout", body: ["authKey": authKey])
    }
}
