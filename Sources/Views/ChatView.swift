import PhotosUI
import SwiftUI

/// Chat with the selected partner — text bubbles, photos, and touches rendered as glowing
/// strokes, with a message input bar. With an original-app partner the chat is end-to-end
/// encrypted through the original backend (opt-in on this phone).
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var draft = ""
    @State private var photo: PhotosPickerItem?
    @State private var enabling = false

    private var messages: [ChatMessage] {
        guard let id = model.selectedPartnerID else { return [] }
        return model.messagesByBond[id] ?? []
    }

    private var isLegacy: Bool { model.selectedPartner?.bond.legacy == true }
    private var needsSetup: Bool { isLegacy && !store.legacyChatEnabled }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); PartnerBar(); Spacer() }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

            if needsSetup {
                setupCard
                Spacer()
            } else {
                if isLegacy, !model.legacyChatStatus.isEmpty, model.legacyChatStatus != "Encrypted chat is on." {
                    Text(model.legacyChatStatus)
                        .font(.footnote).foregroundStyle(Theme.subtitle)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
                        .padding(.horizontal, 16)
                }
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
                        markSeen()
                    }
                }
                inputBar
            }
        }
        .onAppear { markSeen() }
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
    }

    private func markSeen() {
        guard isLegacy, let id = model.selectedPartnerID else { return }
        Task { await model.markLegacyChatSeen(id) }
    }

    /// Opt-in for encrypted chat with an original-app partner.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Private, end-to-end encrypted chat", systemImage: "lock.fill")
                .font(.headline).foregroundStyle(.white)
            Text("Chat with \(model.selectedPartner?.displayName ?? "your partner") uses the same Signal encryption as the original app. Turning it on gives this phone its own chat keys, so:")
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline).foregroundStyle(Theme.subtitle)
            Text("• Messages sent before today can't be read here (they were encrypted for your old phone's keys).\n• The original app on another phone stops receiving your chat.")
                .font(.footnote).foregroundStyle(Theme.subtitle)
            Button {
                enabling = true
                Task { await model.enableLegacyChat(); enabling = false }
            } label: {
                HStack {
                    if enabling { ProgressView().tint(Theme.bgBottom) }
                    Text("Turn on encrypted chat").font(.headline)
                }
                .frame(maxWidth: .infinity).frame(height: Metric.buttonHeight)
                .background(Theme.accent).foregroundStyle(Theme.bgBottom)
                .clipShape(RoundedRectangle(cornerRadius: Metric.cornerMedium))
            }
            .buttonStyle(.plain).disabled(enabling)
            if !model.legacyChatStatus.isEmpty {
                Text(model.legacyChatStatus).font(.footnote).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Metric.cornerLarge))
        .padding(16)
    }

    @ViewBuilder private func bubble(_ msg: ChatMessage) -> some View {
        let mine = msg.senderID == model.myUserID || msg.senderID == ChatMessage.legacySelf
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
                    .background(Circle().fill(Theme.accent.opacity(isLegacy ? 0.9 : 0.3)))
            }
            .disabled(!isLegacy)
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
