import SwiftUI

/// Orbit: you in the middle, your people circling you, glowing when they're online. Drag
/// from yourself to someone (or tap them) to pick them; a light runs along the line between
/// you, and their last touch, meanings and a touch bar sit in the panel below.
struct OrbitHome: View {
    @EnvironmentObject var model: AppModel
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var drag: CGPoint?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HeartbeatButton()
                Spacer()
                VStack(spacing: 1) {
                    Text("Orbit").font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                    Text("Drag from you to someone").font(Theme.font(11)).foregroundStyle(Theme.subtitle)
                }
                Spacer()
                RoundIconButton(icon: "person.2.fill", label: "People") { people = true }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            GeometryReader { geo in
                let size = geo.size, c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 44
                let spots = positions(count: model.partners.count, center: c, radius: r)
                ZStack {
                    Circle().stroke(Theme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                        .frame(width: r * 2, height: r * 2).position(c)
                    Circle().stroke(Theme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                        .frame(width: r * 1.25, height: r * 1.25).position(c)

                    // The line to the selected person, with a light travelling along it.
                    if let i = model.partners.firstIndex(where: { $0.id == model.selectedPartnerID }), i < spots.count {
                        let to = spots[i]
                        Path { p in p.move(to: c); p.addLine(to: to) }
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 7]))
                            .shadow(color: Theme.accent, radius: 4)
                        TimelineView(.animation) { ctx in
                            let t = CGFloat(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6)
                            Circle().fill(Theme.pink).frame(width: 10, height: 10).shadow(color: Theme.pink, radius: 6)
                                .position(x: c.x + (to.x - c.x) * t, y: c.y + (to.y - c.y) * t)
                        }
                    }
                    if let drag {
                        Path { p in p.move(to: c); p.addLine(to: drag) }
                            .stroke(Theme.title.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }

                    ForEach(Array(model.partners.enumerated()), id: \.element.id) { i, p in
                        if i < spots.count {
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.35)) { model.selectedPartnerID = p.id }
                            } label: {
                                VStack(spacing: 3) {
                                    PartnerFace(partner: p, size: p.id == model.selectedPartnerID ? 62 : 48,
                                                selected: p.id == model.selectedPartnerID)
                                        .shadow(color: p.online ? Theme.lime.opacity(0.6) : .clear, radius: 10)
                                    Text(p.displayName).font(Theme.font(12, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .position(spots[i])
                        }
                    }

                    MyFace(size: 84)
                        .shadow(color: Theme.magenta.opacity(0.6), radius: 18)
                        .position(c)
                        .gesture(DragGesture(minimumDistance: 6)
                            .onChanged { v in drag = CGPoint(x: c.x + v.translation.width, y: c.y + v.translation.height) }
                            .onEnded { v in
                                let end = CGPoint(x: c.x + v.translation.width, y: c.y + v.translation.height)
                                drag = nil
                                if let i = spots.indices.min(by: { dist(spots[$0], end) < dist(spots[$1], end) }),
                                   dist(spots[i], end) < 70, i < model.partners.count {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    model.selectedPartnerID = model.partners[i].id
                                    compose = true
                                }
                            })
                        .accessibilityLabel("You. Drag to someone to touch them")
                }
            }

            panel
        }
        .padding(.bottom, 92)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
    }

    @ViewBuilder private var panel: some View {
        if let p = model.selectedPartner {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button { partnerSheet = true } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.displayName).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                            Text(model.statusText(p)).font(Theme.font(11)).foregroundStyle(Theme.subtitle).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let last = model.recentTouches().first {
                        Button { model.feel(last) } label: { TouchGlyph(touch: last, height: 28).frame(width: 120) }
                            .buttonStyle(.plain).accessibilityLabel("Replay the last touch")
                    }
                }
                MeaningChipRow(height: 32)
                InlineTouchPad(shape: .bar, title: "Touch \(p.displayName)", hint: "tap & slide").frame(height: 52)
            }
            .padding(12)
            .glass(cornerRadius: 26)
            .padding(.horizontal, 12)
        }
    }

    private func positions(count: Int, center c: CGPoint, radius r: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let a = -Double.pi / 3 + Double(i) * 2 * .pi / Double(max(count, 3))
            // Alternate between the outer and inner orbit so faces don't crowd.
            let rr = i % 2 == 0 ? r : r * 0.62
            return CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
