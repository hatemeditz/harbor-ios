import SwiftUI

struct AddonsView: View {
    @ObservedObject private var manager = AddonManager.shared
    @State private var newAddonURL = ""

    var body: some View {
        List {
            if let status = manager.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
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

            Section {
                Text("Tip: use the Streaming section to install Torrentio with your debrid key — that's what makes streams playable on iPhone.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Addons")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let authKey = AuthStore.shared.authKey else { return }
        await manager.reload(authKey: authKey)
    }

    private func installURL() {
        guard let authKey = AuthStore.shared.authKey else { return }
        Task {
            await manager.installFromURL(authKey: authKey, rawURL: newAddonURL)
            newAddonURL = ""
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

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8)
    ]

    var body: some View {
        List {
            if let status = manager.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
            }

            torrentioStatusRow

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
                Text("Debrid API keys")
            } footer: {
                Text("Keys are stored only in this device's Keychain and embedded into your Torrentio addon URL so streams come back as direct HTTPS links.")
            }

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
                        Text(isInstalling ? "Installing…" : "Install / Update Torrentio")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isInstalling)
                .listRowBackground(Theme.accent)
                .foregroundColor(.white)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Streaming")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadKeys() }
        .task {
            if let authKey = AuthStore.shared.authKey {
                await manager.reload(authKey: authKey)
            }
        }
    }

    private var torrentioStatusRow: some View {
        let status = manager.torrentioStatus()
        return Section {
            HStack(spacing: 10) {
                Image(systemName: status.installed ? "checkmark.seal.fill" : "circle.dashed")
                    .foregroundColor(status.installed ? .green : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Torrentio")
                        .font(.body.weight(.medium))
                    Text(status.installed
                         ? (status.keyed ? "Installed with debrid keys" : "Installed without keys")
                         : "Not installed")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.vertical, 2)
        }
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
