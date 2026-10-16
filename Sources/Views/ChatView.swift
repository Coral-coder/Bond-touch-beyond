import CloudKit
import PhotosUI
import SwiftUI

/// Chat with the selected partner over iCloud — text bubbles, photos, and touches rendered
/// as glowing strokes. A partner on the original Bond Touch app is invited to (or linked
/// with) an iCloud bond first; chat with them then runs through it.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var inviting = false
    @State private var showShare = false
    @State private var shareError: String?

    private var messages: [ChatMessage] { model.chatMessages(for: model.selectedPartnerID) }
    private var chatBondID: String? { model.chatBondID(for: model.selectedPartnerID) }
    private var needsLink: Bool { model.selectedPartner != nil && chatBondID == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); PartnerBar(); Spacer() }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

            if needsLink {
                ScrollView { linkCard }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { msg in bubble(msg).id(msg.id) }
                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.horizontal, 16).padding(.top, 8)
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                inputBar
            }
        }
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.7) {
                    await model.sendChatImage(jpeg)
                }
                photo = nil
            }
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

    /// Shown for an original-app partner without an iCloud chat bond yet.
    private var linkCard: some View {
        let name = model.selectedPartner?.displayName ?? "your partner"
        let linkable = model.cloudPartners.filter { !model.chatLinkedCloudIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            Label("Chat goes through iCloud", systemImage: "icloud.fill")
                .font(Theme.font(17, .heavy)).foregroundStyle(.white)
            Text("Messages and photos with \(name) are sent privately through iCloud. Invite them to Bond Touch Beyond chat — they open the link on their iPhone — or link the iCloud partner you already share with them.")
                .font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard let id = model.selectedPartnerID else { return }
                inviting = true
                Task {
                    await model.inviteToICloudChat(id)
                    inviting = false
                    showShare = model.pendingShareRoot != nil
                }
            } label: {
                HStack {
                    if inviting { ProgressView().tint(Theme.onAccent) }
                    Text("Invite \(name) to iCloud chat")
                }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(inviting)
            if !linkable.isEmpty {
                Text("Or link an iCloud partner").font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
                    .padding(.top, 4)
                ForEach(linkable) { p in
                    Button {
                        if let id = model.selectedPartnerID { model.linkChat(id, toCloudBond: p.id) }
                    } label: {
                        HStack(spacing: 10) {
                            AvatarRing(name: p.displayName, ringColor: Color(rgbInt: p.colorRGB), size: 34,
                                       photo: model.photo(forBond: p.id), ringWidth: 0)
                            Text(p.displayName).font(Theme.font(15, .bold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "link").foregroundStyle(Theme.accent)
                        }
                        .padding(10).glass(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .glass(cornerRadius: 28)
        .padding(16)
    }

    @ViewBuilder private func bubble(_ msg: ChatMessage) -> some View {
        let mine = msg.senderID == model.myUserID
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            HStack {
                if mine { Spacer(minLength: 40) }
                switch msg.kind {
                case .touch:
                    GlassCard { TouchViz(pattern: [], colorRGB: msg.colorRGB) }
                        .frame(maxWidth: 260)
                case .image:
                    if let file = msg.imageFile, let image = UIImage(contentsOfFile: ChatArchive.imageURL(file).path) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(maxWidth: 240, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Text("Photo").foregroundStyle(Theme.subtitle)
                            .padding(14).background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                case .text:
                    if mine {
                        Text(msg.text)
                            .font(Theme.font(16)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accentDeep.opacity(0.35)],
                                                       startPoint: .top, endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
                    } else {
                        Text(msg.text)
                            .font(Theme.font(16)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .glass(cornerRadius: 20)
                    }
                }
                if !mine { Spacer(minLength: 40) }
            }
            Text(msg.sentAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(Theme.subtitle)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.accent.opacity(0.9)))
            }
            .accessibilityLabel("Send a photo")
            TextField("", text: $draft, prompt: Text("Message \(model.selectedPartner?.displayName ?? "")…")
                .foregroundColor(Theme.subtitle))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Button {
                let text = draft; draft = ""
                Task { await model.sendChatText(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty
                                              ? Color.white.opacity(0.12) : Theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(8)
        .glass(cornerRadius: 30)
        .padding(.horizontal, 12).padding(.bottom, 90)
    }
}
