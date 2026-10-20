import SwiftUI

/// Bento: everything at a glance as tiles — the partner and their bracelet, how far apart,
/// days until you meet, their last heartbeat, the last touch, meanings as big buttons, and
/// a wide touch tile to send right there.
struct BentoHome: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @EnvironmentObject var together: TogetherStore
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    private let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Hi \(store.profile.name.isEmpty ? "there" : store.profile.name)")
                    .font(Theme.font(26, .heavy)).foregroundStyle(Theme.title).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                PartnerBar()
                RoundIconButton(icon: "person.2.fill", label: "People", size: 42) { people = true }
            }
            .padding(.horizontal, 16).padding(.top, 8)

            ScrollView {
                VStack(spacing: 10) {
                    if let p = model.selectedPartner {
                        HStack(spacing: 10) {
                            partnerTile(p)
                            VStack(spacing: 10) {
                                stat("Apart", model.distanceText(to: p)?.replacingOccurrences(of: " apart", with: "") ?? "—")
                                stat("Meet", store.meetText(for: p.id) ?? "Set a date")
                            }
                        }
                        .frame(height: 160)
                        togetherTile(p)
                        WeatherButton(partner: p)
                        heartbeatTile(p)
                        lastTouchTile
                    }
                    let meanings = Array(model.currentMeanings.prefix(4))
                    if !meanings.isEmpty {
                        LazyVGrid(columns: grid, spacing: 10) {
                            ForEach(meanings) { m in meaningTile(m) }
                        }
                    }
                    InlineTouchPad(shape: .bar, title: "Send a touch", hint: "tap & slide right here")
                        .frame(height: 70)
                    Color.clear.frame(height: 4)
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, TabBarSpace.fixed)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    private func partnerTile(_ p: Partner) -> some View {
        Button { partnerSheet = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                PartnerFace(partner: p, size: 50)
                Spacer(minLength: 4)
                Text(p.displayName).font(Theme.font(20, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                Text(p.online ? "Online" : "Offline").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                if let b = p.presence?.braceletBattery, p.presence?.bracelet == true {
                    Text("Bracelet \(b)% · on").font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                } else if p.presence?.watchStandIn == true {
                    Text("Watch standing in").font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glass(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func togetherTile(_ p: Partner) -> some View {
        if let since = together.space(p.id).togetherSince {
            VStack(spacing: 6) {
                TogetherCounter(since: since)
                if let next = together.space(p.id).dates.filter({ !$0.deleted }).min(by: { $0.daysUntil() < $1.daysUntil() }) {
                    SpecialDateRow(date: next)
                }
            }
            .padding(14).frame(maxWidth: .infinity)
            .glass(cornerRadius: 24)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            Text(value).font(Theme.font(18, .heavy)).foregroundStyle(Theme.title).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glass(cornerRadius: 24)
    }

    @ViewBuilder private func heartbeatTile(_ p: Partner) -> some View {
        let beat = model.recentTouches().first { $0.heartbeatBPM != nil && !model.isMine($0) }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(p.displayName)'s heartbeat").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    Spacer()
                    if let bpm = beat?.heartbeatBPM {
                        Text("\(bpm) BPM").font(Theme.font(15, .heavy)).foregroundStyle(Theme.pink)
                    }
                }
                if let beat, let bpm = beat.heartbeatBPM {
                    EKGView(bpm: bpm, colorRGB: beat.colorRGB, start: model.heartbeatStart(for: beat), lineWidth: 2.2).frame(height: 40)
                } else {
                    Text("None yet — send yours →").font(Theme.font(13, .semibold)).foregroundStyle(Theme.title)
                        .frame(height: 40)
                }
            }
            HeartbeatButton(size: 56, cornerRadius: 18)
        }
        .padding(14)
        .glass(cornerRadius: 24)
    }

    @ViewBuilder private var lastTouchTile: some View {
        if let last = model.recentTouches().first {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last touch · \(last.sentAt.formatted(.relative(presentation: .named)))")
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    Spacer()
                    Button { model.feel(last) } label: {
                        Label("Replay", systemImage: "play.fill").font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    Button { history = true } label: {
                        Text("All").font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain).padding(.leading, 8)
                }
                TouchGlyph(touch: last, height: 44)
            }
            .padding(14)
            .glass(cornerRadius: 24)
        }
    }

    private func meaningTile(_ m: TouchMeaning) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task { await model.sendMeaning(m) }
        } label: {
            Text("\(m.emoji.isEmpty ? "" : m.emoji + " ")\(m.label)")
                .font(Theme.font(15, .heavy)).foregroundStyle(Theme.title).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: 58)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(rgbInt: m.colorRGB).opacity(0.35), Color(rgbInt: m.endColorRGB).opacity(0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .glass(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send \(m.label)")
    }
}
