import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    private static let authKeyAccount = "authKey"
    private static let userCacheKey = "harbor.userCache"

    @Published private(set) var authKey: String?
    @Published private(set) var user: StremioUser?

    var isSignedIn: Bool { authKey != nil }

    private init() {
        authKey = Keychain.string(for: Self.authKeyAccount)
        user = Self.loadCachedUser()
        if authKey != nil {
            refreshUser()
        }
    }

    func signIn(email: String, password: String) async throws {
        let response = try await StremioAPI.shared.login(email: email, password: password)
        Keychain.set(response.authKey, for: Self.authKeyAccount)
        authKey = response.authKey
        user = response.user
        Self.cacheUser(response.user)
    }

    func signOut() {
        if let authKey {
            Task.detached {
                _ = try? await StremioAPI.shared.logout(authKey: authKey)
            }
        }
        Keychain.delete(account: Self.authKeyAccount)
        UserDefaults.standard.removeObject(forKey: Self.userCacheKey)
        authKey = nil
        user = nil
    }

    private func refreshUser() {
        guard let authKey else { return }
        Task.detached { [weak self] in
            guard let fresh = try? await StremioAPI.shared.getUser(authKey: authKey) else { return }
            await MainActor.run {
                self?.user = fresh
                Self.cacheUser(fresh)
            }
        }
    }

    // MARK: - User cache (UserDefaults; non-sensitive profile only)

    private static func cacheUser(_ user: StremioUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userCacheKey)
        }
    }

    private static func loadCachedUser() -> StremioUser? {
        guard let data = UserDefaults.standard.data(forKey: userCacheKey) else { return nil }
        return try? JSONDecoder().decode(StremioUser.self, from: data)
    }
}
