import SwiftUI

/// Minimal 2: the middle ground — three calm cards. Your partner (status, weather, days
/// together and the next date in one place), the touch bar with a few meanings, and the
/// last touch (tap for the history).
struct MinimalTwoHome: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Home").font(Theme.font(26, .heavy)).foregroundStyle(Theme.title)
                    Spacer()
                    PartnerBar()
                }
                .padding(.top, 8)

                if let p = model.selectedPartner {
                    partnerCard(p)
                    sendCard
                    if let last = model.recentTouches().first { lastTouchCard(last) }
                } else {
                    Button("Add a partner") { people = true }
                        .buttonStyle(AccentButtonStyle(height: 56))
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    private func partnerCard(_ p: Partner) -> some View {
        Button { partnerSheet = true } label: {
            HStack(spacing: 14) {
                PartnerFace(partner: p, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.displayName).font(Theme.font(20, .heavy)).foregroundStyle(Theme.title)
                    Text(statusLine(p)).font(Theme.font(13)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    if let us = usLine(p) {
                        Text(us).font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glass(cornerRadius: Theme.cardCorner)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Partner details")
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Send a touch").font(Theme.font(17, .bold)).foregroundStyle(Theme.title)
                Spacer()
                Button("Full screen") { compose = true }
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent)
            }
            InlineTouchPad(shape: .bar, title: "Touch", hint: "tap & slide").frame(height: 72)
            MeaningChipRow()
        }
        .padding(18)
        .glass(cornerRadius: Theme.cardCorner)
    }

    private func lastTouchCard(_ last: TouchMessage) -> some View {
        Button { history = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isMine(last) ? "You sent" : "From \(model.selectedPartner?.displayName ?? "them")")
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.title)
                    Text(last.sentAt.formatted(.relative(presentation: .named)))
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
                .frame(width: 96, alignment: .leading)
                TouchGlyph(touch: last, height: 34).frame(maxWidth: .infinity)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.subtitle)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .glass(cornerRadius: Theme.cardCorner)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent touches")
    }

    /// "Online · 63° partly cloudy in Paris"
    private func statusLine(_ p: Partner) -> String {
        var parts = [model.statusText(p)]
        if Feature.weather.isOn, let w = model.weather(for: p) {
            parts.append("\(WeatherInfo.degrees(w.temp)) \(w.summary.lowercased())" + (w.place.map { " in \($0)" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }

    /// "412 days together · Birthday in 40 days"
    private func usLine(_ p: Partner) -> String? {
        let space = together.space(p.id)
        var parts: [String] = []
        if let since = space.togetherSince { parts.append("\(TogetherSpace.days(since: since).formatted()) days together") }
        if Feature.dates.isOn, let next = space.dates.filter({ !$0.deleted }).min(by: { $0.daysUntil() < $1.daysUntil() }),
           next.daysUntil() <= 60 {
            parts.append(next.daysUntil() == 0 ? "\(next.title) today" : "\(next.title) in \(next.daysUntil()) days")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
