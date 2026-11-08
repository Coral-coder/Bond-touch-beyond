import SwiftUI

/// Send a touch or send a kiss, side by side — on a partner's page and under a kiss that lands.
struct TouchOrKissRow: View {
    @EnvironmentObject var model: AppModel
    let bondID: String
    var name: String
    var onDone: (() -> Void)? = nil
    @State private var sent: String?

    var body: some View {
        HStack(spacing: 10) {
            button("touch", sent == "touch" ? "Sent ✓" : "Send a touch", emoji: "❤️") {
                await model.sendQuickTouch(toBondID: bondID)
            }
            button("kiss", sent == "kiss" ? "Kissed ✓" : "Send a kiss", emoji: "💋") {
                await model.sendKiss(toBondID: bondID)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func button(_ id: String, _ title: String, emoji: String, _ action: @escaping () async -> Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task {
                if await action() {
                    sent = id
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    sent = nil
                    onDone?()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(emoji).font(.system(size: Theme.s(20)))
                Text(title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.title)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .glass(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id == "kiss" ? "Send \(name) a kiss" : "Send \(name) a touch")
    }
}

/// A partner's kiss arriving with the app open: lips and hearts float up the screen, and a card
/// says "{name} kissed you! 💋" with Kiss back and Send a touch.
struct KissOverlay: View {
    @EnvironmentObject var model: AppModel
    let show: KissShow
    @State private var start = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            FloatingKisses(start: start)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AvatarRing(name: show.name, ringColor: Theme.pink, size: 46, photo: model.photo(forBond: show.bondID))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(show.name) kissed you! 💋").font(Theme.font(19, .heavy)).foregroundStyle(Theme.title)
                        Text("Send one back").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
                    }
                    Spacer()
                    Button { model.kissShow = nil } label: {
                        Image(systemName: "xmark").font(.system(size: Theme.s(13), weight: .bold))
                            .foregroundStyle(Theme.subtitle).frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Close")
                }
                TouchOrKissRow(bondID: show.bondID, name: show.name) { model.kissShow = nil }
            }
            .padding(16)
            .glass(cornerRadius: 26)
            .padding(.horizontal, 14).padding(.bottom, 100)
        }
        .onAppear { start = Date() }
    }
}

/// Lips and hearts drifting up from the bottom, swaying, for a few seconds.
private struct FloatingKisses: View {
    let start: Date
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let marks = ["💋", "❤️", "💕", "💋", "💗", "💋"]
                for i in 0..<18 {
                    let delay = Double(i) * 0.22
                    let life = t - delay
                    guard life > 0, life < 4.2 else { continue }
                    let seed = Double((i * 37) % 17) / 17
                    let x = size.width * (0.1 + 0.8 * seed) + sin(life * 2.2 + Double(i)) * 18
                    let y = size.height + 40 - life * (size.height * 0.28 + 60 * seed)
                    var c = ctx
                    c.opacity = min(1, life * 3) * max(0, 1 - life / 4.2)
                    let scale = 0.8 + seed * 0.9
                    c.draw(Text(marks[i % marks.count]).font(.system(size: 30 * scale)), at: CGPoint(x: x, y: y))
                }
            }
        }
    }
}

/// A touch (or kiss) sent from Matrix mode, arriving: the whole screen goes Matrix while it
/// plays — fast, dense rain with the sender's face in the code and their name glitching in
/// the middle — then fades back to your own theme.
struct MatrixTakeover: View {
    @EnvironmentObject var model: AppModel
    let show: MatrixShow
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let fadeIn = min(1, t / 0.35)
            let fadeOut = min(1, max(0, (show.seconds - t) / 0.6))
            ZStack {
                MatrixRain(face: model.photo(forBond: show.bondID), intensity: 1.7)
                // The flash as it breaks in.
                Color(red: 0.6, green: 1, blue: 0.7).opacity(max(0, 0.5 - t * 1.6))
                VStack(spacing: 10) {
                    GlitchText(text: "♥", size: 86, t: t)
                    GlitchText(text: show.name.uppercased(), size: 34, t: t + 0.37)
                    GlitchText(text: show.label, size: 18, t: t + 0.71)
                    Text("wake up, \(model.store.profile.name.isEmpty ? "love" : model.store.profile.name.lowercased())…")
                        .font(.system(size: Theme.s(13), weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0, green: 0.8, blue: 0.25))
                        .opacity(t > 1.2 ? 1 : 0)
                        .padding(.top, 8)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)).blur(radius: 12))
            }
            .opacity(fadeIn * fadeOut)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { model.matrixShow = nil }
        .onAppear { start = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(show.name) \(show.label), in Matrix mode")
    }
}

/// Text in code green that glitches: an RGB-split ghost, sideways tears and the odd flicker.
struct GlitchText: View {
    let text: String
    var size: CGFloat
    var t: Double

    var body: some View {
        let tick = Int(t * 12)
        let r = Double(abs((tick &* 2_654_435_761) % 1000)) / 1000
        let tearing = r < 0.16
        let dx: CGFloat = tearing ? CGFloat(r * 60 - 4) : 0
        let base = Text(text).font(.system(size: Theme.s(size), weight: .black, design: .monospaced))
        ZStack {
            base.foregroundStyle(Color(red: 0, green: 1, blue: 0.4).opacity(0.55)).offset(x: -2 - dx * 0.4, y: 0)
            base.foregroundStyle(Color(red: 0.75, green: 1, blue: 0.3).opacity(0.45)).offset(x: 2 + dx * 0.3, y: tearing ? 1 : 0)
            base.foregroundStyle(Color(red: 0.82, green: 1, blue: 0.86))
                .shadow(color: Color(red: 0, green: 1, blue: 0.25), radius: 8)
                .offset(x: dx * 0.15)
                .opacity(r > 0.95 ? 0.35 : 1)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.5)
    }
}
