import SwiftUI

struct SettingsView: View {
    @ObservedObject private var auth = AuthStore.shared
    @AppStorage("harbor.region") private var region = "US"
    @AppStorage(AnalyticsService.collectionPreferenceKey) private var analyticsEnabled = true
    @State private var confirmSignOut = false

    private let regions = ["US", "UK", "CA", "AU", "DE", "FR", "ES", "IT", "NL", "BR", "MX", "IN", "JP", "KR", "SE", "PL"]

    var body: some View {
        NavigationStack {
            List {
                HarborPageHeader(
                    title: "Settings",
                    eyebrow: "Make Harbor Yours",
                    subtitle: "Account, playback services and privacy"
                )
                .accessibilityIdentifier("harbor.settings.header")
                .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section("Account") {
                    if let user = auth.user {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: user.avatar ?? "")) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.body.weight(.semibold))
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive) {
                            confirmSignOut = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 36))
                                .foregroundColor(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not signed in")
                                    .font(.body.weight(.semibold))
                                Text("Sign in to sync your library and addons.")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Theme.surface)

                if auth.isSignedIn {
                    Section("Library") {
                        NavigationLink {
                            AddonsView()
                        } label: {
                            Label("Addons", systemImage: "puzzlepiece.extension")
                        }
                        NavigationLink {
                            DebridSetupView()
                        } label: {
                            Label("Streaming & Debrid", systemImage: "wand.and.stars")
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section("Preferences") {
                        Picker(selection: $region) {
                            ForEach(regions, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        } label: {
                            Label("Region", systemImage: "globe")
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Toggle("Share anonymous analytics", isOn: $analyticsEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Shares privacy-safe usage, crash, and performance diagnostics. Harbor never sends credentials, private URLs, stream links, or raw searches.")
                }
                .listRowBackground(Theme.surface)

                Section("About") {
                    LabeledRow(label: "Version", value: appVersion)
                    LabeledRow(label: "Build", value: appBuild)
                    LabeledRow(label: "Player", value: "VLC")
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Sign out of Stremio?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
            } message: {
                Text("Your library stays synced to your Stremio account.")
            }
            .onAppear {
                AnalyticsService.shared.setCurrentScreen(.settings, screenClass: "SettingsView")
            }
            .onChange(of: analyticsEnabled) { enabled in
                AnalyticsService.shared.setCollectionEnabledByUser(enabled)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.textSecondary)
        }
    }
}
