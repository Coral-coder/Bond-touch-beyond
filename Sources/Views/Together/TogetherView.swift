import SwiftUI

/// Us: the space the two of you share — how long you've been together (counting live),
/// anniversaries and birthdays (with reminders), what each of you likes, and shared to-dos,
/// notes, a whiteboard and chess. Everything syncs with your partner through iCloud.
struct TogetherView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @EnvironmentObject var store: LocalStore
    @State private var pickingStart = false
    @State private var addingDate = false
    @State private var editingDate: SpecialDate?

    private var partner: Partner? { model.selectedPartner }
    private var space: TogetherSpace { together.space(model.selectedPartnerID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Us").font(Theme.font(30, .heavy)).foregroundStyle(Theme.title)
                    Spacer()
                    PartnerBar()
                }
                .padding(.top, 8)

                if let partner {
                    if partner.bond.legacy {
                        Text("The Us space works with partners paired over iCloud.")
                            .font(Theme.font(14)).foregroundStyle(Theme.subtitle).padding().glass(cornerRadius: 20)
                    } else {
                        header(partner)
                        if Feature.dates.isOn { datesCard }
                        if Feature.likes.isOn { likesCard(partner) }
                        tiles
                    }
                } else {
                    Text("Add a partner to start your Us space.")
                        .font(Theme.font(15)).foregroundStyle(Theme.subtitle).padding(.top, 40)
                }
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $pickingStart) { TogetherStartSheet() }
        .sheet(isPresented: $addingDate) { SpecialDateEditor(date: nil) }
        .sheet(item: $editingDate) { SpecialDateEditor(date: $0) }
    }

    // MARK: Header: you two and the live counter

    private func header(_ p: Partner) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: -10) {
                MyFace(size: 74)
                Image(systemName: "heart.fill").font(.system(size: 22)).foregroundStyle(Theme.pink)
                    .padding(8).background(Circle().fill(Theme.bgBottom)).zIndex(1)
                PartnerFace(partner: p, size: 74)
            }
            if let since = space.togetherSince {
                TogetherCounter(since: since)
                Button("Change date") { pickingStart = true }
                    .font(Theme.font(12, .semibold)).foregroundStyle(Theme.accent)
            } else {
                Button { pickingStart = true } label: {
                    Label("When did you get together?", systemImage: "heart.circle")
                        .font(Theme.font(16, .heavy)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18).frame(height: 46)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glass(cornerRadius: Theme.cardCorner)
    }

    // MARK: Dates

    private var datesCard: some View {
        let upcoming = space.dates.filter { !$0.deleted }.sorted { $0.daysUntil() < $1.daysUntil() }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Special dates").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                NavigationLink { SpecialDatesView().screenBackground() } label: {
                    Text("All").font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                }
                Button { addingDate = true } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Add a date")
            }
            if upcoming.isEmpty {
                Text("Add your anniversary and both birthdays — you'll get a reminder a week before and on the day.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            }
            ForEach(upcoming.prefix(3)) { d in
                Button { editingDate = d } label: { SpecialDateRow(date: d) }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .glass(cornerRadius: Theme.cardCorner)
    }

    // MARK: Likes

    private func likesCard(_ p: Partner) -> some View {
        NavigationLink { LikesView().screenBackground() } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What we like").font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                    let mine = space.likes.filter { !$0.deleted && $0.owner == model.myRole(p.id) }.count
                    let theirs = space.likes.filter { !$0.deleted && $0.owner != model.myRole(p.id) }.count
                    Text("You: \(mine) · \(p.displayName): \(theirs) — favourites, sizes, love languages…")
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.subtitle)
            }
            .padding(16)
            .glass(cornerRadius: Theme.cardCorner)
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared things

    private var tiles: some View {
        let open = space.todos.filter { !$0.deleted && !$0.done }.count
        let notes = space.notes.filter { !$0.deleted }.count
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            if Feature.todos.isOn { tile("To-do", "checklist", open == 0 ? "All done" : "\(open) to do", Theme.lime) { TodoListView() } }
            if Feature.notes.isOn { tile("Notes", "note.text", notes == 0 ? "Write one" : "\(notes) note\(notes == 1 ? "" : "s")", Theme.amber) { SharedNotesView() } }
            if Feature.whiteboard.isOn { tile("Whiteboard", "scribble.variable", "Draw together", Theme.magenta) { WhiteboardView() } }
            if Feature.games.isOn { tile("Games", "gamecontroller.fill", "Pool, chess, checkers, backgammon, Battleship", Theme.accent) { GamesView() } }
            if Feature.stress.isOn { tile("Stress & mood", "face.smiling", batteryStatus, Theme.lime) { BatteryView() } }
            if Feature.radar.isOn { tile("R.A.D.A.R.", "dot.radiowaves.left.and.right", radarStatus, Theme.pink) { RadarView() } }
        }
    }

    private var radarStatus: String {
        let open = (space.radarTopics ?? []).filter { !$0.deleted && !$0.discussed }.count
        if let next = space.radarNext {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                       to: Calendar.current.startOfDay(for: next)).day ?? 0
            return (days <= 0 ? "Check-in due" : "In \(days) days") + (open > 0 ? " · \(open) topics" : "")
        }
        return open > 0 ? "\(open) topics waiting" : "Set up check-ins"
    }

    private var batteryStatus: String {
        guard let m = model.selectedPartner?.presence?.mood else { return "How are you feeling?" }
        return "\(model.selectedPartner?.displayName ?? "They"): \(m.emoji) \(m.label) · \(Stress.face(m.stress).emoji)"
    }

    private var chessStatus: String {
        guard let game = space.chess else { return "Start a game" }
        let pos = ChessPosition.from(moves: game.moves)
        if game.resigned != nil { return "Game over" }
        switch pos.status {
        case .checkmate: return "Checkmate"
        case .stalemate: return "Stalemate"
        default:
            let myWhite = model.myRole(model.selectedPartnerID) == "A"
            return pos.whiteToMove == myWhite ? "Your move" : "Their move"
        }
    }

    private func tile<D: View>(_ title: String, _ icon: String, _ sub: String, _ tint: Color,
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination().screenBackground() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(title).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                Text(sub).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .glass(cornerRadius: Theme.cardCorner)
        }
        .buttonStyle(.plain)
    }
}

/// "Together for 1 year, 3 months, 12 days", with a live hours:minutes:seconds counter.
struct TogetherCounter: View {
    let since: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let days = TogetherSpace.days(since: since, to: ctx.date)
            let secs = Int(ctx.date.timeIntervalSince(since))
            VStack(spacing: compact ? 1 : 4) {
                Text(compact ? "Together \(days) days" : "Together for")
                    .font(Theme.font(compact ? 13 : 13, compact ? .heavy : .semibold))
                    .foregroundStyle(compact ? Theme.title : Theme.subtitle)
                if !compact {
                    Text(TogetherSpace.durationText(since: since, to: ctx.date))
                        .font(Theme.font(22, .heavy)).foregroundStyle(Theme.title).multilineTextAlignment(.center)
                    Text("\(days.formatted()) days · \(String(format: "%02d:%02d:%02d", (secs / 3600) % 24, (secs / 60) % 60, secs % 60))")
                        .font(Theme.font(14, .semibold)).monospacedDigit().foregroundStyle(Theme.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A one-line "Together 412 days" for the home layouts, when the date is set.
struct TogetherChip: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore

    var body: some View {
        if let since = together.space(model.selectedPartnerID).togetherSince {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.pink)
                Text("\(TogetherSpace.days(since: since).formatted()) days together")
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                if let next = together.space(model.selectedPartnerID).dates.filter({ !$0.deleted }).min(by: { $0.daysUntil() < $1.daysUntil() }),
                   next.daysUntil() <= 30 {
                    Text("· \(next.title) \(next.daysUntil() == 0 ? "today" : "in \(next.daysUntil())d")")
                        .font(Theme.font(12, .semibold)).foregroundStyle(Theme.subtitle).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glass(Capsule())
        }
    }
}

/// The Together card for the Classic home: days together and the next special date.
struct TogetherHomeCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore

    var body: some View {
        let space = together.space(model.selectedPartnerID)
        let next = space.dates.filter { !$0.deleted }.min { $0.daysUntil() < $1.daysUntil() }
        HStack(spacing: 12) {
            Image(systemName: "heart.fill").font(.system(size: 22)).foregroundStyle(Theme.pink)
            VStack(alignment: .leading, spacing: 2) {
                if let since = space.togetherSince {
                    Text("\(TogetherSpace.days(since: since).formatted()) days together").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                    Text(TogetherSpace.durationText(since: since)).font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                } else {
                    Text("Together").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                    Text("Set when you got together in the Us tab").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
            }
            Spacer(minLength: 4)
            if let next {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(next.title).font(Theme.font(12, .bold)).foregroundStyle(Theme.title).lineLimit(1)
                    Text(next.daysUntil() == 0 ? "today 🎉" : "in \(next.daysUntil()) days").font(Theme.font(12, .heavy)).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(14)
        .glass(cornerRadius: Theme.cardCorner)
    }
}

struct TogetherStartSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("When did you get together?").font(Theme.font(20, .heavy)).foregroundStyle(Theme.title)
                Text("Scroll the day, month and year.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .padding(.vertical, 6).glass(cornerRadius: 22)
                Text(TogetherSpace.durationText(since: date) + " together")
                    .font(Theme.font(15, .bold)).foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding()
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id = model.selectedPartnerID
                        together.edit(id, note: "updated when you got together 💞") { s in
                            let old = s.togetherSince
                            s.togetherSince = date
                            s.togetherSinceEdited = Date()
                            // The day you got together is your anniversary: move the one that was
                            // on the old day (or the only one), or add it.
                            let cal = Calendar.current
                            let anniversaries = s.dates.indices.filter { s.dates[$0].kind == .anniversary && !s.dates[$0].deleted }
                            let match = anniversaries.first { i in old.map { cal.isDate(s.dates[i].date, inSameDayAs: $0) } ?? false }
                                ?? (anniversaries.count == 1 ? anniversaries.first : nil)
                            if let i = match {
                                s.dates[i].date = date
                                s.dates[i].edited = Date()
                            } else if anniversaries.isEmpty {
                                s.dates.append(SpecialDate(title: "Our anniversary", date: date, kind: .anniversary))
                            }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { if let s = together.space(model.selectedPartnerID).togetherSince { date = s } }
        }
    }
}

// MARK: - Special dates

struct SpecialDateRow: View {
    let date: SpecialDate
    var body: some View {
        let days = date.daysUntil()
        HStack(spacing: 12) {
            Image(systemName: date.kind.icon).font(.system(size: 20))
                .foregroundStyle(date.kind == .birthday ? Theme.amber : Theme.pink).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(date.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                Text([date.date.formatted(date: .abbreviated, time: .omitted), date.ordinalText()].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            Spacer()
            Text(days == 0 ? "Today 🎉" : days == 1 ? "Tomorrow" : "\(days) days")
                .font(Theme.font(13, .heavy)).foregroundStyle(days <= 7 ? Theme.accent : Theme.subtitle)
        }
    }
}

struct SpecialDatesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var editing: SpecialDate?
    @State private var adding = false

    var body: some View {
        let dates = together.space(model.selectedPartnerID).dates.filter { !$0.deleted }.sorted { $0.daysUntil() < $1.daysUntil() }
        List {
            ForEach(dates) { d in
                Button { editing = d } label: { SpecialDateRow(date: d) }
                    .listRowBackground(Theme.ink.opacity(0.06))
                    .swipeActions {
                        Button(role: .destructive) {
                            together.edit(model.selectedPartnerID, note: "removed \(d.title) from your dates") { s in
                                if let i = s.dates.firstIndex(where: { $0.id == d.id }) { s.dates[i].deleted = true; s.dates[i].edited = Date() }
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Special dates")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { SpecialDateEditor(date: $0) }
        .sheet(isPresented: $adding) { SpecialDateEditor(date: nil) }
    }
}

struct SpecialDateEditor: View {
    let date: SpecialDate?
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var day = Date()
    @State private var kind: SpecialDate.Kind = .anniversary
    @State private var yearly = true
    @State private var remind = 7

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(SpecialDate.Kind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(kind == .birthday ? "Whose birthday? e.g. Alex's birthday" : "Title, e.g. First date", text: $title)
                Section {
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                } header: {
                    Text(day.formatted(date: .long, time: .omitted))
                }
                Toggle("Every year", isOn: $yearly)
                Picker("Remind me", selection: $remind) {
                    Text("On the day").tag(0)
                    Text("1 day before too").tag(1)
                    Text("3 days before too").tag(3)
                    Text("1 week before too").tag(7)
                    Text("2 weeks before too").tag(14)
                }
                if let date {
                    Button("Delete this date", role: .destructive) {
                        together.edit(model.selectedPartnerID, note: "removed \(date.title) from your dates") { s in
                            if let i = s.dates.firstIndex(where: { $0.id == date.id }) { s.dates[i].deleted = true; s.dates[i].edited = Date() }
                        }
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(date == nil ? "New date" : "Edit date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        let name = t.isEmpty ? kind.title : t
                        together.edit(model.selectedPartnerID, note: date == nil ? "added \(name) to your dates 📅" : "changed \(name) 📅") { s in
                            if let date, let i = s.dates.firstIndex(where: { $0.id == date.id }) {
                                s.dates[i].title = t.isEmpty ? kind.title : t
                                s.dates[i].date = day; s.dates[i].kind = kind; s.dates[i].yearly = yearly
                                s.dates[i].remindDaysBefore = remind; s.dates[i].edited = Date()
                            } else {
                                s.dates.append(SpecialDate(title: t.isEmpty ? kind.title : t, date: day, kind: kind,
                                                           yearly: yearly, remindDaysBefore: remind))
                            }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let date { title = date.title; day = date.date; kind = date.kind; yearly = date.yearly; remind = date.remindDaysBefore }
            }
        }
    }
}

// MARK: - Likes

struct LikesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var addingFor: String?
    @State private var label = ""
    @State private var value = ""

    private static let ideas = ["Favourite food", "Favourite flowers", "Favourite colour", "Coffee order", "Love language",
                                "Clothes size", "Shoe size", "Ring size", "Favourite film", "Favourite song",
                                "Dream trip", "Allergies", "Pet peeve", "Comfort snack"]

    var body: some View {
        let id = model.selectedPartnerID
        let me = model.myRole(id), them = me == "A" ? "B" : "A"
        let likes = together.space(id).likes.filter { !$0.deleted }
        List {
            section("You", me, likes.filter { $0.owner == me })
            section(model.selectedPartner?.displayName ?? "Them", them, likes.filter { $0.owner == them })
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("What we like")
        .alert("Add", isPresented: Binding(get: { addingFor != nil }, set: { if !$0 { addingFor = nil } })) {
            TextField("What, e.g. Favourite flowers", text: $label)
            TextField("e.g. Peonies", text: $value)
            Button("Add") {
                guard let owner = addingFor, !label.isEmpty || !value.isEmpty else { return }
                together.edit(id, note: "added something to What we like ✨") { $0.likes.append(Preference(owner: owner, label: label, value: value)) }
                label = ""; value = ""
            }
            Button("Cancel", role: .cancel) { label = ""; value = "" }
        }
    }

    private func section(_ title: String, _ owner: String, _ items: [Preference]) -> some View {
        Section {
            ForEach(items) { p in
                HStack(alignment: .firstTextBaseline) {
                    Text(p.label).font(Theme.font(14, .semibold)).foregroundStyle(Theme.subtitle)
                    Spacer()
                    Text(p.value).font(Theme.font(15, .bold)).foregroundStyle(Theme.title).multilineTextAlignment(.trailing)
                }
                .listRowBackground(Theme.ink.opacity(0.06))
                .swipeActions {
                    Button(role: .destructive) {
                        together.edit(model.selectedPartnerID) { s in
                            if let i = s.likes.firstIndex(where: { $0.id == p.id }) { s.likes[i].deleted = true; s.likes[i].edited = Date() }
                        }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.ideas.filter { idea in !items.contains { $0.label == idea } }, id: \.self) { idea in
                        Button(idea) { label = idea; value = ""; addingFor = owner }
                            .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.ink.opacity(0.1)))
                            .buttonStyle(.plain)
                    }
                    Button { label = ""; value = ""; addingFor = owner } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            .listRowBackground(Color.clear)
        } header: {
            Text(title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
        }
    }
}

// MARK: - To-do

struct TodoListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var text = ""

    var body: some View {
        let id = model.selectedPartnerID
        let items = together.space(id).todos.filter { !$0.deleted }
        let me = model.myRole(id)
        List {
            Section {
                HStack {
                    TextField("Add something to do together…", text: $text).onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .listRowBackground(Theme.ink.opacity(0.06))
            }
            Section {
                ForEach(items.sorted { ($0.done ? 1 : 0, $0.created) < ($1.done ? 1 : 0, $1.created) }) { t in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        together.edit(id, note: t.done ? nil : "ticked off a to-do ✅") { s in
                            if let i = s.todos.firstIndex(where: { $0.id == t.id }) { s.todos[i].done.toggle(); s.todos[i].edited = Date() }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.title3)
                                .foregroundStyle(t.done ? Theme.lime : Theme.subtitle)
                            Text(t.text).font(Theme.font(16)).foregroundStyle(t.done ? Theme.subtitle : Theme.title)
                                .strikethrough(t.done)
                            Spacer()
                            Text(t.by == me ? "you" : (model.selectedPartner?.displayName ?? "them"))
                                .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                        }
                    }
                    .listRowBackground(Theme.ink.opacity(0.06))
                    .swipeActions {
                        Button(role: .destructive) {
                            together.edit(id) { s in
                                if let i = s.todos.firstIndex(where: { $0.id == t.id }) { s.todos[i].deleted = true; s.todos[i].edited = Date() }
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("To-do")
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let id = model.selectedPartnerID
        together.edit(id, note: "added a to-do ✅") { $0.todos.append(TodoItem(text: t, by: model.myRole(id))) }
        text = ""
    }
}

// MARK: - Notes

struct SharedNotesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var openID: UUID?

    var body: some View {
        let id = model.selectedPartnerID
        let notes = together.space(id).notes.filter { !$0.deleted }.sorted { $0.edited > $1.edited }
        List {
            ForEach(notes) { n in
                NavigationLink { SharedNoteEditor(noteID: n.id).screenBackground() } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.title.isEmpty ? "Untitled" : n.title).font(Theme.font(16, .bold)).foregroundStyle(Theme.title)
                        Text(n.body.isEmpty ? " " : n.body).font(Theme.font(13)).foregroundStyle(Theme.subtitle).lineLimit(2)
                        Text(n.edited.formatted(.relative(presentation: .named))).font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    }
                }
                .listRowBackground(Theme.ink.opacity(0.06))
                .swipeActions {
                    Button(role: .destructive) {
                        together.edit(id) { s in
                            if let i = s.notes.firstIndex(where: { $0.id == n.id }) { s.notes[i].deleted = true; s.notes[i].edited = Date() }
                        }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Notes")
        .toolbar {
            Button {
                let note = SharedNote(title: "", body: "")
                together.edit(id, note: "started a new note 📝") { $0.notes.append(note) }
                openID = note.id
            } label: { Image(systemName: "square.and.pencil") }
        }
        .navigationDestination(isPresented: Binding(get: { openID != nil }, set: { if !$0 { openID = nil } })) {
            if let openID { SharedNoteEditor(noteID: openID).screenBackground() }
        }
    }
}

struct SharedNoteEditor: View {
    let noteID: UUID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var title = ""
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title).font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
            TextEditor(text: $text).font(Theme.font(16)).foregroundStyle(Theme.title)
                .scrollContentBackground(.hidden)
                .padding(8).glass(cornerRadius: 16)
        }
        .padding(16).padding(.bottom, 80)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let n = together.space(model.selectedPartnerID).notes.first(where: { $0.id == noteID }) else { return }
            title = n.title; text = n.body; loaded = true
        }
        .onChange(of: title) { _ in save() }
        .onChange(of: text) { _ in save() }
        // One notification for a round of edits, when you leave the note.
        .onDisappear {
            if lastTyped != .distantPast { Task { await model.notifyPartner(model.selectedPartnerID, "updated a note 📝") } }
        }
        // The partner edited it while it's open: show theirs if it's newer than what we typed.
        .onChange(of: together.space(model.selectedPartnerID).notes.first(where: { $0.id == noteID })) { n in
            guard loaded, let n, n.title != title || n.body != text, Date().timeIntervalSince(lastTyped) > 3 else { return }
            title = n.title; text = n.body
        }
    }

    @State private var lastTyped = Date.distantPast

    private func save() {
        guard loaded else { return }
        lastTyped = Date()
        together.edit(model.selectedPartnerID) { s in
            if let i = s.notes.firstIndex(where: { $0.id == noteID }), s.notes[i].title != title || s.notes[i].body != text {
                s.notes[i].title = title; s.notes[i].body = text; s.notes[i].edited = Date()
            }
        }
    }
}
