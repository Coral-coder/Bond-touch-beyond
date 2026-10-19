import SwiftUI

/// Agreements: what you've agreed, by topic. Each needs both of you to tap Agree; changing
/// the wording asks you both again. Set a date to look at one again.
struct AgreementsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var text = ""
    @State private var topic = "General"
    @State private var editing: Agreement?
    @State private var editText = ""

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var them: String { me == "A" ? "B" : "A" }
    private var items: [Agreement] { syncLive(together.space(id).agreements) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                propose
                let topics = Agreement.topics.filter { t in items.contains { $0.topic == t } }
                ForEach(topics, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                        ForEach(items.filter { $0.topic == t }.sorted { $0.created < $1.created }) { a in row(a) }
                    }
                    .padding(16).glass(cornerRadius: Theme.cardCorner)
                }
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Agreements")
        .alert("Change the wording", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Agreement", text: $editText)
            Button("Save — ask again") {
                guard let a = editing else { return }
                let t = editText.trimmingCharacters(in: .whitespaces)
                together.edit(id, note: "changed an agreement — have a look 🤝") {
                    syncUpdate(&$0.agreements, a.id) { x in
                        x.text = t
                        x.agreedA = me == "A" ? Date() : nil
                        x.agreedB = me == "B" ? Date() : nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var propose: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Propose an agreement").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Picker("Topic", selection: $topic) { ForEach(Agreement.topics, id: \.self) { Text($0).tag($0) } }
                .tint(Theme.accent)
            TextField("We'll text if we're running more than 15 minutes late", text: $text, axis: .vertical)
                .font(Theme.font(14)).lineLimit(1...4).padding(10).glass(cornerRadius: 14)
            Button("Propose") {
                let t = text.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                var a = Agreement(text: t, topic: topic, by: me)
                if me == "A" { a.agreedA = Date() } else { a.agreedB = Date() }
                together.edit(id, note: "proposed an agreement 🤝") { syncAppend(&$0.agreements, a) }
                text = ""
            }
            .buttonStyle(AccentButtonStyle(height: 42))
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func row(_ a: Agreement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(a.text).font(Theme.font(15, .semibold)).foregroundStyle(Theme.title)
            HStack(spacing: 10) {
                badge("You", a.agreed(me))
                badge(model.selectedPartner?.displayName ?? "Them", a.agreed(them))
                if let r = a.review {
                    Text(r <= Date() ? "Review due" : "Review \(r.formatted(date: .abbreviated, time: .omitted))")
                        .font(Theme.font(11, .bold)).foregroundStyle(r <= Date() ? Theme.danger : Theme.subtitle)
                }
                Spacer()
                Menu {
                    if !a.agreed(me) {
                        Button("Agree") {
                            together.edit(id, note: "agreed to an agreement 🤝") { syncUpdate(&$0.agreements, a.id) { x in
                                if me == "A" { x.agreedA = Date() } else { x.agreedB = Date() }
                            } }
                        }
                    }
                    Button("Change wording") { editText = a.text; editing = a }
                    Menu("Review in…") {
                        ForEach([1, 3, 6, 12], id: \.self) { m in
                            Button("\(m) month\(m == 1 ? "" : "s")") {
                                together.edit(id) { syncUpdate(&$0.agreements, a.id) { x in
                                    x.review = Calendar.current.date(byAdding: .month, value: m, to: Date())
                                } }
                            }
                        }
                    }
                    Button("Remove", role: .destructive) {
                        together.edit(id, note: "removed an agreement") { syncDelete(&$0.agreements, a.id) }
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.accent) }
            }
        }
        .padding(12).glass(cornerRadius: 16)
    }

    private func badge(_ who: String, _ ok: Bool) -> some View {
        Label(who, systemImage: ok ? "checkmark.seal.fill" : "hourglass")
            .font(Theme.font(11, .bold)).foregroundStyle(ok ? Theme.lime : Theme.subtitle).lineLimit(1)
    }
}

/// Repair tools for after a hard moment: take a time-out (your partner sees when you'll be
/// back), put a feeling into words ("I feel … when … I need …"), send a repair phrase, and
/// mark it resolved.
struct RepairView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var feel = ""
    @State private var when = ""
    @State private var need = ""
    @State private var minutes = 20

    private var id: String? { model.selectedPartnerID }
    private var me: String { model.myRole(id) }
    private var notes: [RepairNote] { syncLive(together.space(id).repairs).sorted { $0.created > $1.created } }
    private var partnerName: String { model.selectedPartner?.displayName ?? "Your partner" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                activeTimeouts
                timeout
                feeling
                phrases
                log
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Repair")
    }

    @ViewBuilder private var activeTimeouts: some View {
        let active = notes.filter { $0.kind == .timeout && ($0.until ?? .distantPast) > Date() }
        ForEach(active) { t in
            HStack(spacing: 12) {
                Text("🫖").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.by == me ? "You're taking a breather" : "\(partnerName) is taking a breather")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    Text("Back by \(t.until?.formatted(date: .omitted, time: .shortened) ?? "soon") — it's a pause, not a goodbye 💛")
                        .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                if t.by == me {
                    Button("I'm back") {
                        together.edit(id, note: "is back and ready to talk 💛") { syncUpdate(&$0.repairs, t.id) { $0.until = Date() } }
                    }
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(14).glass(cornerRadius: Theme.cardCorner)
        }
    }

    private var timeout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Need a time-out?").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text("Flooded? Take 20 minutes to calm down — your partner gets a gentle note that you're coming back.")
                .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            Picker("Minutes", selection: $minutes) {
                ForEach([10, 20, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Take a breather") {
                let note = RepairNote(by: me, kind: .timeout, until: Date().addingTimeInterval(Double(minutes) * 60))
                together.edit(id, note: "needs a \(minutes)-minute breather — they'll be back 💛") { syncAppend(&$0.repairs, note) }
            }
            .buttonStyle(AccentButtonStyle(height: 44))
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var feeling: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Say how you feel").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            field("I feel…", "hurt, lonely, worried", $feel)
            field("when…", "plans change last minute", $when)
            field("I need…", "a heads-up, a hug, some time", $need)
            Button("Share") {
                let parts = ["I feel \(feel)", when.isEmpty ? nil : "when \(when)", need.isEmpty ? nil : "— I need \(need)"].compactMap { $0 }
                together.edit(id, note: "shared how they feel 💬") { syncAppend(&$0.repairs, RepairNote(by: me, kind: .feeling, text: parts.joined(separator: " "))) }
                feel = ""; when = ""; need = ""
            }
            .buttonStyle(AccentButtonStyle(height: 42))
            .disabled(feel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private func field(_ label: String, _ hint: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).font(Theme.font(14, .bold)).foregroundStyle(Theme.accent).frame(width: 70, alignment: .leading)
            TextField(hint, text: text).font(Theme.font(14))
        }
        .padding(10).glass(cornerRadius: 12)
    }

    private var phrases: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repair attempts").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
            Text("A small bid to turn back toward each other. Tap one to send it.").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            FlowLayout(spacing: 6) {
                ForEach(RepairNote.repairs, id: \.self) { r in
                    Button(r) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        together.edit(id, note: "reached out to make things right 💛") { syncAppend(&$0.repairs, RepairNote(by: me, kind: .repair, text: r)) }
                    }
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.title)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(Capsule().fill(Theme.ink.opacity(0.1)))
                    .buttonStyle(.plain)
                }
            }
            Button("We're good now 🤍") {
                together.edit(id, note: "marked things as resolved 🤍") { syncAppend(&$0.repairs, RepairNote(by: me, kind: .resolved, text: "We talked it through.")) }
            }
            .font(Theme.font(14, .bold)).foregroundStyle(Theme.lime)
        }
        .padding(16).glass(cornerRadius: Theme.cardCorner)
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notes.isEmpty { Text("Recently").font(Theme.font(15, .heavy)).foregroundStyle(Theme.title) }
            ForEach(notes.filter { $0.kind != .timeout }.prefix(20)) { n in
                HStack(alignment: .top, spacing: 8) {
                    Text(n.kind == .feeling ? "💬" : n.kind == .repair ? "💛" : "🤍")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.text).font(Theme.font(14)).foregroundStyle(Theme.title)
                        Text("\(n.by == me ? "You" : partnerName) · \(n.created.formatted(.relative(presentation: .named)))")
                            .font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                    }
                }
            }
        }
    }
}

/// Lays chips out in rows, wrapping as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
