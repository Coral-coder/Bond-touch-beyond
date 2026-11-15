import Charts
import SwiftUI

/// Where we stand: how each of you feels about the relationship (closeness, style, how
/// happy you are with it, what's working, more of, less of, pace), shown to the other as how
/// you line up rather than as numbers; wishes, with an optional mutual reveal; promises; a
/// regular check-in; and, when three or more of you are all bonded, an "All of us" space.
/// Either of you can pause it or call a quiet season. No style ranks above another.
struct WhereWeStandView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var updating = false
    @State private var wishSheet: ScopeSheet?
    @State private var promiseSheet: StandPromiseDraft?
    /// "Keep it" on a rough day: the check-in stays where it is.
    @State private var keptCheckIn = false
    @State private var exportFiles: UnbondConfirm.ExportFiles?

    struct ScopeSheet: Identifiable {
        let id = UUID()
        let scope: StandScope
    }

    private var id: String? { model.selectedPartnerID }
    private var scope: StandScope { model.standScope(id) }
    private var me: String { scope.me }
    private var them: String { model.standThem(id) }
    private var name: String { model.selectedPartner?.displayName ?? "your partner" }
    private var mePaused: Bool { model.standPaused(id, me) }
    private var themPaused: Bool { model.standPaused(id, them) }
    private var groups: [StandGroup] {
        guard let id else { return [] }
        return model.standGroups().filter { $0.bondIDs.contains(id) }
    }

    var body: some View {
        // Read the store here so the screen follows every change.
        let _ = together.space(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if mePaused || themPaused {
                    pausedCard
                } else {
                    if model.standQuiet(id) { quietCard }
                    checkInBanner
                    meterCard
                    theirCard
                    historyCard
                    StandWishesCard(scope: scope, onAdd: { wishSheet = ScopeSheet(scope: scope) },
                                    onPromise: { promiseSheet = $0 })
                    StandPromisesCard(scope: scope, onEdit: { promiseSheet = $0 })
                    StandKeptCard(scope: scope)
                    ForEach(groups) { g in groupCard(g) }
                }
                settingsCard
            }
            .padding(16)
        }
        .navigationTitle("Where we stand")
        .sheet(isPresented: $updating) { StandUpdateSheet(bondID: id) }
        .sheet(item: $wishSheet) { StandWishEditor(scope: $0.scope) }
        .sheet(item: $promiseSheet) { StandPromiseEditor(draft: $0) }
        .sheet(item: $exportFiles) { ActivityView(items: $0.urls).presentationDetents([.medium, .large]) }
        .onAppear {
            model.matchStandWishes(id)
            if !mePaused && !themPaused {
                model.markStandSeen(scope)
                groups.forEach { model.markStandSeen(model.standScope($0)) }
            }
            if StandLink.openUpdate {
                StandLink.openUpdate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { updating = true }
            }
        }
    }

    // MARK: Pause and quiet season

    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(mePaused ? "You've paused Where we stand" : "\(name) has paused Where we stand",
                  systemImage: "pause.circle.fill")
                .font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
            Text(mePaused
                 ? "\(name) sees that it's paused, and nothing else. Nothing new is shown or sent while it rests. Come back whenever you like."
                 : "No reason needed. Nothing new is shown or sent while it's paused, and everything is here when they're ready. 🤍")
                .font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            if mePaused {
                Button("Resume") {
                    model.setStandMark(scope, StandMark(.pause, by: me, value: "off"))
                }
                .buttonStyle(AccentButtonStyle(height: 44))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }

    private var quietCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("🌙").font(.system(size: Theme.s(28)))
            VStack(alignment: .leading, spacing: 4) {
                Text("You're in a quiet season").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Text("Check-ins and reminders are resting for both of you. Everything else is here whenever you want it.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                Button("End the quiet season") {
                    model.setStandMark(scope, StandMark(.quiet, by: me, value: "off", shared: true))
                }
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }

    // MARK: Check-in

    @ViewBuilder private var checkInBanner: some View {
        if let next = model.standNextCheckIn(id), next <= Date() {
            VStack(alignment: .leading, spacing: 10) {
                if model.standMoodLow && !keptCheckIn {
                    Text("You're having a rough day. Want to move the check-in?")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    HStack(spacing: 10) {
                        Button("Move it (+3 days)") { model.standMoveCheckIn(id) }
                            .buttonStyle(AccentButtonStyle(height: 40))
                        Button("Keep it") { keptCheckIn = true }
                            .buttonStyle(GlassButtonStyle(height: 40))
                    }
                } else {
                    Text("Where do you stand with \(name)? 2 minutes.")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    Button("Check in") { updating = true }
                        .buttonStyle(AccentButtonStyle(height: 40))
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
        }
    }

    // MARK: The meter

    private var meterCard: some View {
        let mine = model.standLatest(id, by: me), theirs = model.standLatest(id, by: them)
        let shape = StandAlignment.of(mine, theirs)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(shape.emoji).font(.system(size: Theme.s(38)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(shape.title).font(Theme.font(19, .heavy)).foregroundStyle(Theme.title)
                    Text(StandAlignment.detail(mine, theirs, name: name)).font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                }
            }
            if let mine {
                Divider().overlay(Theme.ink.opacity(0.1))
                HStack(alignment: .firstTextBaseline) {
                    Text("You").font(Theme.font(14, .heavy)).foregroundStyle(Theme.title)
                    Spacer()
                    Text("\(StandPrivate.closeness(mine))/10 · \(mine.happy.title) · \(mine.paceValue.title)")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                }
                let note = StandPrivate.note(mine)
                if !note.isEmpty { Text("\u{201C}\(note)\u{201D}").font(Theme.font(13)).foregroundStyle(Theme.title) }
                StandStyleChips(styles: mine.styles, highlight: theirs.map { StandStyles.overlap(mine.styles, $0.styles) } ?? [])
                Text(mine.shared ? "\(name) can see your number." : "Your number stays on your phone. \(name) sees how you line up.")
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
            Button(mine == nil ? "Say where you stand" : "Update") { updating = true }
                .buttonStyle(AccentButtonStyle(height: 44))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }

    @ViewBuilder private var theirCard: some View {
        if let theirs = model.standLatest(id, by: them) {
            let mine = model.standLatest(id, by: me)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                    Spacer()
                    Text(theirs.closeness.map { "\($0)/10" } ?? "Keeps their number to themselves")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                }
                if let note = theirs.note, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}").font(Theme.font(13)).foregroundStyle(Theme.title)
                }
                StandStyleChips(styles: theirs.styles, highlight: mine.map { StandStyles.overlap(theirs.styles, $0.styles) } ?? [])
                if let mine, !mine.styles.isEmpty, !theirs.styles.isEmpty {
                    let same = StandStyles.overlap(mine.styles, theirs.styles)
                    Text(same.isEmpty ? "You describe it differently. Neither is wrong." : "You agree on \(same.joined(separator: ", ")).")
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                Text("Pace: \(theirs.paceValue.title)").font(Theme.font(12)).foregroundStyle(Theme.title)
                list("What's working", theirs.working, "sparkles")
                list("More of", theirs.moreOf, "plus.circle")
                list("Less of", theirs.lessOf, "minus.circle")
                Text("Said \(theirs.created.formatted(.relative(presentation: .named)))").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
        }
    }

    @ViewBuilder private func list(_ title: String, _ items: [String], _ icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                ForEach(items, id: \.self) { Label($0, systemImage: icon).font(Theme.font(13)).foregroundStyle(Theme.title) }
            }
        }
    }

    // MARK: History

    private struct Point: Identifiable {
        let id: String
        let at: Date
        let value: Double
        let series: String
    }

    @ViewBuilder private var historyCard: some View {
        let mine = model.standReadings(id, by: me)
        let theirs = model.standReadings(id, by: them)
        if mine.count + theirs.count >= 2 {
            let minePoints = mine.map { Point(id: "m\($0.id)", at: $0.created, value: Double(StandPrivate.closeness($0)), series: "You") }
            let theirPoints = theirs.compactMap { r in r.closeness.map { Point(id: "t\(r.id)", at: r.created, value: Double($0), series: name) } }
            // How aligned you were at each reading, against the other's latest one then.
            let aligned = (mine + theirs).sorted { $0.created < $1.created }.compactMap { r -> Point? in
                let other = r.by == me ? theirs : mine
                guard let o = other.last(where: { $0.created <= r.created }) else { return nil }
                let (a, b) = r.by == me ? (r, o) : (o, r)
                return Point(id: "a\(r.id)", at: r.created, value: StandAlignment.of(a, b).score * 10, series: "Alignment")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Over time").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Chart {
                    ForEach(minePoints) { p in
                        LineMark(x: .value("Day", p.at), y: .value("Closeness", p.value), series: .value("Who", p.series))
                            .interpolationMethod(.monotone).foregroundStyle(Theme.accent)
                        PointMark(x: .value("Day", p.at), y: .value("Closeness", p.value)).foregroundStyle(Theme.accent)
                    }
                    ForEach(theirPoints) { p in
                        LineMark(x: .value("Day", p.at), y: .value("Closeness", p.value), series: .value("Who", p.series))
                            .interpolationMethod(.monotone).foregroundStyle(Theme.pink)
                        PointMark(x: .value("Day", p.at), y: .value("Closeness", p.value)).foregroundStyle(Theme.pink)
                    }
                    ForEach(aligned) { p in
                        BarMark(x: .value("Day", p.at, unit: .day), y: .value("Closeness", p.value))
                            .foregroundStyle(Theme.lime.opacity(0.35))
                    }
                }
                .chartYScale(domain: 0...10)
                .chartYAxis { AxisMarks(values: [0, 5, 10]) { _ in
                    AxisGridLine().foregroundStyle(Theme.ink.opacity(0.1))
                    AxisValueLabel()
                } }
                .frame(height: 160)
                HStack(spacing: 12) {
                    legend(Theme.accent, "You")
                    if !theirPoints.isEmpty { legend(Theme.pink, name) }
                    legend(Theme.lime.opacity(0.6), "How aligned")
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
        }
    }

    // MARK: Groups

    private func groupCard(_ g: StandGroup) -> some View {
        let groupScope = model.standScope(g)
        let names = g.members.map { model.standName($0, groupScope) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("All of us", systemImage: "person.3.fill").font(Theme.font(18, .heavy)).foregroundStyle(Theme.title)
                Text("You, " + names.joined(separator: ", ") + ". Wishes and promises among all of you, alongside each pair's own.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            StandWishesCard(scope: groupScope, onAdd: { wishSheet = ScopeSheet(scope: groupScope) },
                            onPromise: { promiseSheet = $0 })
            StandPromisesCard(scope: groupScope, onEdit: { promiseSheet = $0 })
            StandKeptCard(scope: groupScope)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).stroke(Theme.ink.opacity(0.15), lineWidth: 1))
    }

    // MARK: Settings

    private var settingsCard: some View {
        let every = model.standRhythm(id)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Check-ins").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Picker("How often", selection: Binding(get: { every }, set: { days in
                model.setStandMark(scope, StandMark(.rhythm, by: me, value: "\(days)", shared: true))
            })) {
                ForEach(StandRhythm.choices, id: \.self) { Text(StandRhythm.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Shared between you. A quiet reminder comes this long after your last update.")
                .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            Toggle(isOn: Binding(get: { model.standSharing(id) }, set: { model.setStandShare(id, $0) })) {
                Text("Share my number").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
            }
            .tint(Theme.accent)
            Toggle(isOn: Binding(get: { model.standQuiet(id) }, set: { on in
                model.setStandMark(scope, StandMark(.quiet, by: me, value: on ? "on" : "off", shared: true))
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("We're in a quiet season").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                    Text("Pauses check-ins and reminders for both of you").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
            }
            .tint(Theme.accent)
            if !mePaused {
                Button("Pause Where we stand") {
                    model.setStandMark(scope, StandMark(.pause, by: me, value: "on"))
                }
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
                Text("\(name) will see that it's paused. No reason needed.").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
            if let id {
                Button("Export a copy") { exportFiles = .init(urls: model.standExport(id)) }
                    .font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }
}

// MARK: - Style chips

/// Styles as chips; the ones you both picked are filled.
struct StandStyleChips: View {
    let styles: [String]
    var highlight: [String] = []

    var body: some View {
        if !styles.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(styles, id: \.self) { s in
                    let both = highlight.contains { $0.lowercased() == s.lowercased() }
                    Text(s).font(Theme.font(12, .bold)).foregroundStyle(both ? Theme.onAccent : Theme.title)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(both ? Theme.accent : Theme.ink.opacity(0.1)))
                }
            }
        }
    }
}

// MARK: - Wishes

/// The wishes in a scope: add one, answer theirs, and see where yours are.
struct StandWishesCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    let scope: StandScope
    var onAdd: () -> Void
    var onPromise: (StandPromiseDraft) -> Void

    var body: some View {
        let _ = together.space(scope.bondID)
        // Someone else's hidden wish never shows; matched pairs show once.
        var seenBoth = Set<String>()
        let wishes = model.standWishes(scope).filter { w in
            if w.isHidden { return w.by == scope.me }
            if w.both, let lib = w.library { return seenBoth.insert(lib).inserted }
            return true
        }.sorted { a, b in a.both != b.both ? a.both : a.created > b.created }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wishes").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent) }
                    .accessibilityLabel("Add a wish")
            }
            if wishes.isEmpty {
                Text("Something you'd love that isn't there yet, or a change you'd like. Big or small.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            ForEach(wishes) { w in StandWishRow(scope: scope, wish: w, onPromise: onPromise) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }
}

/// One wish: who it's from, how much it matters, the answers and what can happen next.
struct StandWishRow: View {
    @EnvironmentObject var model: AppModel
    let scope: StandScope
    let wish: StandWish
    var onPromise: (StandPromiseDraft) -> Void
    @State private var askingWhen = false

    private var mine: Bool { wish.by == scope.me }
    private var answers: [StandMark] { model.standMarks(scope).live(.answer).filter { $0.item == wish.id } }
    private var myAnswer: StandMark? { answers.first { $0.by == scope.me } }

    /// The words: a hidden wish of mine is read back from its hash on this phone only.
    private var title: String {
        if wish.isHidden, let h = wish.hidden, let b = scope.bondID { return StandLibrary.reveal(h, bondCode: b)?.title ?? "A private wish" }
        return wish.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(wish.emoji).font(.system(size: Theme.s(22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    Text(meta).font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                if mine || wish.both {
                    Menu {
                        Button("Remove", role: .destructive) {
                            model.standEdit(scope, \.standWishes, \.standGroupWishes) { syncDelete(&$0, wish.id) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.accent) }
                }
            }
            if wish.both {
                Text("You both want this 💞").font(Theme.font(13, .heavy)).foregroundStyle(Theme.pink)
            } else if wish.isHidden {
                Label("Only shown if they want it too. Until then, they see nothing.", systemImage: "lock.fill")
                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
            }
            ForEach(answers.filter { $0.by != scope.me || !mine }) { a in answerLine(a) }
            if mine, !seenBy.isEmpty, !wish.isHidden {
                Label(scope.isGroup ? "Seen by " + seenBy.joined(separator: ", ") : "Seen", systemImage: "eye")
                    .font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
            }
            if !mine && !wish.both && canAnswer { answerButtons }
            if wish.promise == nil, wish.both || answers.contains(where: { $0.value == StandAnswer.yes.rawValue }) {
                Button("Make it a promise 🤝") {
                    onPromise(StandPromiseDraft(scope: scope, title: title, wish: wish.id))
                }
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(12).glass(cornerRadius: 16)
        .confirmationDialog("When could it come back?", isPresented: $askingWhen, titleVisibility: .visible) {
            ForEach([1, 3, 6], id: \.self) { m in
                Button("In \(m) month\(m == 1 ? "" : "s")") { answer(.notYet, months: m) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be asked again before then. When the time comes, they get a quiet reminder.")
        }
    }

    private var meta: String {
        var parts: [String] = []
        if !wish.both { parts.append(mine ? "Your wish" : "From \(model.standName(wish.by, scope))") }
        parts.append(wish.matters ? "This matters to me" : "Would be lovely")
        parts.append(wish.change ? "A change I'd like" : "Closer")
        return parts.joined(separator: " · ")
    }

    private var seenBy: [String] {
        let marks = model.standMarks(scope).live(.seen).filter { $0.item == wish.id && $0.by != scope.me }
        return Array(Set(marks.map { model.standName($0.by, scope) })).sorted()
    }

    /// Not answered yet, or a "Not yet" whose time has come.
    private var canAnswer: Bool {
        guard let a = myAnswer else { return true }
        return a.value == StandAnswer.notYet.rawValue && (a.until ?? .distantPast) <= Date()
    }

    private func answerLine(_ a: StandMark) -> some View {
        let who = model.standName(a.by, scope)
        let answer = StandAnswer(rawValue: a.value) ?? .talk
        return VStack(alignment: .leading, spacing: 4) {
            if answer == .notYet, let until = a.until {
                if until > Date() {
                    Text("\(who): Not yet 🌙 · can come back \(until.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                } else {
                    Text("\(who) said not yet, and it can come back now").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                    if mine {
                        Button("Bring it back") {
                            model.clearStandMark(scope, a.id, note: "brought back a wish in Where we stand 🌱")
                        }
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                    }
                }
            } else {
                Text("\(who): \(answer.title) \(answer.emoji)").font(Theme.font(12, .bold))
                    .foregroundStyle(answer == .yes ? Theme.lime : Theme.title)
            }
        }
    }

    private var answerButtons: some View {
        HStack(spacing: 8) {
            ForEach(StandAnswer.allCases) { a in
                Button(a.title) {
                    if a == .notYet { askingWhen = true } else { answer(a) }
                }
                .font(Theme.font(12, .bold)).foregroundStyle(a == .yes ? Theme.onAccent : Theme.title)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(a == .yes ? Theme.accent : Theme.ink.opacity(0.1)))
                .buttonStyle(.plain)
            }
        }
    }

    private func answer(_ a: StandAnswer, months: Int? = nil) {
        let until = months.flatMap { Calendar.current.date(byAdding: .month, value: $0, to: Date()) }
        UISelectionFeedbackGenerator().selectionChanged()
        model.setStandMark(scope, StandMark(.answer, item: wish.id, by: scope.me, value: a.rawValue, until: until,
                                            groupKey: scope.groupKey),
                           note: "answered your wish in Where we stand")
    }
}

/// Add a wish: from the starter library or in your own words.
struct StandWishEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let scope: StandScope
    @State private var picked: StandLibraryItem?
    @State private var custom = ""
    @State private var matters = false
    @State private var change = false
    @State private var hidden = false

    private var name: String { scope.isGroup ? "everyone" : model.standName(scope.me == "A" ? "B" : "A", scope) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Something you'd like that isn't there yet").font(Theme.font(18, .heavy)).foregroundStyle(Theme.title)
                    FlowLayout(spacing: 6) {
                        ForEach(StandLibrary.all) { item in
                            Button {
                                picked = picked == item ? nil : item
                                if picked != nil { custom = ""; change = item.change }
                            } label: {
                                Text("\(item.emoji) \(item.title)").font(Theme.font(13, .bold))
                                    .foregroundStyle(picked == item ? Theme.onAccent : Theme.title)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Capsule().fill(picked == item ? Theme.accent : Theme.ink.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Or in your own words", text: $custom)
                        .font(Theme.font(14)).padding(10).glass(cornerRadius: 12)
                        .onChange(of: custom) { t in if !t.isEmpty { picked = nil; hidden = false } }
                    Picker("Importance", selection: $matters) {
                        Text("Would be lovely").tag(false); Text("This matters to me").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("Direction", selection: $change) {
                        Text("Closer").tag(false); Text("A change I'd like").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if !scope.isGroup {
                        Toggle(isOn: $hidden) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Only show this if they want it too").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                                Text("\(name) sees nothing unless they pick the same one. Works with the starter wishes only: your own words can't be matched.")
                                    .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                            }
                        }
                        .tint(Theme.accent)
                        .disabled(picked == nil)
                    }
                    Button("Add the wish") { save() }
                        .buttonStyle(AccentButtonStyle(height: 48))
                        .disabled(picked == nil && custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("A wish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        var w = StandWish(by: scope.me, matters: matters, change: change, groupKey: scope.groupKey)
        if let picked, hidden, !scope.isGroup, let code = scope.bondID {
            // No words at all: just the keyed hash.
            w.hidden = StandLibrary.hiddenHash(picked, bondCode: code)
        } else if let picked {
            w.title = picked.title
            w.library = picked.id
        } else {
            w.title = custom.trimmingCharacters(in: .whitespaces)
        }
        let isHidden = w.hidden != nil
        model.standEdit(scope, note: isHidden ? nil : "added a wish to Where we stand 🌱", \.standWishes, \.standGroupWishes) {
            syncAppend(&$0, w)
        }
        if isHidden { model.matchStandWishes(scope.bondID) }
        dismiss()
    }
}

// MARK: - Promises

/// What the promise editor is for: a new promise (maybe from a wish), changing one, or renewing one.
struct StandPromiseDraft: Identifiable {
    let id = UUID()
    let scope: StandScope
    var title = ""
    var wish: UUID?
    var changing: StandPromise?
    var renewing: StandPromise?
}

struct StandPromiseEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let draft: StandPromiseDraft
    @State private var title = ""
    @State private var hasDate = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Asheville weekend", text: $title)
                    Toggle("For a day", isOn: $hasDate).tint(Theme.accent)
                    if hasDate { DatePicker("Day", selection: $due, displayedComponents: .date) }
                    TextField("A note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("You'll both get a gentle reminder three days before. A promise can always be renewed, changed or let go.")
                }
                .listRowBackground(Theme.ink.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(draft.renewing != nil ? "Renew" : draft.changing != nil ? "Change it" : "A promise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                let base = draft.renewing ?? draft.changing
                title = base?.title ?? draft.title
                note = base?.note ?? ""
                if let d = base?.due {
                    hasDate = true
                    due = draft.renewing != nil ? max(d, Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? d) : d
                }
            }
        }
    }

    private func save() {
        let scope = draft.scope
        let t = title.trimmingCharacters(in: .whitespaces)
        let day = hasDate ? Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: due) : nil
        if let old = draft.renewing {
            model.standEdit(scope, note: "renewed a promise in Where we stand 🤝", \.standPromises, \.standGroupPromises) {
                syncUpdate(&$0, old.id) { p in p.title = t; p.due = day; p.note = note }
            }
        } else {
            var p = StandPromise(by: scope.me, title: t, due: day, note: note, wish: draft.wish ?? draft.changing?.wish,
                                 groupKey: scope.groupKey)
            p.replaces = draft.changing?.id
            let old = draft.changing
            model.standEdit(scope, note: old == nil ? "made a promise in Where we stand 🤝" : "changed a promise in Where we stand 🤝",
                            \.standPromises, \.standGroupPromises) { list in
                if let old { syncUpdate(&list, old.id) { x in x.state = StandPromiseState.changed.rawValue; x.stateAt = Date() } }
                syncAppend(&list, p)
            }
            if let w = draft.wish {
                model.standEdit(scope, \.standWishes, \.standGroupWishes) { list in syncUpdate(&list, w) { x in x.promise = p.id } }
            }
        }
        dismiss()
    }
}

/// Open promises, with the gentle prompt once a day has gone by.
struct StandPromisesCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    let scope: StandScope
    var onEdit: (StandPromiseDraft) -> Void

    var body: some View {
        let _ = together.space(scope.bondID)
        let open = model.standPromises(scope).filter { $0.status == .open }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Promises").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Button { onEdit(StandPromiseDraft(scope: scope)) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Make a promise")
            }
            if open.isEmpty {
                Text("Something you'll do for each other. From a wish you agreed on, or on its own.")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            }
            ForEach(open) { p in StandPromiseRow(scope: scope, promise: p, onEdit: onEdit) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
    }
}

struct StandPromiseRow: View {
    @EnvironmentObject var model: AppModel
    let scope: StandScope
    let promise: StandPromise
    var onEdit: (StandPromiseDraft) -> Void

    private var mine: Bool { promise.by == scope.me }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("🤝").font(.system(size: Theme.s(20)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(promise.title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    Text(meta).font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                Menu {
                    Button("Kept 🌟") { set(.kept, note: "kept a promise in Where we stand 🌟") }
                    Button("Change it") { onEdit(StandPromiseDraft(scope: scope, changing: promise)) }
                    Button("Renew") { onEdit(StandPromiseDraft(scope: scope, renewing: promise)) }
                    Button("Let it go") { set(.letGo, note: nil) }
                    if promise.due != nil && promise.event == nil {
                        Button("Add to our calendar") { model.shareStandPromiseToCalendar(scope, promise) }
                    }
                    Button("Remove", role: .destructive) {
                        model.standEdit(scope, \.standPromises, \.standGroupPromises) { syncDelete(&$0, promise.id) }
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.accent) }
            }
            if !promise.note.isEmpty { Text(promise.note).font(Theme.font(13)).foregroundStyle(Theme.title) }
            if promise.event != nil {
                Label("On your calendar", systemImage: "calendar").font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
            }
            if mine, seen {
                Label("Seen", systemImage: "eye").font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
            }
            if promise.slipped {
                Text("This one slipped by. Renew, change it, or let it go?").font(Theme.font(13, .bold)).foregroundStyle(Theme.title)
                HStack(spacing: 8) {
                    chip("Renew") { onEdit(StandPromiseDraft(scope: scope, renewing: promise)) }
                    chip("Change it") { onEdit(StandPromiseDraft(scope: scope, changing: promise)) }
                    chip("Let it go") { set(.letGo, note: nil) }
                }
            }
        }
        .padding(12).glass(cornerRadius: 16)
    }

    private var meta: String {
        var parts = [mine ? "Your promise" : "From \(model.standName(promise.by, scope))"]
        if let due = promise.due { parts.append("for \(due.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    private var seen: Bool {
        model.standMarks(scope).live(.seen).contains { $0.item == promise.id && $0.by != scope.me }
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Theme.ink.opacity(0.1)))
            .buttonStyle(.plain)
    }

    private func set(_ state: StandPromiseState, note: String?) {
        if state == .kept { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        model.standEdit(scope, note: note, \.standPromises, \.standGroupPromises) {
            syncUpdate(&$0, promise.id) { p in p.state = state.rawValue; p.stateAt = Date() }
        }
    }
}

/// "What we've done for each other": kept promises, with thank-you notes.
struct StandKeptCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    let scope: StandScope
    @State private var thanking: StandPromise?
    @State private var thanks = ""

    var body: some View {
        let _ = together.space(scope.bondID)
        let kept = model.standPromises(scope).filter { $0.status == .kept }.sorted { ($0.stateAt ?? $0.edited) > ($1.stateAt ?? $1.edited) }
        let notes = model.standMarks(scope).live(.thanks)
        if !kept.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What we've done for each other").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                ForEach(kept) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🌟 \(p.title)").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                        Text("\(model.standName(p.by, scope)) · \((p.stateAt ?? p.edited).formatted(date: .abbreviated, time: .omitted))")
                            .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                        ForEach(notes.filter { $0.item == p.id }) { n in
                            Text("💛 \(model.standName(n.by, scope)): \(n.value)").font(Theme.font(13)).foregroundStyle(Theme.title)
                        }
                        if p.by != scope.me && !notes.contains(where: { $0.item == p.id && $0.by == scope.me }) {
                            Button("Say thank you") { thanks = ""; thanking = p }
                                .font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(cornerRadius: Theme.cardCorner)
            .alert("A thank-you", isPresented: Binding(get: { thanking != nil }, set: { if !$0 { thanking = nil } })) {
                TextField("That weekend meant a lot", text: $thanks)
                Button("Send") {
                    guard let p = thanking, !thanks.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    model.setStandMark(scope, StandMark(.thanks, item: p.id, by: scope.me, value: thanks, groupKey: scope.groupKey),
                                       note: "said thank you for a kept promise in Where we stand 💛")
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - The update

/// The check-in: the meter first, then any wishes due to come back.
struct StandUpdateSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    let bondID: String?
    @State private var closeness = 6.0
    @State private var note = ""
    @State private var styles: [String] = []
    @State private var customStyle = ""
    @State private var happiness = StandHappiness.content
    @State private var working: [String] = []
    @State private var moreOf: [String] = []
    @State private var lessOf: [String] = []
    @State private var pace = StandPace.steady
    @State private var share = false
    @State private var keptCheckIn = false

    private var scope: StandScope { model.standScope(bondID) }
    private var name: String { model.partners.first { $0.id == bondID }?.displayName ?? "your partner" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.standMoodLow && !keptCheckIn {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You're having a rough day. Want to move the check-in?")
                                .font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                            HStack(spacing: 10) {
                                Button("Move it (+3 days)") { model.standMoveCheckIn(bondID); dismiss() }
                                    .buttonStyle(AccentButtonStyle(height: 40))
                                Button("Keep it") { keptCheckIn = true }
                                    .buttonStyle(GlassButtonStyle(height: 40))
                            }
                        }
                        .padding(14).glass(cornerRadius: 16)
                    }
                    section("How close do you feel?") {
                        HStack {
                            Slider(value: $closeness, in: 1...10, step: 1).tint(Theme.accent)
                            Text("\(Int(closeness))").font(Theme.font(22, .heavy)).monospacedDigit().foregroundStyle(Theme.title)
                                .frame(width: 36)
                        }
                        TextField("A line about it (optional)", text: $note).font(Theme.font(14)).padding(10).glass(cornerRadius: 12)
                        Toggle("Share my number with \(name)", isOn: $share).font(Theme.font(13, .bold)).tint(Theme.accent)
                    }
                    section("What kind of relationship is it?", hint: "Pick any. None ranks above another.") {
                        Text("Shape").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                        chips(StandStyles.shape)
                        Text("Kind").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
                        chips(StandStyles.kind)
                        let custom = styles.filter { !StandStyles.all.contains($0) }
                        if !custom.isEmpty { chips(custom) }
                        HStack {
                            TextField("Your own word", text: $customStyle).font(Theme.font(14)).onSubmit(addStyle)
                            Button(action: addStyle) { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent) }
                                .disabled(customStyle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(10).glass(cornerRadius: 12)
                    }
                    section("How do you feel about it?", hint: "Content is content, whatever the shape.") {
                        Picker("Happiness", selection: $happiness) {
                            ForEach(StandHappiness.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("What's working") { StandListEditor(items: $working, hint: "Sunday mornings") }
                    section("More of") { StandListEditor(items: $moreOf, hint: "Little texts in the day") }
                    section("Less of") { StandListEditor(items: $lessOf, hint: "Last-minute changes") }
                    section("Pace") {
                        Picker("Pace", selection: $pace) {
                            ForEach(StandPace.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Button("Save") { save() }.buttonStyle(AccentButtonStyle(height: 50))
                    comingBack
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Where you stand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: load)
        }
    }

    private func section<C: View>(_ title: String, hint: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            if let hint { Text(hint).font(Theme.font(11)).foregroundStyle(Theme.subtitle) }
            content()
        }
    }

    private func chips(_ list: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(list, id: \.self) { s in
                let on = styles.contains(s)
                Button {
                    if on { styles.removeAll { $0 == s } } else { styles.append(s) }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(s).font(Theme.font(12, .bold)).foregroundStyle(on ? Theme.onAccent : Theme.title)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Capsule().fill(on ? Theme.accent : Theme.ink.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func addStyle() {
        let s = customStyle.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !styles.contains(where: { $0.lowercased() == s.lowercased() }) else { customStyle = ""; return }
        styles.append(s)
        customStyle = ""
    }

    /// Wishes due to come back: yours whose "Not yet" has run out, and theirs you said "Not yet" to.
    @ViewBuilder private var comingBack: some View {
        let marks = model.standMarks(scope).live(.answer).filter {
            $0.value == StandAnswer.notYet.rawValue && ($0.until ?? .distantFuture) <= Date()
        }
        let due = model.standWishes(scope).filter { w in marks.contains { $0.item == w.id } }
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wishes that can come back").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                ForEach(due) { w in StandWishRow(scope: scope, wish: w, onPromise: { _ in }) }
            }
        }
    }

    private func load() {
        share = model.standSharing(bondID)
        guard let last = model.standLatest(bondID, by: scope.me) else { return }
        closeness = Double(StandPrivate.closeness(last))
        note = StandPrivate.note(last)
        styles = last.styles
        happiness = last.happy
        working = last.working
        moreOf = last.moreOf
        lessOf = last.lessOf
        pace = last.paceValue
    }

    private func save() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.saveStandReading(bondID, closeness: Int(closeness), note: note.trimmingCharacters(in: .whitespaces), styles: styles,
                               happiness: happiness, working: working, moreOf: moreOf, lessOf: lessOf, pace: pace, share: share)
        dismiss()
    }
}

/// A short list you add lines to and take them off.
struct StandListEditor: View {
    @Binding var items: [String]
    let hint: String
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text("• \(item)").font(Theme.font(14)).foregroundStyle(Theme.title)
                    Spacer()
                    Button { items.removeAll { $0 == item } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
            if items.count < 6 {
                HStack {
                    TextField(hint, text: $text).font(Theme.font(14)).onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent) }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10).glass(cornerRadius: 12)
            }
        }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(t) else { return }
        items.append(t)
        text = ""
    }
}
