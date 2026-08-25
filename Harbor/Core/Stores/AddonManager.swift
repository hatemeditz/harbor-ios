import SwiftUI

@MainActor
final class AddonManager: ObservableObject {
    /// Cloud-only collection (no synthesized Cinemeta).
    @Published var cloudAddons: [Addon] = []
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    func reload(authKey: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            cloudAddons = try await AddonClient.shared.addonCollection(authKey: authKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(authKey: String, addon: Addon) async {
        guard isRemovable(addon) else { return }
        let updated = cloudAddons.filter { $0.id != addon.id }
        do {
            try await AddonClient.shared.setAddonCollection(authKey: authKey, addons: updated)
            cloudAddons = updated
            statusMessage = "Removed \(addon.displayName)"
            CatalogStore.shared.invalidate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installFromURL(authKey: String, rawURL: String) async -> Bool {
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed += "" }
        if !trimmed.hasPrefix("http") {
            errorMessage = "Enter a full manifest URL (https://…)"
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let manifest = try await AddonClient.shared.manifest(transportUrl: trimmed)
            var updated = cloudAddons.filter { $0.transportUrl != trimmed }
            updated.append(
                Addon(
                    transportUrl: trimmed,
                    manifest: manifest,
                    flags: AddonFlags(official: false, protected: false)
                )
            )
            try await AddonClient.shared.setAddonCollection(authKey: authKey, addons: updated)
            cloudAddons = updated
            statusMessage = "Installed \(manifest.name)"
            CatalogStore.shared.invalidate()
            return true
        } catch {
            errorMessage = "Could not load manifest: \(error.localizedDescription)"
            return false
        }
    }

    func installTorrentio(authKey: String) async -> Bool {
        let configParts = DebridProvider.allCases.compactMap { provider -> String? in
            guard let key = DebridProvider.loadKey(provider), !key.isEmpty else { return nil }
            return "\(provider.queryName)=\(key.trimmingCharacters(in: .whitespaces))"
        }
        let base = "https://torrentio.strem.fun"
        let transportUrl = configParts.isEmpty ? base + "/manifest.json" : base + "/" + configParts.joined(separator: "|") + "/manifest.json"

        isLoading = true
        defer { isLoading = false }
        do {
            let manifest = try await AddonClient.shared.manifest(transportUrl: transportUrl)
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
            cloudAddons = updated
            statusMessage = configParts.isEmpty
                ? "Installed Torrentio (no debrid keys)"
                : "Installed Torrentio with \(configParts.count) debrid key(s)"
            CatalogStore.shared.invalidate()
            return true
        } catch {
            errorMessage = "Torrentio install failed: \(error.localizedDescription)"
            return false
        }
    }

    func torrentioStatus() -> (installed: Bool, keyed: Bool) {
        let torrentio = cloudAddons.first {
            $0.transportUrl.lowercased().contains("torrentio.strem.fun")
        }
        guard let torrentio else { return (false, false) }
        return (true, torrentio.transportUrl.contains("="))
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
