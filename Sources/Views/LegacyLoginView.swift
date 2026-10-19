import SwiftUI

/// Log in to the original Bond Touch account (Firebase + api.bond-touch.com) as a bridge
/// until everything is on CloudKit. Mirrors the app's flow: enter email → receive a 6-digit
/// PIN by email → confirm. On success the account's email and session are stored.
struct LegacyLoginView: View {
    @EnvironmentObject var store: LocalStore
    @EnvironmentObject var model: AppModel

    enum Stage { case email, link, done }
    @State private var stage: Stage = .email
    @State private var email = ""
    @State private var linkText = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch stage {
                case .email: emailStep
                case .link:  linkStep
                case .done:  doneStep
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle("Bond Touch login")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !store.legacyEmail.isEmpty { stage = .done; email = store.legacyEmail } }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hi there!\nLet's get you connected.")
                .font(.title2.bold()).foregroundStyle(Theme.title)
            Text("Sign in with the email on your original Bond Touch account.")
                .font(.subheadline).foregroundStyle(Theme.subtitle)
            TextField("name@email.com", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(14).background(Theme.ink.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium)).foregroundStyle(Theme.title)
            primaryButton("Continue with email", enabled: email.contains("@") && !busy) {
                Task { await beginLogin() }
            }
        }
    }

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check your email").font(.title2.bold()).foregroundStyle(Theme.title)
            Text("We emailed a sign-in link to\n\(email).\nOpen that email, copy the sign-in link, and paste it here.")
                .font(.subheadline).foregroundStyle(Theme.subtitle)
            TextField("Paste the sign-in link", text: $linkText, axis: .vertical)
                .lineLimit(2...4).textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.footnote.monospaced()).foregroundStyle(Theme.title)
                .padding(14).background(Theme.ink.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            primaryButton("Sign in", enabled: linkText.contains("oobCode") && !busy) {
                Task { await completeLogin() }
            }
            Button("Resend the email") { Task { await beginLogin() } }
                .font(.footnote).foregroundStyle(Theme.accent).disabled(busy)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Signed in", systemImage: "checkmark.seal.fill")
                .font(.title2.bold()).foregroundStyle(Theme.accent)
            Text("Logged in as \(store.legacyEmail).").foregroundStyle(Theme.title)
            Text("Your original account is connected. Partners, invites, touches, Touch Language, greeting, encounters and presence sync with it alongside iCloud.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Text("Status: \(model.legacyStatus)").font(.footnote.monospaced()).foregroundStyle(Theme.subtitle)
            Button(role: .destructive) {
                store.legacyEmail = ""; store.legacyRefreshToken = ""; store.firebaseAuthToken = ""
                store.useLegacyFirebase = false
                model.resetLegacy()
                stage = .email; email = ""; linkText = ""
            } label: { Text("Log out").foregroundStyle(Theme.danger) }
        }
    }

    @ViewBuilder private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(Theme.onAccent) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
            .background(enabled ? Theme.accent : Theme.ink.opacity(0.2))
            .foregroundStyle(Theme.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
        }
        .disabled(!enabled)
    }

    private func beginLogin() async {
        busy = true; error = nil
        do {
            try await BondBackend.beginEmailLogin(email: email.trimmingCharacters(in: .whitespaces))
            stage = .link
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func completeLogin() async {
        busy = true; error = nil
        do {
            let session = try await BondBackend.completeEmailLogin(
                email: email.trimmingCharacters(in: .whitespaces), link: linkText)
            store.firebaseAuthToken = session.idToken
            store.legacyRefreshToken = session.refreshToken
            let fetchedEmail = (try? await BondBackend.currentUserEmail(bearer: session.idToken)) ?? ""
            store.legacyEmail = fetchedEmail.isEmpty ? email : fetchedEmail
            store.useLegacyFirebase = true
            model.startLegacySync()
            stage = .done
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
