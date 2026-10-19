import SwiftUI

/// Memory lane: moments you want to keep, plus "on this day" from past years — your
/// memories, finished dates and R.A.D.A.R. check-ins on one timeline.
struct MemoryLaneView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var adding = false

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var memories: [Memory] { syncLive(together.space(id).memories).sorted { $0.date > $1.date } }

    private var onThisDay: [Memory] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: Date())
        return memories.filter {
            let c = cal.dateComponents([.month, .day, .year], from: $0.date)
            return c.month == today.month && c.day == today.day && c.year != cal.component(.year, from: Date())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !onThisDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On this day").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                        ForEach(onThisDay) { m in card(m, highlight: true) }
                    }
                }
                if let since = together.space(id).togetherSince {
                    Text("\(TogetherSpace.days(since: since).formatted()) days of memories so far")
                        .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent)
                }
                if memories.isEmpty {
                    Text("Add the moments you want to keep — first kiss, trips, silly days. Finished dates from Date roulette land here too.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtitle).padding(16).glass(cornerRadius: Theme.cardCorner)
                }
                let years = Dictionary(grouping: memories) { Calendar.current.component(.year, from: $0.date) }
                ForEach(years.keys.sorted(by: >), id: \.self) { y in
                    Text(String(y)).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title).padding(.top, 4)
                    ForEach(years[y] ?? []) { m in card(m, highlight: false) }
                }
            }
            .padding(16)
        }
        .navigationTitle("Memory lane")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { MemoryEditor() }
    }

    private func card(_ m: Memory, highlight: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(m.emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                Text(m.date.formatted(date: .long, time: .omitted)).font(Theme.font(12)).foregroundStyle(highlight ? Theme.accent : Theme.subtitle)
                if !m.text.isEmpty { Text(m.text).font(Theme.font(14)).foregroundStyle(Theme.title) }
            }
            Spacer()
        }
        .padding(14).glass(cornerRadius: 18)
        .contextMenu {
            Button("Remove", role: .destructive) { together.edit(id) { syncDelete(&$0.memories, m.id) } }
        }
    }
}

struct MemoryEditor: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var date = Date()
    @State private var emoji = "📸"

    var body: some View {
        NavigationStack {
            Form {
                TextField("What happened?", text: $title)
                Picker("Emoji", selection: $emoji) {
                    ForEach(["📸", "💋", "✈️", "🏖️", "🎂", "🏡", "🎉", "🌧️", "🍰", "🎶", "💍", "🐶"], id: \.self) { Text($0).tag($0) }
                }
                DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("The details you want to remember…", text: $text, axis: .vertical).lineLimit(3...8)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New memory").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id = model.selectedPartnerID
                        let t = title.trimmingCharacters(in: .whitespaces)
                        let m = Memory(by: model.myRole(id), title: t.isEmpty ? "A good day" : t, date: date, emoji: emoji, text: text)
                        together.edit(id, note: "added a memory 📸") { syncAppend(&$0.memories, m) }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Co-op games

/// Story together: write a story a sentence at a time, taking turns.
struct StoryTogetherView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var text = ""

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var all: [StoryLine] { syncLive(together.space(id).story).sorted { $0.created < $1.created } }
    private var current: UUID? { all.last?.story }
    private var lines: [StoryLine] { fresh ? [] : all.filter { $0.story == current } }
    private var myTurn: Bool { lines.last?.by != me }

    private static let openers = [
        "Once upon a time, two people found a door that shouldn't have been there.",
        "The postcard arrived with no stamp, just one word: “Come.”",
        "Nobody believed the cat could talk, until that Tuesday.",
        "The lighthouse had been dark for fifty years, and tonight it blinked.",
        "We only meant to buy milk.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if lines.isEmpty {
                    Text("Start a story — then take turns adding a sentence.").font(Theme.font(14)).foregroundStyle(Theme.subtitle)
                    ForEach(Self.openers, id: \.self) { o in
                        Button { add(o, newStory: true) } label: {
                            Text(o).font(Theme.font(14, .semibold)).foregroundStyle(Theme.title).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12).glass(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { l in
                            Text(l.text).font(Theme.font(16)).foregroundStyle(l.by == me ? Theme.title : Theme.accent)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
                    Text("Your lines plain, \(model.selectedPartner?.displayName ?? "theirs") in colour · \(lines.count) sentences")
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                if !lines.isEmpty {
                    if myTurn {
                        TextField("And then…", text: $text, axis: .vertical)
                            .font(Theme.font(15)).lineLimit(1...4).padding(10).glass(cornerRadius: 14)
                        Button("Add my sentence") { add(text, newStory: false) }
                            .buttonStyle(AccentButtonStyle(height: 44))
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Text("Waiting for \(model.selectedPartner?.displayName ?? "them") to add the next line…")
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.subtitle)
                    }
                    Button("Start a new story") { text = ""; fresh = true }
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(16)
        }
        .navigationTitle("Story together")
    }

    /// Showing the openers for a new story.
    @State private var fresh = false

    private func add(_ t: String, newStory: Bool) {
        let line = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let story = (newStory || fresh) ? UUID() : (current ?? UUID())
        together.edit(id, note: "added a line to your story — your turn ✍️") { syncAppend(&$0.story, StoryLine(by: me, text: line, story: story)) }
        text = ""
        fresh = false
    }
}

/// Same Wavelength: both pick a side of a this-or-that without seeing the other's; you score
/// together for every match.
struct WavelengthView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var picks: [WavelengthPick] { syncLive(together.space(id).wavelength) }
    private func pick(_ q: Int, _ role: String) -> Int? { picks.first { $0.q == q && $0.by == role }?.pick }
    private var them: String { me == "A" ? "B" : "A" }

    /// The first question you haven't both answered.
    private var current: Int {
        (0..<Wavelength.questions.count).first { pick($0, me) == nil || pick($0, them) == nil } ?? Wavelength.questions.count
    }
    private var score: (match: Int, total: Int) {
        let both = (0..<Wavelength.questions.count).filter { pick($0, me) != nil && pick($0, them) != nil }
        return (both.filter { pick($0, me) == pick($0, them) }.count, both.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("\(score.match) / \(score.total) in sync").font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                if current < Wavelength.questions.count {
                    question(current)
                } else {
                    Text("You've done them all! \(score.match) matches").font(Theme.font(16, .bold)).foregroundStyle(Theme.accent)
                    Button("Play again") { together.edit(id) { s in for p in syncLive(s.wavelength) { syncDelete(&s.wavelength, p.id) } } }
                        .buttonStyle(AccentButtonStyle(height: 44))
                }
                results
            }
            .padding(16)
        }
        .navigationTitle("Same wavelength")
    }

    private func question(_ q: Int) -> some View {
        let options = Wavelength.questions[q]
        let mine = pick(q, me)
        return VStack(spacing: 12) {
            Text("Question \(q + 1) of \(Wavelength.questions.count)").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            HStack(spacing: 12) {
                option(options.0, q, 0, mine)
                Text("or").font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
                option(options.1, q, 1, mine)
            }
            if mine != nil {
                Text(pick(q, them) == nil ? "Locked in — waiting for \(model.selectedPartner?.displayName ?? "them")…" : "")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func option(_ title: String, _ q: Int, _ n: Int, _ mine: Int?) -> some View {
        Button {
            guard mine == nil else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            together.edit(id, note: "answered on Same wavelength — your turn 🌊") { syncAppend(&$0.wavelength, WavelengthPick(by: me, q: q, pick: n)) }
        } label: {
            Text(title).font(Theme.font(16, .heavy)).foregroundStyle(mine == n ? Theme.onAccent : Theme.title)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 80).padding(8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(mine == n ? Theme.accent : Theme.ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var results: some View {
        let done = (0..<Wavelength.questions.count).filter { pick($0, me) != nil && pick($0, them) != nil }.reversed()
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(done), id: \.self) { q in
                let a = pick(q, me) ?? 0, b = pick(q, them) ?? 0
                let opts = Wavelength.questions[q]
                HStack {
                    Image(systemName: a == b ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                        .font(.system(size: 13)).foregroundStyle(a == b ? Theme.lime : Theme.subtitle)
                    Text(a == b ? (a == 0 ? opts.0 : opts.1) : "You: \(a == 0 ? opts.0 : opts.1) · Them: \(b == 0 ? opts.0 : opts.1)")
                        .font(Theme.font(13)).foregroundStyle(Theme.title)
                    Spacer()
                }
            }
        }
    }
}
