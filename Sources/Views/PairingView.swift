import CloudKit
import SwiftUI

/// Create a bond and invite a partner. Used when the user has no partners yet, and from
/// the People screen to add another.
struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var showShare = false
    @State private var shareError: String?
    @State private var inviteEmail = ""
    @State private var inviting = false
    @State private var inviteResult: String?

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)
            Text("Pair with someone. Touches, messages and your heartbeat are relayed privately through iCloud — no account, no server.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await model.createBond()
                    showShare = model.pendingShareRoot != nil
                }
            } label: {
                Label("Create a bond & invite", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Your partner joins by opening the invite you send them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.legacySignedIn { emailInvite }
        }
        .padding()
        }
        .sheet(isPresented: $showShare) {
            if let root = model.pendingShareRoot {
                CloudShareSheet(root: root, container: CKContainer(identifier: AppConfig.cloudContainerID),
                                onError: { msg in showShare = false; shareError = msg })
            }
        }
        .alert("Can't invite", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    /// Invite someone who uses the original Bond Touch app, by their account email
    /// (`POST bond/api/v4/bonds`). They accept it in their app.
    private var emailInvite: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))
            Text("Partner on the original Bond Touch app?")
                .font(.headline).foregroundStyle(.white)
            Text("Invite them with the email on their Bond Touch account.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            TextField("name@email.com", text: $inviteEmail)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(12).background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium)).foregroundStyle(.white)
            Button {
                Task {
                    inviting = true; inviteResult = nil
                    do {
                        try await model.legacyInvite(email: inviteEmail)
                        inviteResult = "Invite sent to \(inviteEmail)."
                        inviteEmail = ""
                    } catch {
                        inviteResult = error.localizedDescription
                    }
                    inviting = false
                }
            } label: {
                HStack {
                    if inviting { ProgressView().tint(Theme.bgBottom) }
                    Text("Send invite").font(.headline)
                }
                .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                .background(inviteEmail.contains("@") ? Theme.accent : Color.white.opacity(0.2))
                .foregroundStyle(Theme.bgBottom)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            }
            .buttonStyle(.plain)
            .disabled(!inviteEmail.contains("@") || inviting)
            if let inviteResult {
                Text(inviteResult).font(.footnote).foregroundStyle(Theme.subtitle)
            }
        }
    }
}
