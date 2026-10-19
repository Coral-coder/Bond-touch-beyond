import SwiftUI

/// The poly calendar: plans with every partner on one timeline. Each event lives in your
/// space with the partner it's shared with, so they see the plans you have with them (and
/// add their own); only you see everyone's together.
struct PolyCalendarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var adding = false

    private struct Row: Identifiable {
        let event: CalendarEvent
        let partner: Partner
        var id: UUID { event.id }
    }

    private var rows: [Row] {
        let start = Calendar.current.startOfDay(for: Date())
        return model.partners.filter { !$0.bond.legacy }.flatMap { p in
            syncLive(together.space(p.id).events).filter { $0.end >= start }.map { Row(event: $0, partner: p) }
        }
        .sorted { $0.event.start < $1.event.start }
    }

    var body: some View {
        let byDay = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.event.start) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                legend
                if rows.isEmpty {
                    Text("Nothing planned yet. Add date nights, weekends away and time with metamours — each partner sees the plans you share with them.")
                        .font(Theme.font(13)).foregroundStyle(Theme.subtitle).padding(16).glass(cornerRadius: Theme.cardCorner)
                }
                ForEach(byDay.keys.sorted(), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(Theme.font(14, .heavy)).foregroundStyle(Theme.title)
                        ForEach(byDay[day] ?? []) { r in eventRow(r) }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Poly calendar")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { CalendarEventEditor() }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.partners.filter { !$0.bond.legacy }) { p in
                    HStack(spacing: 5) {
                        Circle().fill(Color(rgbInt: p.colorRGB)).frame(width: 10, height: 10)
                        Text(p.displayName).font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6).glass(Capsule())
                }
            }
        }
    }

    private func eventRow(_ r: Row) -> some View {
        let e = r.event
        let me = model.myRole(r.partner.id)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(Color(rgbInt: r.partner.colorRGB)).frame(width: 5)
            Text(e.emoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                Text("\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: Calendar.current.isDate(e.start, inSameDayAs: e.end) ? .omitted : .abbreviated, time: .shortened)) · with \(e.with == "Us" ? r.partner.displayName : e.with)")
                    .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                Text(e.by == me ? "Added by you" : "Added by \(r.partner.displayName)").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
            }
            Spacer()
            Button {
                together.edit(r.partner.id, note: "removed a plan from your calendar 📅") { syncDelete(&$0.events, e.id) }
            } label: { Image(systemName: "trash").foregroundStyle(Theme.subtitle) }
            .buttonStyle(.plain)
        }
        .padding(12).glass(cornerRadius: 16)
    }
}

struct CalendarEventEditor: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @Environment(\.dismiss) private var dismiss
    @State private var partnerID: String?
    @State private var title = ""
    @State private var with = "Us"
    @State private var emoji = "💞"
    @State private var start = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Shared with", selection: $partnerID) {
                    ForEach(model.partners.filter { !$0.bond.legacy }) { p in Text(p.displayName).tag(Optional(p.id)) }
                }
                TextField("What, e.g. Date night", text: $title)
                TextField("With (Us, a metamour, family…)", text: $with)
                Picker("Emoji", selection: $emoji) {
                    ForEach(["💞", "🍷", "🏡", "✈️", "🌷", "🎬", "🍽️", "🛏️", "🎉", "👪"], id: \.self) { Text($0).tag($0) }
                }
                DatePicker("Starts", selection: $start)
                DatePicker("Ends", selection: $end, in: start...)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let pid = partnerID ?? model.selectedPartnerID else { return }
                        let t = title.trimmingCharacters(in: .whitespaces)
                        let event = CalendarEvent(by: model.myRole(pid), title: t.isEmpty ? "Plans" : t, start: start,
                                                  end: max(end, start), with: with.isEmpty ? "Us" : with, emoji: emoji)
                        together.edit(pid, note: "added a plan to your calendar 📅") { syncAppend(&$0.events, event) }
                        dismiss()
                    }
                }
            }
            .onAppear { if partnerID == nil { partnerID = model.selectedPartnerID } }
        }
    }
}

/// Metamours & compersion: your partner's other partners as each of you describes them
/// (names, what's good to know, birthdays), and a little log of compersion — joy in your
/// partner's joy.
struct MetamoursView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var name = ""
    @State private var notes = ""
    @State private var emoji = "🌷"
    @State private var moment = ""

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var them: String { me == "A" ? "B" : "A" }
    private var space: TogetherSpace { together.space(id) }
    private var partnerName: String { model.selectedPartner?.displayName ?? "your partner" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                list("\(partnerName)'s other partners", syncLive(space.metamours).filter { $0.of == them },
                     empty: "\(partnerName) can add who else they're seeing, and what's good for you to know.")
                list("Your other partners (as \(partnerName) sees them)", syncLive(space.metamours).filter { $0.of == me },
                     empty: "Tell \(partnerName) about your other partners — names, boundaries, birthdays.")
                add
                compersion
            }
            .padding(16)
        }
        .navigationTitle("Metamours")
    }

    private func list(_ title: String, _ items: [Metamour], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            if items.isEmpty { Text(empty).font(Theme.font(13)).foregroundStyle(Theme.subtitle) }
            ForEach(items) { m in
                HStack(alignment: .top, spacing: 10) {
                    Text(m.emoji).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(Theme.font(15, .bold)).foregroundStyle(Theme.title)
                        if !m.notes.isEmpty { Text(m.notes).font(Theme.font(13)).foregroundStyle(Theme.subtitle) }
                    }
                    Spacer()
                    if m.of == me {
                        Button { together.edit(id) { syncDelete(&$0.metamours, m.id) } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.subtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var add: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add one of your partners").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
            HStack {
                Picker("", selection: $emoji) {
                    ForEach(["🌷", "🌻", "🌙", "⭐️", "🦋", "🍀", "🔥", "🌊"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 70)
                TextField("Name", text: $name).font(Theme.font(15))
            }
            TextField("Good to know (boundaries, how you met, what they like)…", text: $notes, axis: .vertical)
                .font(Theme.font(14)).lineLimit(1...4)
            Button("Add") {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                together.edit(id, note: "added to your metamours 🌷") {
                    syncAppend(&$0.metamours, Metamour(of: me, name: n, emoji: emoji, notes: notes))
                }
                name = ""; notes = ""
            }
            .buttonStyle(AccentButtonStyle(height: 42))
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var compersion: some View {
        let moments = syncLive(space.compersion).sorted { $0.created > $1.created }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Compersion").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text("Moments you felt happy for \(partnerName)'s happiness with someone else.")
                .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            HStack {
                TextField("I loved seeing you so happy after…", text: $moment).font(Theme.font(14))
                Button {
                    let t = moment.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    together.edit(id, note: "shared a compersion moment ✨") { syncAppend(&$0.compersion, CompersionNote(by: me, text: t)) }
                    moment = ""
                } label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent) }
            }
            .padding(10).glass(cornerRadius: 14)
            ForEach(moments.prefix(20)) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.text).font(Theme.font(14)).foregroundStyle(Theme.title)
                    Text("\(c.by == me ? "You" : partnerName) · \(c.created.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }
}
