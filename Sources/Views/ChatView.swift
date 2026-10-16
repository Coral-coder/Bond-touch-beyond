import SwiftUI

/// Chat with the selected partner — text bubbles and touches rendered as glowing strokes,
/// with a message input bar.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""

    private var messages: [ChatMessage] {
        guard let id = model.selectedPartnerID else { return [] }
        return model.messagesByBond[id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); PartnerBar(); Spacer() }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

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

    @ViewBuilder private func bubble(_ msg: ChatMessage) -> some View {
        let mine = msg.senderID == model.myUserID
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            HStack {
                if mine { Spacer(minLength: 40) }
                if msg.kind == .touch {
                    GlassCard { TouchViz(pattern: [], colorRGB: msg.colorRGB) }
                        .frame(maxWidth: 260)
                } else {
                    Text(msg.text)
                        .foregroundStyle(mine ? .white : .white.opacity(0.95))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(mine ? Theme.teal.opacity(0.22) : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
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
            Image(systemName: "camera.fill")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.teal.opacity(0.9)))
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
                                              ? Color.white.opacity(0.12) : Theme.teal))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
