import SwiftUI

/// Timeline: a glowing line down the middle — their touches on the left, yours on the
/// right, in time order — so you see the rhythm of your day together. A floating button
/// opens the touch bar.
struct TimelineHome: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let p = model.selectedPartner {
                    Button { partnerSheet = true } label: { PartnerFace(partner: p, size: 46) }.buttonStyle(.plain)
                }
                VStack(spacing: 2) {
                    PartnerBar().frame(height: 48)
                    Text([model.distanceText(to: model.selectedPartner), store.meetText(for: model.selectedPartnerID)]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle).lineLimit(1)
                    TogetherChip()
                }
                .frame(maxWidth: .infinity)
                MyFace(size: 46)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    let touches = model.recentTouches(limit: 50)
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.magenta, Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 2)
                            .shadow(color: Theme.accent, radius: 6)
                            .frame(maxHeight: .infinity)
                        VStack(spacing: 14) {
                            if touches.isEmpty {
                                Text("No touches yet today.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                                    .padding(.top, 40).padding(8).glass(cornerRadius: 12)
                            }
                            ForEach(Array(touches.enumerated()), id: \.element.id) { i, t in
                                if i == 0 || !Calendar.current.isDate(t.sentAt, inSameDayAs: touches[i - 1].sentAt) {
                                    Text(day(t.sentAt)).font(Theme.font(12, .heavy)).foregroundStyle(Theme.title)
                                        .padding(.horizontal, 12).padding(.vertical, 4).glass(Capsule())
                                }
                                node(t)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)

                HStack(spacing: 10) {
                    HeartbeatButton(size: 54)
                    Button { compose = true } label: {
                        Image(systemName: "hand.tap.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(LinearGradient(colors: [Theme.p.accentTop, Theme.accentDeep], startPoint: .top, endPoint: .bottom)))
                            .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.selectedPartner == nil)
                    .accessibilityLabel("Send a touch")
                }
                .padding(.trailing, 20).padding(.bottom, 8)
            }
        }
        .padding(.bottom, 12)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
    }

    private func node(_ t: TouchMessage) -> some View {
        let mine = model.isMine(t)
        let tag = model.meaningTag(for: t)
        let content = Button { model.feel(t) } label: {
            VStack(alignment: mine ? .leading : .trailing, spacing: 3) {
                Text(t.sentAt.formatted(date: .omitted, time: .shortened)).font(Theme.font(10, .heavy)).foregroundStyle(Theme.subtitle)
                VStack(alignment: .leading, spacing: 2) {
                    if let bpm = t.heartbeatBPM {
                        Text("♥ \(bpm)").font(Theme.font(11, .heavy)).foregroundStyle(Theme.title)
                    } else if let tag {
                        Text("\(tag.emoji) \(tag.label)").font(Theme.font(11, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                    }
                    TouchGlyph(touch: t, height: 32).frame(width: 118)
                }
                .padding(8).glass(cornerRadius: 16)
            }
        }
        .buttonStyle(.plain)

        return HStack(spacing: 0) {
            Group { if mine { Color.clear } else { content } }.frame(maxWidth: .infinity, alignment: .trailing)
            Circle().fill(Theme.title).frame(width: 12, height: 12)
                .shadow(color: Color(rgbInt: t.colorRGB), radius: 6)
                .padding(.horizontal, 10)
            Group { if mine { content } else { Color.clear } }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
    }

    private func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month())
    }
}
