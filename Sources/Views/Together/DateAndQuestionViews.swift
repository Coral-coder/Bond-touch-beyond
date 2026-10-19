import SwiftUI

/// Date roulette: a shared list of date ideas (starters included); spin for one, filter by
/// cost or at home, and mark it done — done dates go to memory lane.
struct DateRouletteView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var spinning = false
    @State private var pick: DateIdea?
    @State private var flicker = 0
    @State private var maxCost = 2
    @State private var homeOnly = false
    @State private var newIdea = ""

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var ideas: [DateIdea] {
        let saved = together.space(id).dateIdeas
        if saved == nil {
            return DateIdea.starters.map { DateIdea(text: $0.0, emoji: $0.1, cost: $0.2, athome: $0.3) }
        }
        return syncLive(saved)
    }
    private var pool: [DateIdea] { ideas.filter { !$0.done && $0.cost <= maxCost && (!homeOnly || $0.athome) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                wheel
                filters
                Button(spinning ? "Spinning…" : "Spin 🎰") { spin() }
                    .buttonStyle(AccentButtonStyle(height: 52)).disabled(spinning || pool.isEmpty)
                if let pick, !spinning {
                    HStack(spacing: 10) {
                        Button("We did it! 🎉") { markDone(pick) }.buttonStyle(AccentButtonStyle(height: 44))
                        Button("Add to to-dos") {
                            together.edit(id, note: "picked a date idea 🎲") { $0.todos.append(TodoItem(text: "Date: \(pick.text)", by: me)) }
                        }
                        .font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
                    }
                }
                list
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Date roulette")
    }

    private var wheel: some View {
        let shown = spinning ? pool[safe: flicker % max(1, pool.count)] : pick
        return VStack(spacing: 8) {
            Text(shown?.emoji ?? "🎲").font(.system(size: 64))
            Text(shown?.text ?? "Spin for a date idea").font(Theme.font(20, .heavy)).foregroundStyle(Theme.title)
                .multilineTextAlignment(.center).frame(minHeight: 56)
            if let s = shown {
                Text([s.cost == 0 ? "Free" : s.cost == 1 ? "$" : "$$", s.athome ? "At home" : "Out"].joined(separator: " · "))
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(20).frame(maxWidth: .infinity).glass(cornerRadius: Theme.cardCorner)
    }

    private var filters: some View {
        HStack {
            Picker("Cost", selection: $maxCost) {
                Text("Free").tag(0); Text("Up to $").tag(1); Text("Any").tag(2)
            }
            .pickerStyle(.segmented)
            Toggle("Home", isOn: $homeOnly).toggleStyle(.button).tint(Theme.accent)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ideas (\(ideas.filter { !$0.done }.count))").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
            HStack {
                TextField("Add your own idea…", text: $newIdea).font(Theme.font(14)).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent) }
            }
            .padding(10).glass(cornerRadius: 14)
            ForEach(ideas.filter { !$0.done }) { idea in
                HStack {
                    Text(idea.emoji)
                    Text(idea.text).font(Theme.font(14)).foregroundStyle(Theme.title)
                    Spacer()
                    Button { remove(idea) } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.subtitle) }
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    /// Writes the starters into the shared list the first time anything changes.
    private func seed(_ s: inout TogetherSpace) {
        if s.dateIdeas == nil { s.dateIdeas = ideas }
    }

    private func add() {
        let t = newIdea.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        together.edit(id, note: "added a date idea 🎲") { s in seed(&s); syncAppend(&s.dateIdeas, DateIdea(text: t, by: me)) }
        newIdea = ""
    }

    private func remove(_ idea: DateIdea) {
        together.edit(id) { s in seed(&s); syncDelete(&s.dateIdeas, idea.id) }
    }

    private func markDone(_ idea: DateIdea) {
        together.edit(id, note: "marked a date as done 🎉") { s in
            seed(&s)
            syncUpdate(&s.dateIdeas, idea.id) { $0.done = true; $0.doneAt = Date() }
            syncAppend(&s.memories, Memory(by: me, title: idea.text, date: Date(), emoji: idea.emoji))
        }
        pick = nil
    }

    private func spin() {
        guard !pool.isEmpty else { return }
        spinning = true
        let final = pool.randomElement()
        var steps = 0
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
            steps += 1
            flicker += 1
            UISelectionFeedbackGenerator().selectionChanged()
            if steps >= 22 {
                t.invalidate()
                pick = final
                spinning = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Question of the day: the same question on both phones; your partner's answer shows once
/// you've answered too.
struct QuestionOfDayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var text = ""

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var answers: [QuestionAnswer] { syncLive(together.space(id).answers) }
    private var today: String { DailyQuestion.key() }

    var body: some View {
        let mine = answers.first { $0.day == today && $0.by == me }
        let theirs = answers.first { $0.day == today && $0.by != me }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's question").font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
                    Text(DailyQuestion.question()).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                    if let mine {
                        answerRow("You", mine.text)
                    } else {
                        TextField("Your answer…", text: $text, axis: .vertical)
                            .font(Theme.font(15)).lineLimit(2...6).padding(10).glass(cornerRadius: 14)
                        Button("Answer") { answer() }.buttonStyle(AccentButtonStyle(height: 44))
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let theirs {
                        if mine != nil { answerRow(model.selectedPartner?.displayName ?? "Them", theirs.text) }
                        else { Text("🔒 \(model.selectedPartner?.displayName ?? "They") answered — answer to see theirs")
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent) }
                    } else if mine != nil {
                        Text("Waiting for \(model.selectedPartner?.displayName ?? "them") to answer…").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                    }
                }
                .padding(16).glass(cornerRadius: Theme.cardCorner)
                past
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Question of the day")
    }

    private func answerRow(_ who: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(who).font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
            Text(text).font(Theme.font(15)).foregroundStyle(Theme.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(cornerRadius: 14)
    }

    private var past: some View {
        let days = Array(Set(answers.map(\.day))).filter { $0 != today }.sorted(by: >)
        return VStack(alignment: .leading, spacing: 10) {
            if !days.isEmpty { Text("Earlier").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title) }
            ForEach(days.prefix(30), id: \.self) { day in
                let mine = answers.first { $0.day == day && $0.by == me }
                VStack(alignment: .leading, spacing: 6) {
                    Text(DailyQuestion.question(forKey: day)).font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                    ForEach(answers.filter { $0.day == day }) { a in
                        // Theirs only if you answered that day too.
                        if a.by == me || mine != nil {
                            Text("\(a.by == me ? "You" : (model.selectedPartner?.displayName ?? "Them")): \(a.text)")
                                .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                        }
                    }
                    Text(day).font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(cornerRadius: 14)
            }
        }
    }

    private func answer() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        together.edit(id, note: "answered today's question 💭") { syncAppend(&$0.answers, QuestionAnswer(day: today, by: me, text: t)) }
        text = ""
    }
}
