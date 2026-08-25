import SwiftUI

struct SettingsView: View {
    @ObservedObject private var auth = AuthStore.shared
    @AppStorage("harbor.region") private var region = "US"
    @State private var confirmSignOut = false

    private let regions = ["US", "UK", "CA", "AU", "DE", "FR", "ES", "IT", "NL", "BR", "MX", "IN", "JP", "KR", "SE", "PL"]

    var body: some View {
        NavigationStack {
            List {
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

                    Section("Preferences") {
                        Picker(selection: $region) {
                            ForEach(regions, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        } label: {
                            Label("Region", systemImage: "globe")
                        }
                    }
                }

                Section("About") {
                    LabeledRow(label: "Version", value: "0.9.1")
                    LabeledRow(label: "Build", value: "2")
                    LabeledRow(label: "Player", value: "VLC")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
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
        }
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
