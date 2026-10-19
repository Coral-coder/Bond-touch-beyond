import SwiftUI

/// 8-ball pool with your partner. Drag on the table to aim (a guide line shows where the
/// cue ball goes), set the power, and shoot; the shot plays out with real physics. Pot your
/// group (solids or stripes, picked by your first pot), then the 8. Your partner sees each
/// shot replayed on their phone.
struct PoolView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var angle = Double.pi
    @State private var power = 0.6
    @State private var frames: [Pool.Rack] = []
    @State private var frame = 0
    @State private var seenShots = -1
    @State private var confirmNew = false
    @State private var animating = false

    private var bondID: String? { model.selectedPartnerID }
    private var shots: [Pool.Shot] {
        (together.space(bondID).pool?.moves ?? []).compactMap { try? JSONDecoder().decode(Pool.Shot.self, from: Data($0.utf8)) }
    }
    private var me: String { model.myRole(bondID) }

    var body: some View {
        let state = Pool.state(shots)
        let myTurn = (state.aToShoot ? "A" : "B") == me && state.winner == nil && !animating
        let shown = animating && frame < frames.count ? frames[frame] : state.balls
        VStack(spacing: 12) {
            Text(status(state, myTurn: myTurn)).font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                .padding(.horizontal, 16).padding(.vertical, 8).glass(Capsule())

            GeometryReader { geo in
                let scale = min(geo.size.width / (Pool.width + 0.16), geo.size.height / (Pool.height + 0.16))
                Canvas { ctx, size in
                    drawTable(&ctx, size: size, scale: scale, balls: shown, aim: myTurn ? angle : nil, power: power)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    guard myTurn, let cue = state.balls[0] else { return }
                    let origin = tableOrigin(geo.size, scale)
                    let tx = (v.location.x - origin.x) / scale, ty = (v.location.y - origin.y) / scale
                    angle = Double(atan2(ty - cue.y, tx - cue.x))
                })
            }
            .aspectRatio((Pool.width + 0.16) / (Pool.height + 0.16), contentMode: .fit)

            HStack(spacing: 12) {
                Text("Power").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                Slider(value: $power, in: 0.05...1).tint(Theme.accent).disabled(!myTurn)
                Button("Shoot") { shoot(state) }.buttonStyle(AccentButtonStyle(height: 44)).frame(width: 110).disabled(!myTurn)
            }
            groups(state)
            HStack {
                Text("Drag on the table to aim").font(Theme.font(12)).foregroundStyle(Theme.subtitle)
                Spacer()
                Button("New game") { confirmNew = true }.font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(16).padding(.bottom, 84)
        .navigationTitle("Pool").navigationBarTitleDisplayMode(.inline)
        .onAppear { seenShots = shots.count; aimAtNearest(state) }
        .onChange(of: shots.count) { n in
            // The partner shot: replay it.
            guard n > seenShots, let last = shots.last, last.by != me else { seenShots = n; return }
            seenShots = n
            let run = Pool.simulate(Pool.decode(last.start), angle: last.angle, power: last.power)
            play(run.frames + [Pool.decode(last.end)])
        }
        .confirmationDialog("Rack up a new game of pool?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New game") { together.edit(bondID, note: "racked up a new game of pool 🎱") { $0.pool = ChessGame() } }
        }
    }

    // MARK: Drawing

    private func tableOrigin(_ size: CGSize, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: (size.width - Pool.width * scale) / 2, y: (size.height - Pool.height * scale) / 2)
    }

    private static let colors: [Int] = [0xFFFFFF, 0xF6C40E, 0x1E4FC2, 0xD7261E, 0x5B2A86, 0xF07A12, 0x1E7A3A, 0x7A1E2A, 0x111111,
                                        0xF6C40E, 0x1E4FC2, 0xD7261E, 0x5B2A86, 0xF07A12, 0x1E7A3A, 0x7A1E2A]

    private func drawTable(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat, balls: Pool.Rack, aim: Double?, power: Double) {
        let o = tableOrigin(size, scale)
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: o.x + p.x * scale, y: o.y + p.y * scale) }
        let felt = CGRect(x: o.x, y: o.y, width: Pool.width * scale, height: Pool.height * scale)
        let railW = 0.07 * scale
        ctx.fill(Path(roundedRect: felt.insetBy(dx: -railW, dy: -railW), cornerRadius: railW * 0.8),
                 with: .linearGradient(Gradient(colors: [Color(rgbInt: 0x7A4A2A), Color(rgbInt: 0x4A2A16)]),
                                       startPoint: CGPoint(x: 0, y: felt.minY), endPoint: CGPoint(x: 0, y: felt.maxY)))
        ctx.fill(Path(felt), with: .radialGradient(Gradient(colors: [Color(rgbInt: 0x1F9A5A), Color(rgbInt: 0x116B3C)]),
                                                   center: CGPoint(x: felt.midX, y: felt.midY), startRadius: 0, endRadius: felt.width * 0.6))
        for p in Pool.pockets {
            let c = pt(p), r = Pool.pocketRadius * scale
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.black))
        }
        // Aim guide.
        if let aim, let cue = balls[0] {
            let dx = CGFloat(cos(aim)), dy = CGFloat(sin(aim))
            var line = Path()
            line.move(to: pt(cue))
            line.addLine(to: pt(CGPoint(x: cue.x + dx * 0.9, y: cue.y + dy * 0.9)))
            ctx.stroke(line, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            var cueStick = Path()
            let back = CGFloat(0.06 + power * 0.18)
            cueStick.move(to: pt(CGPoint(x: cue.x - dx * back, y: cue.y - dy * back)))
            cueStick.addLine(to: pt(CGPoint(x: cue.x - dx * (back + 0.75), y: cue.y - dy * (back + 0.75))))
            ctx.stroke(cueStick, with: .linearGradient(Gradient(colors: [Color(rgbInt: 0xF3E2C3), Color(rgbInt: 0x6B3E1F)]),
                                                     startPoint: pt(cue), endPoint: pt(CGPoint(x: cue.x - dx, y: cue.y - dy))),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        for (i, b) in balls.enumerated() {
            guard let b else { continue }
            let c = pt(b), r = Pool.radius * scale
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 1, dy: 1.5)), with: .color(.black.opacity(0.35)))
            let color = Color(rgbInt: Self.colors[i])
            if i >= 9 {
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                var band = ctx
                band.clip(to: Path(ellipseIn: rect))
                band.fill(Path(CGRect(x: rect.minX, y: c.y - r * 0.55, width: r * 2, height: r * 1.1)), with: .color(color))
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
            if i > 0 {
                let dot = CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9)
                ctx.fill(Path(ellipseIn: dot), with: .color(.white))
                ctx.draw(Text("\(i)").font(.system(size: r * 0.7, weight: .heavy)).foregroundColor(.black), at: c)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.7, width: r * 0.5, height: r * 0.35)),
                     with: .color(.white.opacity(0.55)))
        }
    }

    @ViewBuilder private func groups(_ s: Pool.State) -> some View {
        let mineSolids = s.solids.map { $0 == me }
        HStack(spacing: 8) {
            Text(mineSolids == nil ? "Open table" : mineSolids! ? "You: solids" : "You: stripes")
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.title)
            Spacer()
            let left = (1...15).filter { $0 != 8 && s.balls[$0] != nil }
            Text("Left: \(left.filter { $0 < 8 }.count) solids · \(left.filter { $0 > 8 }.count) stripes")
                .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
        }
    }

    // MARK: Play

    private func aimAtNearest(_ s: Pool.State) {
        guard let cue = s.balls[0],
              let target = s.balls.enumerated().dropFirst().compactMap({ $0.element }).min(by: { hypot($0.x - cue.x, $0.y - cue.y) < hypot($1.x - cue.x, $1.y - cue.y) })
        else { return }
        angle = Double(atan2(target.y - cue.y, target.x - cue.x))
    }

    private func shoot(_ s: Pool.State) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let run = Pool.simulate(s.balls, angle: angle, power: power)
        let end = run.frames.last ?? s.balls
        let shot = Pool.Shot(by: me, angle: angle, power: power, start: Pool.encode(s.balls), end: Pool.encode(end),
                             potted: run.potted, firstHit: run.firstHit, scratch: run.potted.contains(0) || run.firstHit == nil)
        seenShots = shots.count + 1
        play(run.frames)
        let after = Pool.state(shots + [shot])
        let note = after.winner.map { $0 == me ? "won at pool 🎱🏆" : "potted the 8 too early 🎱 — you win" }
            ?? ((after.aToShoot ? "A" : "B") == me ? nil : "took their shot 🎱 — your turn")
        let encoded = (try? JSONEncoder().encode(shot)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(run.frames.count) / 60 + 0.2) {
            together.edit(bondID, note: note) { sp in
                if sp.pool == nil { sp.pool = ChessGame() }
                sp.pool?.moves.append(encoded)
                sp.pool?.edited = Date()
            }
            aimAtNearest(after)
        }
    }

    private func play(_ f: [Pool.Rack]) {
        frames = f
        frame = 0
        animating = true
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
            if frame + 1 >= frames.count { t.invalidate(); animating = false; return }
            frame += 1
        }
    }

    private func status(_ s: Pool.State, myTurn: Bool) -> String {
        if let w = s.winner { return w == me ? "You win! 🎉" : "\(model.selectedPartner?.displayName ?? "They") won" }
        if animating { return "…" }
        if myTurn { return s.lastShot?.scratch == true && s.lastShot?.by != me ? "Ball in hand — your shot" : "Your shot" }
        return "Waiting for \(model.selectedPartner?.displayName ?? "them")…"
    }
}
