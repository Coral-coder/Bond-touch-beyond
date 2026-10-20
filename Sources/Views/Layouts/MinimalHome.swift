import SwiftUI

/// Minimal: your partner, one line about them, the last touch, and one button to send a
/// touch. Everything else (weather, dates, meanings, history) is a tap away.
struct MinimalHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.subtitle)
                Spacer()
                PartnerBar()
            }
            .padding(.horizontal, 28).padding(.top, 8)

            if let p = model.selectedPartner {
                Button { partnerSheet = true } label: {
                    VStack(spacing: 12) {
                        PartnerFace(partner: p, size: 116)
                        Text(p.displayName).font(Theme.font(30, .heavy)).foregroundStyle(Theme.title)
                        Text(statusLine(p)).font(Theme.font(15)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 48)
                .accessibilityHint("Partner details")

                if let last = model.recentTouches().first {
                    Button { history = true } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(model.isMine(last) ? "You sent" : "Last touch") · \(last.sentAt.formatted(.relative(presentation: .named)))")
                                .font(Theme.font(12, .semibold)).foregroundStyle(Theme.subtitle)
                                .textCase(.uppercase).kerning(0.8)
                            TouchGlyph(touch: last, height: 44)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28).padding(.top, 56)
                    .accessibilityLabel("Recent touches")
                }

                Spacer(minLength: 20)

                Button { compose = true } label: {
                    Label("Send \(p.displayName) a touch", systemImage: "heart.fill")
                        .font(Theme.font(18, .bold))
                        .frame(maxWidth: .infinity).frame(height: 60)
                }
                .buttonStyle(AccentButtonStyle(height: 60))
                .padding(.horizontal, 28)
            } else {
                Spacer()
                Button("Add a partner") { people = true }
                    .buttonStyle(AccentButtonStyle(height: 56))
                    .padding(.horizontal, 28)
                Spacer()
            }
        }
        .padding(.bottom, TabBarSpace.fixed + 8)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    /// "Online · 63° in Paris"
    private func statusLine(_ p: Partner) -> String {
        var parts = [model.statusText(p)]
        if Feature.weather.isOn, let w = model.weather(for: p) {
            parts.append(WeatherInfo.degrees(w.temp) + (w.place.map { " in \($0)" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }
}
