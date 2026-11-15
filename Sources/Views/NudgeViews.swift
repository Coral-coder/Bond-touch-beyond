import SwiftUI

/// On a partner's page: your streak together, and when to be reminded to reach out.
struct StreakCard: View {
    @EnvironmentObject var model: AppModel
    let partner: Partner
    @State private var interval = NudgeInterval.default

    var body: some View {
        let log = model.contactLog(partner.id)
        let streak = log.streak()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(streak > 0 ? "🔥" : "✨").font(.system(size: Theme.s(30)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(streak > 0 ? "\(streak) day\(streak == 1 ? "" : "s") in touch" : "Start a streak")
                        .font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                    Text(subtitle(log, streak))
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
            }
            Divider().overlay(Theme.ink.opacity(0.1))
            HStack {
                Label("Remind me after", systemImage: "hourglass")
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.title)
                Spacer()
                Picker("Remind me after", selection: $interval) {
                    ForEach(NudgeInterval.choices, id: \.self) { Text(NudgeInterval.title($0)).tag($0) }
                }
                .pickerStyle(.menu).tint(Theme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 22)
        .onAppear { interval = NudgeInterval.days(for: partner.id) }
        .onChange(of: interval) { days in
            NudgeInterval.set(days, for: partner.id)
            model.scheduleNudgesSoon()
        }
    }

    private func subtitle(_ log: ContactLog, _ streak: Int) -> String {
        if streak == 0 { return "A touch, kiss or message each day keeps it going. Missing a day just starts it again." }
        let best = max(log.bestStreak, streak)
        let today = log.inTouchToday ? "Today counts ✓" : "Reach out today to keep it going"
        return best > streak ? "\(today) · best \(best) days" : today
    }
}

/// People, with more than one partner: who you reached out to this week, privately.
struct BalanceCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let rows = model.balance()
        let top = max(1, rows.map { max($0.sent, $0.received) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Text("Only you see this").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
            ForEach(rows, id: \.partner.id) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.partner.displayName).font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                        let streak = model.contactLog(row.partner.id).streak()
                        if streak > 1 { Text("🔥\(streak)").font(Theme.font(12, .bold)) }
                        Spacer()
                        Text("you \(row.sent) · them \(row.received)")
                            .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    }
                    bar(row.sent, of: top, color: Color(rgbInt: model.store.profile.colorRGB))
                    bar(row.received, of: top, color: Color(rgbInt: row.partner.colorRGB))
                }
            }
            if let summary = model.balanceSummary(), summary.contains("missing you") {
                Text(summary.components(separatedBy: ". ").last ?? summary)
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 22)
    }

    private func bar(_ value: Int, of top: Int, color: Color) -> some View {
        GeometryReader { geo in
            Capsule().fill(Theme.ink.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: max(value > 0 ? 6 : 0, geo.size.width * CGFloat(value) / CGFloat(top)))
                }
        }
        .frame(height: 6)
    }
}
