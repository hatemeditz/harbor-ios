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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-HarborUITestSignedIn") {
            authKey = "harbor-ui-test-session"
            user = StremioUser(
                id: "harbor-ui-test-user",
                email: "viewer@example.invalid",
                fullname: "Harbor Viewer",
                avatar: nil
            )
            return
        }
        #endif

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
        let keyToRevoke = authKey
        clearLocalSession()
        guard let keyToRevoke else { return }
        Task {
            _ = try? await StremioAPI.shared.logout(authKey: keyToRevoke)
        }
    }

    private func clearLocalSession() {
        Keychain.delete(account: Self.authKeyAccount)
        UserDefaults.standard.removeObject(forKey: Self.userCacheKey)
        authKey = nil
        user = nil
        LibraryStore.shared.reset()
        CatalogStore.shared.reset()
        AddonManager.shared.reset()
    }

    private func refreshUser() {
        guard let authKey else { return }
        Task { [weak self] in
            do {
                let fresh = try await StremioAPI.shared.getUser(authKey: authKey)
                guard self?.authKey == authKey else { return }
                self?.user = fresh
                Self.cacheUser(fresh)
            } catch let error as StremioAPIError where error.invalidatesSession {
                guard self?.authKey == authKey else { return }
                self?.clearLocalSession()
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
