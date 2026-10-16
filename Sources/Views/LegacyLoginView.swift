import SwiftUI

/// Log in to the original Bond Touch account (Firebase + api.bond-touch.com) as a bridge
/// until everything is on CloudKit. Mirrors the app's flow: enter email → receive a 6-digit
/// PIN by email → confirm. On success the account's email and session are stored.
struct LegacyLoginView: View {
    @EnvironmentObject var store: LocalStore

    enum Stage { case email, pin, done }
    @State private var stage: Stage = .email
    @State private var email = ""
    @State private var pin = ""
    @State private var anon: BondBackend.Session?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch stage {
                case .email: emailStep
                case .pin:   pinStep
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
            Text("Hi there! 👋\nLet's get you connected.")
                .font(.title2.bold()).foregroundStyle(.white)
            Text("Sign in with the email on your original Bond Touch account.")
                .font(.subheadline).foregroundStyle(Theme.subtitle)
            TextField("name@email.com", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(14).background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium)).foregroundStyle(.white)
            primaryButton("Continue with email", enabled: email.contains("@") && !busy) {
                Task { await beginLogin() }
            }
        }
    }

    private var pinStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your pin").font(.title2.bold()).foregroundStyle(.white)
            Text("We sent a 6-digit code to\n\(email)\nto confirm your email address.")
                .font(.subheadline).foregroundStyle(Theme.subtitle)
            TextField("------", text: $pin)
                .keyboardType(.numberPad).multilineTextAlignment(.center)
                .font(.title.monospaced()).foregroundStyle(.white)
                .padding(14).background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                .onChange(of: pin) { if $0.count > 6 { pin = String($0.prefix(6)) } }
            primaryButton("Confirm", enabled: pin.count == 6 && !busy) {
                Task { await completeLogin() }
            }
            Button("Resend pin") { Task { await beginLogin() } }
                .font(.footnote).foregroundStyle(Theme.accent).disabled(busy)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Signed in", systemImage: "checkmark.seal.fill")
                .font(.title2.bold()).foregroundStyle(Theme.accent)
            Text("Logged in as \(store.legacyEmail).").foregroundStyle(.white)
            Text("Your original account is connected. Partner data sync is being wired up next.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Button(role: .destructive) {
                store.legacyEmail = ""; store.legacyRefreshToken = ""; store.firebaseAuthToken = ""
                store.useLegacyFirebase = false
                stage = .email; email = ""; pin = ""
            } label: { Text("Log out").foregroundStyle(Theme.danger) }
        }
    }

    @ViewBuilder private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(Theme.bgBottom) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
            .background(enabled ? Theme.accent : Color.white.opacity(0.2))
            .foregroundStyle(Theme.bgBottom)
            .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
        }
        .disabled(!enabled)
    }

    private func beginLogin() async {
        busy = true; error = nil
        do {
            anon = try await BondBackend.beginEmailLogin(email: email.trimmingCharacters(in: .whitespaces))
            stage = .pin
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func completeLogin() async {
        guard let anon else { return }
        busy = true; error = nil
        do {
            let session = try await BondBackend.completeEmailLogin(
                email: email.trimmingCharacters(in: .whitespaces), pin: pin, anon: anon)
            store.firebaseAuthToken = session.idToken
            store.legacyRefreshToken = session.refreshToken
            let fetchedEmail = (try? await BondBackend.currentUserEmail(bearer: session.idToken)) ?? ""
            store.legacyEmail = fetchedEmail.isEmpty ? email : fetchedEmail
            store.useLegacyFirebase = true
            stage = .done
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
