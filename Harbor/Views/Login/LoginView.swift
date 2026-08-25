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
                VStack(spacing: 24) {
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
                .padding(24)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "anchor")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text("Harbor")
                .font(.system(size: 34, weight: .bold))
            Text("Sign in with your Stremio account to sync your library and addons.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding()
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

            Button(action: submit) {
                HStack {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right.to.line")
                    }
                    Text(isBusy ? "Signing in" : "Sign In")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)
            }
            .disabled(!canSubmit)
        }
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
