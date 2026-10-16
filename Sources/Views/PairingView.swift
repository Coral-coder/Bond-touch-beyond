import CloudKit
import SwiftUI
import UIKit

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

            if let msg = model.iCloudStatus { iCloudBanner(msg) }

            Button {
                Task {
                    inviteResult = nil
                    let error = await model.createBond()
                    if let error { shareError = error }
                }
            } label: {
                Label("Create an invite link", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.iCloudStatus != nil)

            Text("Your partner joins by opening the invite you send them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = model.pendingShare?.url { inviteLink(url) }

            if model.legacySignedIn { emailInvite }
        }
        .padding()
        }
        .sheet(isPresented: $showShare) {
            if let share = model.pendingShare {
                CloudShareSheet(share: share, container: CKContainer(identifier: AppConfig.cloudContainerID),
                                onError: { msg in showShare = false; shareError = msg })
            }
        }
        .alert("Can't invite", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    /// Shown when iCloud isn't usable (chiefly: not signed in) — the reason, plus a button
    /// straight to Settings. iCloud pairing can't work until this clears.
    @ViewBuilder private func iCloudBanner(_ message: String) -> some View {
        VStack(spacing: 10) {
            Label("iCloud needed to pair", systemImage: "exclamationmark.icloud")
                .font(.headline).foregroundStyle(.white)
            Text(message).font(.footnote).foregroundStyle(Theme.subtitle)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label("Open Settings", systemImage: "gear").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Theme.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: Metric.cornerMedium))
    }

    /// The ready invite link — share or copy it and send any way. This bypasses the
    /// CloudKit share sheet's Messages preview, which can spin forever.
    @ViewBuilder private func inviteLink(_ url: URL) -> some View {
        VStack(spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))
            Text("Invite link ready").font(.headline).foregroundStyle(.white)
            Text("Send this to your partner any way you like — Messages, WhatsApp, email. They tap it to join.")
                .font(.footnote).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    UIPasteboard.general.url = url
                    inviteResult = "Invite link copied."
                } label: {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text(url.absoluteString).font(.caption2.monospaced()).foregroundStyle(Theme.subtitle)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            if let inviteResult { Text(inviteResult).font(.caption).foregroundStyle(Theme.accent) }
        }
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
