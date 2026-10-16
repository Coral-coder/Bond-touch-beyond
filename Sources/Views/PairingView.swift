import SwiftUI
import UIKit

/// Pair with someone by a short code / link — one link connects both phones, no accept step.
struct PairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var shareError: String?
    @State private var inviteEmail = ""
    @State private var inviting = false
    @State private var inviteResult: String?
    @State private var joinCode = ""
    @State private var joining = false
    @State private var joinError: String?

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)
            Text("Pair with someone. Touches, messages and your heartbeat sync privately through iCloud — end-to-end encrypted, no account, no server.")
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
                Label("Create an invite code", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.iCloudStatus != nil)

            if let code = model.pendingInviteURL.flatMap(CloudRelay.code(fromURL:)),
               let url = model.pendingInviteURL {
                inviteBlock(code: code, url: url)
            } else {
                Text("Create a code, then send it to your partner. They enter it (or tap the link) and you're connected.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            joinBlock

            if model.legacySignedIn { emailInvite }
        }
        .padding()
        }
        .alert("Can't invite", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    /// The created invite: the code in big type, plus Share / Copy of the link.
    @ViewBuilder private func inviteBlock(code: String, url: URL) -> some View {
        VStack(spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))
            Text("Your invite code").font(.headline).foregroundStyle(.white)
            Text(code).font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                .foregroundStyle(Theme.accent).textSelection(.enabled)
            Text("Send your partner this code, or the link below. One tap connects you — no accepting, no waiting.")
                .font(.footnote).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    UIPasteboard.general.string = code
                    inviteResult = "Code copied."
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let inviteResult { Text(inviteResult).font(.caption).foregroundStyle(Theme.accent) }
        }
    }

    /// Join a partner's bond by typing their code.
    private var joinBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))
            Text("Have a code from your partner?").font(.headline).foregroundStyle(.white)
            HStack(spacing: 10) {
                TextField("CODE", text: $joinCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(12).background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium)).foregroundStyle(.white)
                Button {
                    Task {
                        joining = true; joinError = nil
                        joinError = await model.joinBond(code: joinCode.trimmingCharacters(in: .whitespaces))
                        if joinError == nil { joinCode = "" }
                        joining = false
                    }
                } label: {
                    if joining { ProgressView().tint(Theme.onAccent) } else { Text("Join").font(.headline) }
                }
                .frame(height: Metric.buttonHeight).padding(.horizontal, 18)
                .background(joinCode.count >= 4 ? Theme.accent : Color.white.opacity(0.2))
                .foregroundStyle(Theme.onAccent).clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                .disabled(joinCode.count < 4 || joining)
            }
            if let joinError { Text(joinError).font(.footnote).foregroundStyle(Theme.amber) }
        }
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

/// A sheet showing a bond's invite code + link (used from a partner/chat screen).
struct InviteCodeSheet: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let url, let code = CloudRelay.code(fromURL: url) {
                    Text("Invite code").font(.headline).foregroundStyle(.secondary)
                    Text(code).font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                        .foregroundStyle(Theme.accent).textSelection(.enabled)
                    Text("Send your partner this code or the link. One tap connects you — no accepting.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                        Button { UIPasteboard.general.string = code } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Text("Couldn't create the invite. Make sure you're signed into iCloud.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
