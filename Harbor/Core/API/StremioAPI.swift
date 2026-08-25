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
}

final class StremioAPI {
    static let shared = StremioAPI()
    private let base = URL(string: "https://api.strem.io/api")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Generic call

    private struct Envelope<Result: Decodable>: Decodable {
        let result: Result?
        let error: ServerError?

        struct ServerError: Decodable {
            let message: String?
        }
    }

    func call<Result: Decodable>(_ path: String, body: [String: Any]) async throws -> Result {
        guard let url = URL(string: path, relativeTo: base) else {
            throw StremioAPIError.http(-1)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StremioAPIError.http(http.statusCode)
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Result>.self, from: data)
            if let message = envelope.error?.message {
                throw StremioAPIError.server(message)
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
        let _: EmptyResult = try await call("logout", body: ["authKey": authKey])
    }

    struct EmptyResult: Decodable {}
}
