import SwiftUI

struct AddonsView: View {
    @ObservedObject private var manager = AddonManager.shared
    @State private var newAddonURL = ""

    var body: some View {
        List {
            HarborPageHeader(
                title: "Addons",
                eyebrow: "Extend Harbor",
                subtitle: "Everything installed in your Stremio collection"
            )
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let status = manager.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .listRowBackground(Theme.surface)
            }
            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                    .listRowBackground(Theme.surface)
            }

            Section("Installed (\(manager.cloudAddons.count))") {
                if manager.isLoading && manager.cloudAddons.isEmpty {
                    HStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
                } else if manager.cloudAddons.isEmpty {
                    Text("No addons in your Stremio collection yet.")
                        .foregroundColor(Theme.textSecondary)
                        .font(.subheadline)
                } else {
                    ForEach(manager.cloudAddons) { addon in
                        addonRow(addon)
                    }
                }
            }
            .listRowBackground(Theme.surface)

            Section("Add by URL") {
                TextField("https://example.com/manifest.json", text: $newAddonURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)

                Button {
                    installURL()
                } label: {
                    Label("Install Addon", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(newAddonURL.isEmpty || manager.isLoading)
            }
            .listRowBackground(Theme.surface)

            Section {
                Text("Addons installed or configured in Stremio on your PC sync here automatically. Add a URL only when the addon is not already in your Stremio account.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .harborNavigationChrome()
        .task { await reload() }
        .refreshable { await reload() }
        .onAppear {
            AnalyticsService.shared.setCurrentScreen(.addons, screenClass: "AddonsView")
        }
    }

    private func reload() async {
        guard let authKey = AuthStore.shared.authKey else { return }
        await manager.reload(authKey: authKey)
    }

    private func installURL() {
        guard let authKey = AuthStore.shared.authKey else { return }
        Task {
            let installed = await manager.installFromURL(authKey: authKey, rawURL: newAddonURL)
            if installed {
                newAddonURL = ""
            }
        }
    }

    private func addonRow(_ addon: Addon) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: addon.manifest.logo ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.surfaceRaised
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(addon.displayName)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let version = addon.manifest.version {
                        Text("v\(version)")
                    }
                    Text((addon.manifest.types ?? []).prefix(3).joined(separator: ", "))
                }
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if manager.isRemovable(addon) {
                Button {
                    guard let authKey = AuthStore.shared.authKey else { return }
                    Task { await manager.remove(authKey: authKey, addon: addon) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary.opacity(0.5))
            }
        }
        .padding(.vertical, 2)
    }
}

struct DebridSetupView: View {
    @ObservedObject private var manager = AddonManager.shared

    @State private var keys: [DebridProvider: String] = [:]
    @State private var isInstalling = false

    var body: some View {
        List {
            HarborPageHeader(
                title: "Streaming & Debrid",
                eyebrow: "Playback Services",
                subtitle: "Manage synced providers and optional Torrentio setup"
            )
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let status = manager.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .listRowBackground(Theme.surface)
            }
            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                    .listRowBackground(Theme.surface)
            }

            syncedStreamingAddons
            syncedSubtitleAddons

            Section {
                ForEach(DebridProvider.allCases) { provider in
                    HStack {
                        Text(provider.displayName)
                            .font(.subheadline)
                            .frame(width: 96, alignment: .leading)
                        SecureField("API key", text: binding(provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote)
                    }
                }
            } header: {
                Text("Optional Torrentio setup")
            } footer: {
                Text("Keys stay in this device's Keychain. Installing or updating Torrentio adds its configured transport URL to your Stremio account.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button {
                    installTorrentio()
                } label: {
                    HStack {
                        if isInstalling {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isInstalling ? "Updating…" : "Install / Update Torrentio")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isInstalling || manager.isLoading)
                .listRowBackground(Theme.accent)
                .foregroundColor(.white)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .harborNavigationChrome()
        .onAppear {
            loadKeys()
            AnalyticsService.shared.setCurrentScreen(.debridSetup, screenClass: "DebridSetupView")
        }
        .task {
            if let authKey = AuthStore.shared.authKey {
                await manager.reload(authKey: authKey)
            }
        }
    }

    private var syncedStreamingAddons: some View {
        Section {
            if manager.isLoading && manager.syncedStreamAddons.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
            } else if manager.syncedStreamAddons.isEmpty {
                Text("No configured streaming addon was found in your Stremio account.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ForEach(manager.syncedStreamAddons) { addon in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.displayName)
                                .font(.body.weight(.medium))
                            Text(manager.hasEmbeddedDebridConfiguration(addon)
                                 ? "Debrid configuration synced from Stremio"
                                 : "Streaming addon synced from Stremio")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            }
        } header: {
            Text("Stremio account")
        } footer: {
            if !manager.syncedStreamAddons.isEmpty {
                Text("Harbor uses these addons and their configured transport URLs automatically. You do not need to reinstall them or enter the debrid key again.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var syncedSubtitleAddons: some View {
        Section("Subtitle addons") {
            if manager.isLoading && manager.syncedSubtitleAddons.isEmpty {
                ProgressView().tint(Theme.accent)
                    .frame(maxWidth: .infinity)
            } else if manager.syncedSubtitleAddons.isEmpty {
                Text("No subtitle addon was found in your Stremio account.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            } else {
                ForEach(manager.syncedSubtitleAddons) { addon in
                    Label(addon.displayName, systemImage: "captions.bubble.fill")
                        .foregroundColor(Theme.textPrimary)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func loadKeys() {
        for provider in DebridProvider.allCases {
            keys[provider] = provider.loadExisting()
        }
    }

    private func binding(_ provider: DebridProvider) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: {
                keys[provider] = $0
                provider.saveKey($0)
            }
        )
    }

    private func installTorrentio() {
        guard let authKey = AuthStore.shared.authKey else { return }
        isInstalling = true
        Task {
            defer { isInstalling = false }
            _ = await manager.installTorrentio(authKey: authKey)
        }
    }
}
