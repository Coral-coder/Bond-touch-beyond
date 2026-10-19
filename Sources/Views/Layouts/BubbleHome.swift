import SwiftUI

/// Bubbles: Home as a cluster of glossy floating bubbles, gently bobbing — a big touch bubble
/// in the middle you touch directly, your partner, your days together, the heartbeat,
/// meanings and your latest touches each in their own bubble.
struct BubbleHome: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var people = false
    @State private var partnerSheet = false
    @State private var compose = false
    @State private var history = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                PartnerBar()
                Spacer()
            }
            .padding(.top, 8)

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        if let p = model.selectedPartner {
                            bubble(at: (0.3, 0.15), size: w * 0.36, t: t, phase: 0, w: w, h: h) {
                                Button { partnerSheet = true } label: {
                                    VStack(spacing: 2) {
                                        PartnerFace(partner: p, size: w * 0.16)
                                        Text(p.displayName).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title).lineLimit(1)
                                        Text(p.online ? "online" : "away").font(Theme.font(10)).foregroundStyle(Theme.subtitle)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        bubble(at: (0.77, 0.12), size: w * 0.27, t: t, phase: 1.3, w: w, h: h) {
                            togetherBubble
                        }

                        bubble(at: (0.84, 0.33), size: w * 0.2, t: t, phase: 2.1, w: w, h: h) {
                            HeartbeatButton(size: w * 0.16).clipShape(Circle())
                        }

                        bubble(at: (0.1, 0.37), size: w * 0.15, t: t, phase: 0.7, w: w, h: h) {
                            Button { people = true } label: {
                                Image(systemName: "person.2.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.title)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.plain).accessibilityLabel("People")
                        }

                        // The big touch bubble.
                        bubble(at: (0.5, 0.52), size: w * 0.6, t: t, phase: 3.0, w: w, h: h, amplitude: 2) {
                            InlineTouchPad(shape: .ring, title: "Touch", hint: "tap · hold · slide")
                                .padding(4)
                        }

                        ForEach(Array(model.currentMeanings.prefix(5).enumerated()), id: \.element.id) { i, m in
                            let spots: [(Double, Double)] = [(0.14, 0.72), (0.38, 0.86), (0.64, 0.84), (0.88, 0.68), (0.12, 0.93)]
                            bubble(at: spots[i], size: w * 0.21, t: t, phase: Double(i) * 0.9 + 4, w: w, h: h) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    Task { await model.sendMeaning(m) }
                                } label: {
                                    VStack(spacing: 1) {
                                        if !m.emoji.isEmpty { Text(m.emoji).font(.system(size: 18)) }
                                        Text(m.label).font(Theme.font(12, .heavy)).foregroundStyle(Theme.title)
                                            .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.plain).accessibilityLabel("Send \(m.label)")
                            }
                        }

                        if let last = model.recentTouches().first {
                            bubble(at: (0.86, 0.92), size: w * 0.19, t: t, phase: 5.5, w: w, h: h) {
                                Button { history = true } label: {
                                    TouchGlyph(touch: last, height: w * 0.07).padding(10)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.plain).accessibilityLabel("Recent touches")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 92)
        .modifier(HomeSheets(people: $people, partner: $partnerSheet, compose: $compose))
        .sheet(isPresented: $history) { TouchHistorySheet() }
    }

    @ViewBuilder private var togetherBubble: some View {
        if let since = together.space(model.selectedPartnerID).togetherSince {
            VStack(spacing: 0) {
                Text("\(TogetherSpace.days(since: since))").font(Theme.font(22, .heavy)).foregroundStyle(Theme.title)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("days").font(Theme.font(11, .bold)).foregroundStyle(Theme.subtitle)
            }
            .padding(6)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.pink)
                Text("Us").font(Theme.font(13, .heavy)).foregroundStyle(Theme.title)
            }
        }
    }

    /// A glossy bubble holding `content`, bobbing gently around its spot.
    private func bubble<C: View>(at spot: (Double, Double), size: CGFloat, t: Double, phase: Double,
                                 w: CGFloat, h: CGFloat, amplitude: CGFloat = 5,
                                 @ViewBuilder content: () -> C) -> some View {
        let dx = CGFloat(sin(t * 0.7 + phase)) * amplitude, dy = CGFloat(cos(t * 0.9 + phase * 1.3)) * amplitude
        return content()
            .frame(width: size, height: size)
            .background(BubbleShell())
            .clipShape(Circle())
            .overlay(BubbleShine().allowsHitTesting(false))
            .shadow(color: Theme.accent.opacity(0.25), radius: 10, y: 4)
            .position(x: w * spot.0 + dx, y: h * spot.1 + dy)
    }
}

/// The body of a bubble: clear glass tinted with the theme, a bright rim.
struct BubbleShell: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.ink.opacity(0.04), Theme.accent.opacity(0.10), Theme.accent.opacity(0.28)],
                                         center: .center, startRadius: 0, endRadius: 120))
            Circle().fill(.ultraThinMaterial).opacity(0.35)
            Circle().stroke(LinearGradient(colors: [.white.opacity(0.9), Theme.accent.opacity(0.4), .white.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        }
    }
}

/// A bubble's shine: a soft highlight top-left and a small glint bottom-right.
struct BubbleShine: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.5, height: d * 0.28)
                    .rotationEffect(.degrees(-28))
                    .position(x: d * 0.34, y: d * 0.22)
                Circle().fill(.white.opacity(0.55)).frame(width: d * 0.07, height: d * 0.07)
                    .position(x: d * 0.76, y: d * 0.78)
            }
        }
    }
}
