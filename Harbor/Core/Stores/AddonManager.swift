import SwiftUI

@MainActor
final class AddonManager: ObservableObject {
    static let shared = AddonManager()

    /// Cloud-only collection (no synthesized Cinemeta).
    @Published var cloudAddons: [Addon] = []
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private init() {}

    var syncedStreamAddons: [Addon] {
        cloudAddons.filter { addon in
            !(addon.manifest.behaviorHints?.configurationRequired ?? false)
                && (addon.manifest.resources ?? []).contains { $0.typeName == "stream" }
        }
    }

    var syncedSubtitleAddons: [Addon] {
        cloudAddons.filter { addon in
            !(addon.manifest.behaviorHints?.configurationRequired ?? false)
                && (addon.manifest.resources ?? []).contains { $0.typeName == "subtitles" }
        }
    }

    func hasEmbeddedDebridConfiguration(_ addon: Addon) -> Bool {
        let transport = (addon.transportUrl.removingPercentEncoding ?? addon.transportUrl).lowercased()
        return DebridProvider.allCases.contains { transport.contains("\($0.queryName)=") }
    }

    func applySyncedAddons(_ addons: [Addon], authKey: String) {
        guard AuthStore.shared.authKey == authKey else { return }
        cloudAddons = addons
        errorMessage = nil
    }

    func reset() {
        cloudAddons = []
        isLoading = false
        statusMessage = nil
        errorMessage = nil
    }

    func reload(authKey: String) async {
        guard AuthStore.shared.authKey == authKey else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer {
            if AuthStore.shared.authKey == authKey {
                isLoading = false
            }
        }
        do {
            let loaded = try await AddonClient.shared.addonCollection(authKey: authKey)
            guard AuthStore.shared.authKey == authKey else { return }
            cloudAddons = loaded
            CatalogStore.shared.invalidate()
        } catch {
            guard AuthStore.shared.authKey == authKey else { return }
            errorMessage = error.localizedDescription
        }
    }

    func remove(authKey: String, addon: Addon) async {
        guard AuthStore.shared.authKey == authKey, isRemovable(addon) else { return }
        errorMessage = nil
        statusMessage = nil
        let updated = cloudAddons.filter { $0.id != addon.id }
        do {
            try await AddonClient.shared.setAddonCollection(authKey: authKey, addons: updated)
            guard AuthStore.shared.authKey == authKey else { return }
            cloudAddons = updated
            statusMessage = "Removed \(addon.displayName)"
            CatalogStore.shared.invalidate()
        } catch {
            guard AuthStore.shared.authKey == authKey else { return }
            errorMessage = error.localizedDescription
        }
    }

    func installFromURL(authKey: String, rawURL: String) async -> Bool {
        guard AuthStore.shared.authKey == authKey else { return false }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host != nil
        else {
            errorMessage = "Enter a full manifest URL (https://…)"
            return false
        }
        let transportURL = AddonClient.baseURL(for: trimmed) + "/manifest.json"
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer {
            if AuthStore.shared.authKey == authKey {
                isLoading = false
            }
        }
        do {
            let manifest = try await AddonClient.shared.manifest(transportUrl: transportURL)
            guard AuthStore.shared.authKey == authKey else { return false }
            var updated = cloudAddons.filter {
                AddonClient.baseURL(for: $0.transportUrl) != AddonClient.baseURL(for: transportURL)
            }
            updated.append(
                Addon(
                    transportUrl: transportURL,
                    manifest: manifest,
                    flags: AddonFlags(official: false, protected: false)
                )
            )
            try await AddonClient.shared.setAddonCollection(authKey: authKey, addons: updated)
            guard AuthStore.shared.authKey == authKey else { return false }
            cloudAddons = updated
            statusMessage = "Installed \(manifest.name)"
            CatalogStore.shared.invalidate()
            return true
        } catch {
            guard AuthStore.shared.authKey == authKey else { return false }
            errorMessage = "Could not load manifest: \(error.localizedDescription)"
            return false
        }
    }

    func installTorrentio(authKey: String) async -> Bool {
        guard AuthStore.shared.authKey == authKey else { return false }
        let configParts = DebridProvider.allCases.compactMap { provider -> String? in
            guard let key = DebridProvider.loadKey(provider), !key.isEmpty else { return nil }
            return "\(provider.queryName)=\(key.trimmingCharacters(in: .whitespaces))"
        }
        let base = "https://torrentio.strem.fun"
        let transportUrl = configParts.isEmpty ? base + "/manifest.json" : base + "/" + configParts.joined(separator: "|") + "/manifest.json"

        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer {
            if AuthStore.shared.authKey == authKey {
                isLoading = false
            }
        }
        do {
            let manifest = try await AddonClient.shared.manifest(transportUrl: transportUrl)
            guard AuthStore.shared.authKey == authKey else { return false }
            var updated = cloudAddons.filter {
                !$0.transportUrl.lowercased().contains("torrentio.strem.fun")
            }
            updated.append(
                Addon(
                    transportUrl: transportUrl,
                    manifest: manifest,
                    flags: AddonFlags(official: false, protected: false)
                )
            )
            try await AddonClient.shared.setAddonCollection(authKey: authKey, addons: updated)
            guard AuthStore.shared.authKey == authKey else { return false }
            cloudAddons = updated
            statusMessage = configParts.isEmpty
                ? "Installed Torrentio (no debrid keys)"
                : "Installed Torrentio with \(configParts.count) debrid key(s)"
            CatalogStore.shared.invalidate()
            return true
        } catch {
            guard AuthStore.shared.authKey == authKey else { return false }
            errorMessage = "Torrentio install failed: \(error.localizedDescription)"
            return false
        }
    }

    func isRemovable(_ addon: Addon) -> Bool {
        !(addon.flags?.protected ?? false) && !(addon.flags?.official ?? false)
    }
}

enum DebridProvider: String, CaseIterable, Identifiable {
    case realDebrid = "realdebrid"
    case allDebrid = "alldebrid"
    case premiumize = "premiumize"
    case debridLink = "debridlink"
    case torbox = "torbox"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realDebrid: return "Real-Debrid"
        case .allDebrid: return "AllDebrid"
        case .premiumize: return "Premiumize"
        case .debridLink: return "Debrid-Link"
        case .torbox: return "TorBox"
        }
    }

    var queryName: String { rawValue }

    private var keychainAccount: String { "debrid.\(rawValue)" }

    static func loadKey(_ provider: DebridProvider) -> String? {
        Keychain.string(for: "debrid.\(provider.rawValue)")
    }

    func saveKey(_ value: String) {
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            Keychain.delete(account: keychainAccount)
        } else {
            Keychain.set(value, for: keychainAccount)
        }
    }

    func loadExisting() -> String {
        Self.loadKey(self) ?? ""
    }
}
