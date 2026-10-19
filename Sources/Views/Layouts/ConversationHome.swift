import SwiftUI

/// Conversation: touches and heartbeats as bubbles in a thread — theirs on the left, yours on
/// the right, with day separators — and the touch bar docked at the bottom like a keyboard,
/// meanings as quick replies above it.
struct ConversationHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false

    /// Oldest first, so the newest sits at the bottom by the composer.
    private var thread: [TouchMessage] { model.recentTouches(limit: 60).reversed() }

    var body: some View {
        VStack(spacing: 10) {
            header
            TogetherChip()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if thread.isEmpty {
                            Text(model.selectedPartner == nil ? "Pick someone to touch." : "No touches yet. Send the first one below.")
                                .font(Theme.font(13)).foregroundStyle(Theme.subtitle).padding(.top, 40)
                        }
                        ForEach(Array(thread.enumerated()), id: \.element.id) { i, t in
                            if i == 0 || !Calendar.current.isDate(t.sentAt, inSameDayAs: thread[i - 1].sentAt) {
                                Text(dayTitle(t.sentAt))
                                    .font(Theme.font(11, .heavy)).foregroundStyle(Theme.subtitle)
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.ink.opacity(0.1)))
                                    .padding(.vertical, 4)
                            }
                            bubble(t).id(t.id)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .onAppear { if let last = thread.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: thread.last?.id) { id in
                    if let id { withAnimation(.easeOut) { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            composer
        }
        .padding(.bottom, 12)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let p = model.selectedPartner {
                Button { partnerSheet = true } label: {
                    HStack(spacing: 10) {
                        PartnerFace(partner: p, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.displayName).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                            Text(model.statusText(p)).font(Theme.font(11)).foregroundStyle(Theme.subtitle).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            if model.partners.count > 1 { PartnerBar().frame(maxWidth: 150) }
            RoundIconButton(icon: "person.2.fill", label: "People", size: 40) { people = true }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glass(cornerRadius: 28)
        .padding(.horizontal, 12).padding(.top, 8)
    }

    @ViewBuilder private func bubble(_ t: TouchMessage) -> some View {
        let mine = model.isMine(t)
        let tag = model.meaningTag(for: t)
        HStack {
            if mine { Spacer(minLength: 70) }
            Button { model.feel(t) } label: {
                VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                    if let bpm = t.heartbeatBPM {
                        Text("♥ \(bpm) BPM").font(Theme.font(12, .heavy)).foregroundStyle(Theme.title)
                    } else if let tag {
                        Text("\(tag.emoji) \(tag.label)").font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
                    }
                    TouchGlyph(touch: t, height: 38).frame(width: 180)
                    HStack(spacing: 4) {
                        Text(t.sentAt.formatted(date: .omitted, time: .shortened))
                        if mine, let d = t.delivery {
                            switch d {
                            case .seen: Text("· Seen")
                            case .sent: Text("· Sent")
                            case .sending: Text("· Sending…")
                            case .failed: Text("· Failed").foregroundStyle(Theme.danger)
                            }
                        }
                        if !mine, t.missed == true { Text("· missed").foregroundStyle(Theme.amber) }
                    }
                    .font(Theme.font(10)).foregroundStyle(Theme.subtitle)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    UnevenBubble(mine: mine)
                        .fill(mine ? Theme.accent.opacity(0.28) : .clear)
                        .background(GlassBackground(shape: UnevenBubble(mine: mine)))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(mine ? "You" : "Them"), \(tag?.label ?? (t.heartbeatBPM != nil ? "heartbeat" : "touch")). Play")
            if !mine { Spacer(minLength: 70) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            MeaningChipRow(height: 34)
            HStack(spacing: 10) {
                InlineTouchPad(shape: .bar, title: "Touch", hint: "tap & slide here").frame(height: 56)
                HeartbeatButton(size: 56)
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// A chat bubble: rounded, with the corner by the sender squared off.
struct UnevenBubble: Shape {
    var mine: Bool
    func path(in r: CGRect) -> Path {
        let big: CGFloat = 20, small: CGFloat = 6
        var p = Path()
        let tl = big, tr = big, bl = mine ? big : small, br = mine ? small : big
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}
