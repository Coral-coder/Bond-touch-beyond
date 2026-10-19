import SwiftUI

/// R.A.D.A.R. — the relationship check-in from the Multiamory podcast, made for polyamory:
/// a regular, structured sit-down with each partner. **R**eview the time since the last one,
/// set the **A**genda, **D**iscuss each topic, agree **A**ction items, then **R**econnect.
/// Topics can be added by either of you any time; each partner has their own RADAR.
struct RadarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var topic = ""
    @State private var running = false

    private var id: String? { model.selectedPartnerID }
    private var space: TogetherSpace { together.space(id) }
    private var topics: [RadarTopic] { (space.radarTopics ?? []).filter { !$0.deleted && !$0.discussed } }
    private var sessions: [RadarSession] { (space.radarSessions ?? []).filter { !$0.deleted }.sorted { $0.created > $1.created } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                schedule
                agenda
                Button("Start a check-in with \(model.selectedPartner?.displayName ?? "your partner")") { running = true }
                    .buttonStyle(AccentButtonStyle(height: 52))
                if !sessions.isEmpty { history }
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("R.A.D.A.R.")
        .fullScreenCover(isPresented: $running) { RadarSessionView().screenBackground() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📡 Your regular check-in").font(Theme.font(18, .heavy)).foregroundStyle(Theme.title)
            let rows = [["R", "Review", "how things have been since last time"],
                        ["A", "Agenda", "pick what you both want to talk about"],
                        ["D", "Discuss", "one topic at a time, with a gentle timer"],
                        ["A", "Action items", "small, concrete next steps"],
                        ["R", "Reconnect", "end close — a touch, a hug, a plan"]]
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(rows[i][0]).font(Theme.font(18, .heavy)).foregroundStyle(Theme.accent).frame(width: 18)
                    (Text(rows[i][1]).bold() + Text(" — " + rows[i][2])).font(Theme.font(13)).foregroundStyle(Theme.title)
                }
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var schedule: some View {
        let every = space.radarEveryDays ?? 28
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Next check-in").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                if let next = space.radarNext {
                    Text(next.formatted(date: .abbreviated, time: .omitted)).font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
                }
            }
            Picker("How often", selection: Binding(get: { every }, set: { days in
                together.edit(id, note: "set your R.A.D.A.R. to every \(days / 7) weeks 📡") { s in
                    s.radarEveryDays = days
                    s.radarNext = Calendar.current.date(byAdding: .day, value: days,
                                                        to: s.radarSessions?.filter { !$0.deleted }.map(\.created).max() ?? Date())
                    s.radarEdited = Date()
                }
            })) {
                Text("Weekly").tag(7); Text("Every 2 weeks").tag(14); Text("Monthly").tag(28); Text("Every 2 months").tag(56)
            }
            .pickerStyle(.segmented)
            DatePicker("Or pick a day", selection: Binding(get: { space.radarNext ?? Date() }, set: { d in
                together.edit(id, note: "scheduled your R.A.D.A.R. for \(d.formatted(date: .abbreviated, time: .omitted)) 📡") { s in
                    s.radarNext = d; s.radarEdited = Date()
                }
            }), displayedComponents: .date)
            .font(Theme.font(14)).foregroundStyle(Theme.title)
            Text("You'll both get a reminder the day before and on the day.").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agenda").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text("Add things as they come up — big or small. Either of you can.").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            HStack {
                TextField("Something to talk about…", text: $topic).onSubmit(add)
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.opacity(0.06)))
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent) }
                    .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(topics) { t in
                HStack {
                    Text("• \(t.text)").font(Theme.font(14)).foregroundStyle(Theme.title)
                    Spacer()
                    Text(t.by == model.myRole(id) ? "you" : (model.selectedPartner?.displayName ?? "them"))
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    Button {
                        together.edit(id) { s in
                            if let i = s.radarTopics?.firstIndex(where: { $0.id == t.id }) { s.radarTopics?[i].deleted = true; s.radarTopics?[i].edited = Date() }
                        }
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtitle) }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func add() {
        let t = topic.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        together.edit(id, note: "added a topic for your next R.A.D.A.R. 📡") { s in
            s.radarTopics = (s.radarTopics ?? []) + [RadarTopic(text: t, by: model.myRole(id))]
        }
        topic = ""
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past check-ins").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            ForEach(sessions) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.created.formatted(date: .long, time: .omitted)).font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                    if !s.discussed.isEmpty { Text("Talked about: " + s.discussed.joined(separator: ", ")).font(Theme.font(12)).foregroundStyle(Theme.subtitle) }
                    ForEach(s.actions, id: \.self) { a in Text("✅ \(a)").font(Theme.font(12)).foregroundStyle(Theme.title) }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }
}

/// A check-in, step by step.
struct RadarSessionView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var session = RadarSession()
    @State private var chosen: Set<UUID> = []
    @State private var current = 0
    @State private var timerEnd: Date?
    @State private var action = ""

    private var id: String? { model.selectedPartnerID }
    private var topics: [RadarTopic] { (together.space(id).radarTopics ?? []).filter { !$0.deleted && !$0.discussed } }
    private static let steps = ["Review", "Agenda", "Discuss", "Action items", "Reconnect"]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Close") { dismiss() }.foregroundStyle(Theme.title)
                Spacer()
                Text("\(step + 1) of 5 · \(Self.steps[step])").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Color.clear.frame(width: 50)
            }
            ProgressView(value: Double(step + 1), total: 5).tint(Theme.accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case 0: review
                    case 1: agendaStep
                    case 2: discuss
                    case 3: actions
                    default: reconnect
                    }
                }
                .padding(.vertical, 4)
            }
            HStack(spacing: 12) {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(GlassButtonStyle(height: 50)) }
                Button(step == 4 ? "Finish" : "Next") { next() }.buttonStyle(AccentButtonStyle(height: 50))
            }
        }
        .padding(16)
        .onAppear { chosen = Set(topics.map(\.id)) }
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
            TextField(prompt, text: text, axis: .vertical).lineLimit(2...6)
                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.opacity(0.06)))
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Look back together since your last check-in. Take turns; just listen.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            field("Highlights 🌟", "What felt good, what you appreciated…", $session.highlights)
            field("Challenges 🌧️", "What was hard, what you missed…", $session.challenges)
            field("Coming up 📅", "Trips, busy weeks, dates with other partners…", $session.comingUp)
        }
    }

    private var agendaStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick what to talk about today. Anything not picked waits for next time.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            if topics.isEmpty { Text("No topics yet — that's fine. You can still review and reconnect.").font(Theme.font(14)).foregroundStyle(Theme.title) }
            ForEach(topics) { t in
                Button {
                    if chosen.contains(t.id) { chosen.remove(t.id) } else { chosen.insert(t.id) }
                } label: {
                    HStack {
                        Image(systemName: chosen.contains(t.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                        Text(t.text).font(Theme.font(15)).foregroundStyle(Theme.title)
                        Spacer()
                    }
                    .padding(12).glass(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var picked: [RadarTopic] { topics.filter { chosen.contains($0.id) } }

    private var discuss: some View {
        VStack(alignment: .leading, spacing: 12) {
            if picked.isEmpty {
                Text("Nothing on the agenda — move on to action items.").font(Theme.font(14)).foregroundStyle(Theme.title)
            } else {
                let t = picked[min(current, picked.count - 1)]
                Text("Topic \(min(current, picked.count - 1) + 1) of \(picked.count)").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                Text(t.text).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = timerEnd.map { max(0, Int($0.timeIntervalSince(ctx.date))) }
                    HStack {
                        Text(left.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "10:00")
                            .font(Theme.font(34, .heavy)).monospacedDigit().foregroundStyle(left == 0 ? Theme.amber : Theme.accent)
                        Spacer()
                        Button(timerEnd == nil ? "Start timer" : "Restart") { timerEnd = Date().addingTimeInterval(600) }
                            .buttonStyle(GlassButtonStyle(height: 40)).frame(width: 130)
                    }
                }
                Text("Speak from your own feelings; listen to understand, not to answer.").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                field("Notes", "What you heard, what you agreed…", $session.notes)
                HStack {
                    Button("Previous") { current = max(0, current - 1); timerEnd = nil }.disabled(current == 0)
                    Spacer()
                    Button("Next topic") { current = min(picked.count - 1, current + 1); timerEnd = nil }.disabled(current >= picked.count - 1)
                }
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Small, concrete next steps. They'll also go on your shared to-do list.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            HStack {
                TextField("e.g. Plan a date night for Friday", text: $action).onSubmit(addAction)
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.opacity(0.06)))
                Button(action: addAction) { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent) }
            }
            ForEach(session.actions, id: \.self) { a in Text("✅ \(a)").font(Theme.font(15)).foregroundStyle(Theme.title) }
        }
    }

    private func addAction() {
        let a = action.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return }
        session.actions.append(a)
        action = ""
    }

    private var reconnect: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("End close. Pick something to do right after:").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            ForEach(["A long hug 🤗", "Send each other a touch 💞", "Plan your next date 🍝", "A walk together 🚶",
                     "Say one thing you love about them 💬", "Cuddle and a film 🎬"], id: \.self) { idea in
                Button { session.reconnect = idea } label: {
                    HStack {
                        Text(idea).font(Theme.font(15)).foregroundStyle(Theme.title)
                        Spacer()
                        if session.reconnect == idea { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .padding(12).glass(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func next() {
        guard step == 4 else { step += 1; return }
        session.discussed = picked.map(\.text)
        session.created = Date(); session.edited = Date()
        let me = model.myRole(id)
        let done = Set(picked.map(\.id))
        together.edit(id, note: "saved your R.A.D.A.R. check-in 📡") { s in
            s.radarSessions = (s.radarSessions ?? []) + [session]
            for i in (s.radarTopics ?? []).indices where done.contains(s.radarTopics![i].id) {
                s.radarTopics![i].discussed = true; s.radarTopics![i].edited = Date()
            }
            s.todos += session.actions.map { TodoItem(text: $0, by: me) }
            s.radarNext = Calendar.current.date(byAdding: .day, value: s.radarEveryDays ?? 28, to: Date())
            s.radarEdited = Date()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
