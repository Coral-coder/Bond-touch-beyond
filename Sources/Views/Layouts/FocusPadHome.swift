import SwiftUI

/// Focus Pad: the screen is the touch. One big glowing ring you tap, hold and slide around
/// (around the ring = along the bar); meanings below it; the last touch as a strip that
/// opens the history.
struct FocusPadHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HeartbeatButton()
                Spacer(minLength: 8)
                PartnerBar()
                Spacer(minLength: 8)
                RoundIconButton(icon: "person.2.fill", label: "People") { people = true }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            if let p = model.selectedPartner {
                Button { partnerSheet = true } label: {
                    VStack(spacing: 4) {
                        PartnerFace(partner: p, size: 58)
                        Text(p.displayName).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                        Text([model.statusText(p), model.distanceText(to: p)].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.font(12)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Partner details")
            }

            InlineTouchPad(shape: .ring, title: "Touch", hint: "tap · hold · slide around")
                .frame(maxWidth: 330, maxHeight: 330)
                .padding(.horizontal, 30)
                .layoutPriority(1)

            MeaningChipRow().padding(.horizontal, 18)

            if let last = model.recentTouches().first {
                Button { history = true } label: {
                    HStack(spacing: 10) {
                        Text(model.isMine(last) ? "You" : (model.selectedPartner?.displayName ?? "Partner"))
                            .font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                        Text(last.sentAt.formatted(.relative(presentation: .named)))
                            .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                        TouchGlyph(touch: last, height: 30).frame(maxWidth: .infinity)
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.subtitle)
                    }
                    .padding(.horizontal, 16).frame(height: 54)
                    .glass(cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .accessibilityLabel("Recent touches")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 92)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }
}

/// Recent touches with the selected partner, as a sheet (layouts that don't show the full
/// history on Home open this). Tap one to feel it again.
struct TouchHistorySheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.recentTouches()) { t in
                    Button { model.feel(t) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(model.isMine(t) ? "You" : (model.selectedPartner?.displayName ?? "Partner"))
                                    .font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                                if let tag = model.meaningTag(for: t) {
                                    Text("\(tag.emoji) \(tag.label)").font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                                }
                                Spacer()
                                Text(t.sentAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                            }
                            TouchGlyph(touch: t, height: 40)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.ink.opacity(0.05))
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Recent touches")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
