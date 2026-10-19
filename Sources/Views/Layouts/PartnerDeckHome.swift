import SwiftUI

/// Partner Deck: each person is a tall card with their photo, name and status, and a touch
/// pad right on the card. Swipe sideways for the next person; recent touches run as a strip
/// underneath.
struct PartnerDeckHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Your people").font(Theme.font(26, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                HeartbeatButton(size: 42)
                RoundIconButton(icon: "person.badge.plus", label: "People", size: 42) { people = true }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            if model.partners.isEmpty {
                Button { people = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 34, weight: .semibold))
                        Text("Add someone").font(Theme.font(18, .heavy))
                    }
                    .foregroundStyle(Theme.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glass(cornerRadius: 34)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
            } else {
                TabView(selection: Binding(get: { model.selectedPartnerID }, set: { model.selectedPartnerID = $0 })) {
                    ForEach(model.partners) { p in
                        card(p).padding(.horizontal, 18).padding(.bottom, 30).tag(Optional(p.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }

            let touches = model.recentTouches(limit: 20)
            if !touches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(touches) { t in
                            Button { model.feel(t) } label: {
                                TouchGlyph(touch: t, height: 34).frame(width: 92)
                                    .padding(8).glass(cornerRadius: 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Replay touch from \(t.sentAt.formatted(date: .omitted, time: .shortened))")
                        }
                        Button { history = true } label: {
                            Image(systemName: "list.bullet").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.title)
                                .frame(width: 50, height: 50).glass(cornerRadius: 16)
                        }
                        .buttonStyle(.plain).accessibilityLabel("All recent touches")
                    }
                    .padding(.horizontal, 18).padding(.vertical, 2)
                }
            }
        }
        .padding(.bottom, 12)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    private func card(_ p: Partner) -> some View {
        ZStack {
            if let photo = model.photo(forBond: p.id) {
                GeometryReader { geo in
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            } else {
                LinearGradient(colors: [Color(rgbInt: p.colorRGB).opacity(0.7), Theme.magenta.opacity(0.45), Theme.bgBottom],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
            LinearGradient(colors: [.black.opacity(0.25), .clear, Theme.bgBottom.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Button { model.selectedPartnerID = p.id; partnerSheet = true } label: {
                    HStack(spacing: 12) {
                        PartnerFace(partner: p, size: 54)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.displayName).font(Theme.font(28, .heavy)).foregroundStyle(.white)
                            Text([model.statusText(p), model.distanceText(to: p)].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.font(12, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                            if model.selectedPartnerID == p.id { TogetherChip() }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if model.selectedPartnerID == p.id {
                    InlineTouchPad(shape: .bar, title: "Touch \(p.displayName)", hint: "tap & slide here")
                        .frame(height: 96)
                    MeaningChipRow(height: 34)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Theme.ink.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}
