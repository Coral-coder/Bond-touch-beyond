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
    /// Whether the end of the chat is on screen; new messages only pull the view down then.
    @State private var atBottom = true
    @State private var viewportHeight: CGFloat = 0
    @State private var keyboardUp = false

    private var messages: [ChatMessage] { model.chatMessages(for: model.selectedPartnerID) }

    /// Messages and touches together, in time order — touches show inline in the chat.
    private enum Item: Identifiable {
        case message(ChatMessage)
        case touch(TouchMessage)
        var id: UUID { switch self { case .message(let m): return m.id; case .touch(let t): return t.id } }
        var date: Date { switch self { case .message(let m): return m.sentAt; case .touch(let t): return t.sentAt } }
    }

    private var items: [Item] {
        let touches = model.history.filter { $0.bondID == model.selectedPartnerID }.map(Item.touch)
        return (messages.map(Item.message) + touches).sorted { $0.date < $1.date }
    }
    private var lastSeenID: UUID? { model.lastSeenMessageID(for: model.selectedPartnerID) }
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
                            ForEach(items) { item in
                                switch item {
                                case .message(let msg): bubble(msg).id(msg.id)
                                case .touch(let t): touchBubble(t).id(t.id)
                                }
                            }
                            // Where the bottom of the chat is, relative to the visible area.
                            Color.clear.frame(height: 8).id("bottom")
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: ChatBottomKey.self, value: g.frame(in: .named("chat")).maxY)
                                })
                        }
                        .padding(.horizontal, 16).padding(.top, 8)
                    }
                    .coordinateSpace(name: "chat")
                    // The message box sits between the chat and the bar, so no extra gap here.
                    .noTabBarGap()
                    .scrollDismissesKeyboard(.interactively)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { viewportHeight = g.size.height }
                            .onChange(of: g.size.height) { h in
                                viewportHeight = h
                                // The keyboard (or the tab bar) changed the space: keep the
                                // latest message in view if we were at the bottom.
                                if atBottom { scrollToBottom(proxy, animated: false) }
                            }
                    })
                    .onPreferenceChange(ChatBottomKey.self) { maxY in
                        // At the bottom = the end of the chat is (nearly) on screen.
                        let now = maxY <= viewportHeight + 40
                        if now != atBottom { withAnimation(.easeOut(duration: 0.2)) { atBottom = now } }
                    }
                    .onAppear {
                        scrollToBottom(proxy, animated: false)
                        // Once more after the lazy rows have laid out.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrollToBottom(proxy, animated: false) }
                    }
                    .onChange(of: model.selectedPartnerID) { _ in
                        atBottom = true
                        DispatchQueue.main.async { scrollToBottom(proxy, animated: false) }
                    }
                    .onChange(of: items.count) { _ in
                        // Follow new messages only if we're at the bottom, or it's our own.
                        let mineLast: Bool = {
                            switch items.last {
                            case .message(let m): return m.senderID == model.myUserID
                            case .touch(let t): return t.senderID == model.myUserID || t.senderID == ChatMessage.legacySelf
                            case nil: return false
                            }
                        }()
                        if atBottom || mineLast { scrollToBottom(proxy, animated: true) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !atBottom {
                            Button { scrollToBottom(proxy, animated: true) } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.title)
                                    .frame(width: 44, height: 44).glass(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16).padding(.bottom, 10)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Jump to the latest message")
                        }
                    }
                }
                inputBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
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
            InviteCodeSheet(url: model.pendingInviteURL)
        }
        .alert("Can't invite", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
        // While this chat is on screen, its message notifications stay quiet (see AppDelegate).
        .onAppear { model.viewingChatBondID = model.selectedPartnerID }
        .onChange(of: model.selectedPartnerID) { model.viewingChatBondID = $0 }
        .onDisappear { model.viewingChatBondID = nil }
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
                    showShare = model.pendingInviteURL != nil
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

    /// A touch in the chat: the touch drawn in a small glass card (a heartbeat as its EKG),
    /// on the sender's side, with its meaning and a replay button.
    private func touchBubble(_ t: TouchMessage) -> some View {
        let mine = t.senderID == model.myUserID || t.senderID == ChatMessage.legacySelf
        return VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            HStack {
                if mine { Spacer(minLength: 60) }
                HStack(spacing: 8) {
                    Group {
                        if let bpm = t.heartbeatBPM {
                            EKGView(bpm: bpm, colorRGB: t.colorRGB, lineWidth: 2).frame(height: 40)
                        } else {
                            TouchViz(pattern: t.pattern, generation: t.generation, colorRGB: t.colorRGB,
                                     endColorRGB: t.endColorRGB, height: 40)
                        }
                    }
                    .frame(width: 150)
                    Button { model.feel(t) } label: {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play this touch")
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glass(cornerRadius: 18)
                if !mine { Spacer(minLength: 60) }
            }
            let label = t.heartbeatBPM.map { "Heartbeat \($0) BPM" } ?? t.meaningLabel.map { [t.meaningEmoji, $0].compactMap { $0 }.joined(separator: " ") }
            Text([label, t.sentAt.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Theme.subtitle)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mine ? "Your touch" : "Touch from \(model.selectedPartner?.displayName ?? "partner")")
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
            // "Seen" under our latest message the partner's phone has received.
            Text(msg.sentAt.formatted(date: .omitted, time: .shortened)
                 + (mine && msg.id == lastSeenID ? " · Seen" : ""))
                .font(.caption2).foregroundStyle(Theme.subtitle)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
        atBottom = true
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
        .padding(.horizontal, 12).padding(.bottom, keyboardUp ? 8 : TabBarSpace.fixed)
    }
}

/// The chat's bottom edge, in the scroll view's visible coordinates.
private struct ChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
