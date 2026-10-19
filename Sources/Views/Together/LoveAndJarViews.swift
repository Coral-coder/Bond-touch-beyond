import SwiftUI

/// Love-language check-in: each of you says how full you feel in each love language this
/// week and what you'd love more of; you see both side by side.
struct LoveLanguageView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var levels: [String: Int] = [:]
    @State private var wish = ""
    @State private var saved = false

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var checks: [LoveCheck] { syncLive(together.space(id).loveChecks).sorted { $0.created > $1.created } }
    private func latest(_ role: String) -> LoveCheck? { checks.first { $0.by == role } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                myCheck
                compare
                history
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Love languages")
        .onAppear {
            if let mine = latest(me) { levels = mine.levels }
        }
    }

    private var myCheck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How full is your cup this week?").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
            ForEach(LoveLanguage.allCases) { l in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(l.emoji) \(l.title)").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                    HStack(spacing: 6) {
                        ForEach(0..<6, id: \.self) { n in
                            let on = (levels[l.rawValue] ?? 0) >= n && n > 0
                            Button { levels[l.rawValue] = n; saved = false } label: {
                                Image(systemName: n == 0 ? "xmark.circle" : (on ? "heart.fill" : "heart"))
                                    .font(.system(size: 20)).foregroundStyle(on ? Theme.pink : Theme.subtitle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            TextField("What would you love more of?", text: $wish, axis: .vertical)
                .font(Theme.font(14)).padding(10).glass(cornerRadius: 14)
            Button(saved ? "Shared 💗" : "Share with \(model.selectedPartner?.displayName ?? "your partner")") { save() }
                .buttonStyle(AccentButtonStyle(height: 46)).disabled(saved)
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var compare: some View {
        let mine = latest(me), theirs = latest(me == "A" ? "B" : "A")
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Text("You").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle).frame(width: 70)
                Text(model.selectedPartner?.displayName ?? "Them").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                    .frame(width: 70).lineLimit(1)
            }
            ForEach(LoveLanguage.allCases) { l in
                HStack {
                    Text("\(l.emoji) \(l.title)").font(Theme.font(13)).foregroundStyle(Theme.title)
                    Spacer()
                    meter(mine?.levels[l.rawValue]).frame(width: 70)
                    meter(theirs?.levels[l.rawValue]).frame(width: 70)
                }
            }
            if let w = theirs?.wish, !w.isEmpty {
                Text("\(model.selectedPartner?.displayName ?? "They") would love more of: \(w)")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent)
            }
            if let lowest = theirs.flatMap({ t in LoveLanguage.allCases.min { (t.levels[$0.rawValue] ?? 0) < (t.levels[$1.rawValue] ?? 0) } }) {
                Text("Idea: their \(lowest.title.lowercased()) cup is lowest — \(Self.idea(lowest))")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func meter(_ n: Int?) -> some View {
        Text(n.map { String(repeating: "♥", count: $0) + String(repeating: "·", count: 5 - $0) } ?? "—")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.pink)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !checks.isEmpty {
                Text("Past check-ins").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
            }
            ForEach(checks.prefix(10)) { c in
                let avg = Double(c.levels.values.reduce(0, +)) / Double(max(1, c.levels.count))
                HStack {
                    Text(c.by == me ? "You" : (model.selectedPartner?.displayName ?? "Them")).font(Theme.font(13, .bold))
                    Text(c.created.formatted(date: .abbreviated, time: .omitted)).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    Spacer()
                    Text(String(format: "%.1f / 5", avg)).font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                }
                .foregroundStyle(Theme.title)
            }
        }
    }

    private func save() {
        let check = LoveCheck(by: me, levels: levels, wish: wish.trimmingCharacters(in: .whitespacesAndNewlines))
        together.edit(id, note: "shared a love-language check-in 💗") { syncAppend(&$0.loveChecks, check) }
        wish = ""
        saved = true
    }

    static func idea(_ l: LoveLanguage) -> String {
        switch l {
        case .words: return "leave them a note in the appreciation jar."
        case .time: return "spin the date roulette."
        case .touch: return "send a long hold touch, or plan a cuddle."
        case .acts: return "take a to-do off their list."
        case .gifts: return "a small surprise, even a flower."
        }
    }
}

/// The appreciation jar: drop in little notes for the other one; they open one whenever they
/// need a lift. Notes stay folded (and out of notifications) until opened.
struct AppreciationJarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var text = ""
    @State private var shown: Appreciation?

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var notes: [Appreciation] { syncLive(together.space(id).appreciations) }
    private var forMe: [Appreciation] { notes.filter { $0.by != me } }
    private var unopened: [Appreciation] { forMe.filter { !$0.opened } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                jar
                Button(unopened.isEmpty ? "No new notes yet" : "Open a note (\(unopened.count))") { openOne() }
                    .buttonStyle(AccentButtonStyle(height: 50)).disabled(unopened.isEmpty)
                if let shown {
                    VStack(spacing: 8) {
                        Text("💌").font(.system(size: 34))
                        Text(shown.text).font(Theme.font(18, .bold)).foregroundStyle(Theme.title).multilineTextAlignment(.center)
                        Text(shown.created.formatted(date: .abbreviated, time: .omitted)).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                    }
                    .padding(20).frame(maxWidth: .infinity).glass(cornerRadius: Theme.cardCorner)
                    .transition(.scale.combined(with: .opacity))
                }
                write
                if !forMe.filter(\.opened).isEmpty { opened }
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Appreciation jar")
    }

    private var jar: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 2))
                .frame(width: 170, height: 200)
            VStack(spacing: -6) {
                ForEach(0..<min(12, unopened.count), id: \.self) { i in
                    Text(["💌", "💗", "📝", "💛"][i % 4]).font(.system(size: 26))
                        .rotationEffect(.degrees(Double((i * 37) % 50) - 25))
                        .offset(x: CGFloat((i * 23) % 60) - 30)
                }
            }
            .padding(.bottom, 16)
            RoundedRectangle(cornerRadius: 8).fill(Color(rgbInt: 0xC08A5A)).frame(width: 120, height: 18).offset(y: -190)
        }
        .frame(height: 220)
        .overlay(alignment: .topTrailing) {
            Text("\(notes.filter { $0.by == me && !$0.opened }.count) of yours waiting for them")
                .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
        }
    }

    private var write: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write one for \(model.selectedPartner?.displayName ?? "them")").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            TextField("I love the way you…", text: $text, axis: .vertical)
                .font(Theme.font(15)).lineLimit(2...5).padding(10).glass(cornerRadius: 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["I love the way you…", "Thank you for…", "I felt so loved when…", "You make me laugh when…", "I'm proud of you for…"], id: \.self) { s in
                        Button(s) { text = s }.font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Theme.ink.opacity(0.1)))
                            .buttonStyle(.plain)
                    }
                }
            }
            Button("Drop it in the jar") {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                together.edit(id, note: "dropped a note in your appreciation jar 💌") { syncAppend(&$0.appreciations, Appreciation(by: me, text: t)) }
                text = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .buttonStyle(AccentButtonStyle(height: 44))
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var opened: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Opened").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
            ForEach(forMe.filter(\.opened).sorted { $0.edited > $1.edited }) { n in
                Text("“\(n.text)”").font(Theme.font(14)).foregroundStyle(Theme.title)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(cornerRadius: 14)
            }
        }
    }

    private func openOne() {
        guard let pick = unopened.randomElement() else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = pick }
        together.edit(id, note: "opened one of your appreciation notes 💗") { syncUpdate(&$0.appreciations, pick.id) { $0.opened = true } }
    }
}
