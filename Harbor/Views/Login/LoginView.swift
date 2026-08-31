import SwiftUI

struct LoginView: View {
    @ObservedObject private var auth = AuthStore.shared

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isBusy
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            LinearGradient(
                colors: [Theme.accent.opacity(0.16), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    header
                    form
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    footnote
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
        }
        .onAppear {
            AnalyticsService.shared.setCurrentScreen(.login, screenClass: "LoginView")
        }
    }

    private var header: some View {
        VStack(spacing: 13) {
            HarborWordmark()
                .scaleEffect(1.2)
                .padding(.bottom, 20)
            Text("WELCOME ABOARD")
                .font(.system(size: 9, weight: .heavy))
                .tracking(2.4)
                .foregroundColor(Theme.accent)
            Text("Your watchlist.\nYour streams. One harbor.")
                .font(.system(size: 31, weight: .bold, design: .serif))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
            Text("Sign in with Stremio to sync your library and installed addons.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 54)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STREMIO ACCOUNT")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.8)
                .foregroundColor(Theme.textSecondary)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))

            Button(action: submit) {
                HStack {
                    if isBusy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.right.to.line")
                    }
                    Text(isBusy ? "Signing in" : "Sign In")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HarborPrimaryButtonStyle())
            .opacity(canSubmit ? 1 : 0.45)
            .disabled(!canSubmit)
            .padding(.top, 4)
        }
        .padding(16)
        .background(Theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
    }

    private var footnote: some View {
        Text("Your credentials are sent directly to Stremio's API over HTTPS. Your session key is stored in the iOS Keychain.")
            .font(.caption2)
            .foregroundColor(Theme.textSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.bottom, 24)
    }

    private func submit() {
        guard canSubmit else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await auth.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
