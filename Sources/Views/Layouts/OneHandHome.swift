import SwiftUI

/// One-Hand: the top half is an ambient display — the last touch drawn big, its name, how
/// long ago. Every control lives in the bottom half, in thumb reach: who, meanings, a wide
/// touch pad and the heartbeat.
struct OneHandHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let p = model.selectedPartner {
                    Button { partnerSheet = true } label: {
                        Text("\(p.displayName) · \(model.statusText(p))")
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                RoundIconButton(icon: "clock.arrow.circlepath", label: "Recent touches", size: 40) { history = true }
                RoundIconButton(icon: "person.2.fill", label: "People", size: 40) { people = true }
            }
            .padding(.top, 8)
            TogetherChip()

            ambient.frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                switcher
                MeaningChipRow()
                HStack(spacing: 10) {
                    InlineTouchPad(shape: .bar, title: "Touch", hint: "tap & slide").frame(height: 96)
                    HeartbeatButton(size: 96, cornerRadius: 30)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    @ViewBuilder private var ambient: some View {
        if let last = model.recentTouches().first {
            let tag = model.meaningTag(for: last)
            Button { model.feel(last) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(last.heartbeatBPM.map { "♥ \($0) BPM" } ?? tag.map { "\($0.emoji) \($0.label)" }
                         ?? (model.isMine(last) ? "You touched" : "A touch"))
                        .font(Theme.font(46, .heavy)).foregroundStyle(Theme.title)
                        .lineLimit(2).minimumScaleFactor(0.5)
                    Text("\(model.isMine(last) ? "From you" : "From \(model.selectedPartner?.displayName ?? "them")") · \(last.sentAt.formatted(.relative(presentation: .named)))")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                    TouchGlyph(touch: last, height: 130).padding(.top, 10)
                    Text("Tap to feel it again").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedPartner == nil ? "Hello" : "Say hi to \(model.selectedPartner?.displayName ?? "")")
                    .font(Theme.font(42, .heavy)).foregroundStyle(Theme.title).minimumScaleFactor(0.5)
                Text("Your touches show up here, big.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var switcher: some View {
        HStack(spacing: 4) {
            if model.partners.isEmpty {
                Button { people = true } label: {
                    Text("Add someone").font(Theme.font(14, .heavy)).foregroundStyle(Theme.title).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            ForEach(model.partners) { p in
                let on = p.id == model.selectedPartnerID
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3)) { model.selectedPartnerID = p.id }
                } label: {
                    Text(p.displayName).font(Theme.font(14, .heavy)).lineLimit(1)
                        .foregroundStyle(on ? Theme.title : Theme.subtitle)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(on ? Theme.ink.opacity(0.18) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glass(Capsule())
    }
}
