import SwiftUI

/// Text + touch chat with the selected partner, relayed over CloudKit.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""

    private var messages: [ChatMessage] {
        guard let id = model.selectedPartnerID else { return [] }
        return model.messagesByBond[id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.partners.count > 1 { PartnerPicker() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in bubble(msg).id(msg.id) }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = draft
                    draft = ""
                    Task { await model.sendChatText(text) }
                } label: { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    @ViewBuilder private func bubble(_ msg: ChatMessage) -> some View {
        let mine = msg.senderID == model.myUserID
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(msg.kind == .touch ? "👆 touch" : msg.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Color.accentColor.opacity(0.9) : Color.gray.opacity(0.2))
                .foregroundStyle(mine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !mine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// A compact partner selector shown when the user has more than one partner.
struct PartnerPicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.partners) { partner in
                    Button {
                        model.selectedPartnerID = partner.id
                    } label: {
                        Text(partner.displayName)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(partner.id == model.selectedPartnerID
                                        ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
    }
}
