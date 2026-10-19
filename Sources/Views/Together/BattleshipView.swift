import SwiftUI

/// Battleship with your partner. Place your fleet (shuffle until you like it), then take
/// turns firing at each other's waters. Your partner's phone answers each shot itself, so
/// your ships stay secret until the end.
struct BattleshipView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var draft = BattleshipGame.randomFleet()
    @State private var confirmNew = false

    private var bondID: String? { model.selectedPartnerID }
    private var game: BattleshipGame? { together.space(bondID).battleship }
    private var me: String { model.myRole(bondID) }
    private var them: String { me == "A" ? "B" : "A" }
    private var name: String { model.selectedPartner?.displayName ?? "them" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let game, let fleet = BattleshipGame.loadFleet(game.id) {
                    play(game, fleet: fleet)
                } else {
                    placement
                }
                Button("New game") { confirmNew = true }.font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            }
            .padding(16)
        }
        .navigationTitle("Battleship").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.answerBattleship(bondID) }
        .onChange(of: game?.events.count) { _ in model.answerBattleship(bondID) }
        .confirmationDialog("Start a new game of Battleship?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New game") { together.edit(bondID, note: "started a new game of Battleship 🚢") { $0.battleship = BattleshipGame() } }
        }
    }

    // MARK: Placement

    private var placement: some View {
        VStack(spacing: 14) {
            Text("Place your fleet").font(Theme.font(20, .heavy)).foregroundStyle(Theme.title)
            Text("Shuffle until you like it. Only your phone knows where they are.").font(Theme.font(13)).foregroundStyle(Theme.subtitle)
            grid(cell: { c in
                draft.contains { $0.contains(c) } ? AnyView(shipCell) : AnyView(waterCell)
            }, tap: nil)
            HStack(spacing: 12) {
                Button("Shuffle") { draft = BattleshipGame.randomFleet() }.buttonStyle(GlassButtonStyle(height: 48))
                Button("Ready") { ready() }.buttonStyle(AccentButtonStyle(height: 48))
            }
        }
    }

    private func ready() {
        let salt = UUID().uuidString
        together.edit(bondID, note: "placed their fleet 🚢 — place yours!") { s in
            if s.battleship == nil { s.battleship = BattleshipGame() }
            BattleshipGame.saveFleet(draft, gameID: s.battleship!.id)
            s.battleship?.add("ready:\(me):\(BattleshipGame.fingerprint(draft, salt: salt))")
        }
    }

    // MARK: Play

    @ViewBuilder private func play(_ g: BattleshipGame, fleet: BattleshipGame.Fleet) -> some View {
        let mine = g.results(for: me)          // my shots at them
        let theirs = Set(g.shots(by: them))    // their shots at me
        Text(status(g)).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
            .padding(.horizontal, 16).padding(.vertical, 8).glass(Capsule())
        Text("\(name)'s waters — tap to fire").font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
        grid(cell: { c in
            switch mine[c] {
            case "m": return AnyView(ZStack { waterCell; Circle().fill(.white.opacity(0.7)).frame(width: 7, height: 7) })
            case .some(let r) where r.hasPrefix("s"): return AnyView(ZStack { Rectangle().fill(Color(rgbInt: 0x7A1E2A)); Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) })
            case "h": return AnyView(ZStack { waterCell; Image(systemName: "flame.fill").font(.system(size: 13)).foregroundStyle(Color(rgbInt: 0xFF7A2E)) })
            default:
                let pending = g.shots(by: me).contains(c)
                return AnyView(ZStack { waterCell; if pending { ProgressView().scaleEffect(0.6) } })
            }
        }, tap: { c in fire(c, g) })
        Text("Your fleet").font(Theme.font(13, .bold)).foregroundStyle(Theme.subtitle)
        grid(cell: { c in
            let ship = fleet.contains { $0.contains(c) }
            return AnyView(ZStack {
                ship ? AnyView(shipCell) : AnyView(waterCell)
                if theirs.contains(c) {
                    if ship { Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Color(rgbInt: 0xFF7A2E)) } else { Circle().fill(.white.opacity(0.7)).frame(width: 7, height: 7) }
                }
            })
        }, tap: nil, small: true)
        Text("Hits: you \(g.hits(by: me))/\(BattleshipGame.totalCells) · \(name) \(g.hits(by: them))/\(BattleshipGame.totalCells)")
            .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
    }

    private func fire(_ c: Int, _ g: BattleshipGame) {
        guard g.turn == me, !g.shots(by: me).contains(c) else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        together.edit(bondID, note: "fired a shot 💣 — your turn") { s in s.battleship?.add("shot:\(me):\(c)") }
    }

    private func status(_ g: BattleshipGame) -> String {
        if let w = g.winner { return w == me ? "You sank their fleet!" : "\(name) sank your fleet" }
        if !g.ready(them) { return "Waiting for \(name) to place their fleet…" }
        if g.turn == me { return "Your shot" }
        if g.turn == nil { return "Waiting for the answer…" }
        return "Waiting for \(name)…"
    }

    // MARK: Grid

    private var waterCell: some View {
        Rectangle().fill(LinearGradient(colors: [Color(rgbInt: 0x1E6FB8), Color(rgbInt: 0x0E4A80)], startPoint: .top, endPoint: .bottom))
    }

    private var shipCell: some View {
        Rectangle().fill(LinearGradient(colors: [Color(rgbInt: 0x9AA4AE), Color(rgbInt: 0x5C6670)], startPoint: .top, endPoint: .bottom))
    }

    private func grid(cell: @escaping (Int) -> AnyView, tap: ((Int) -> Void)?, small: Bool = false) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) / 10
            VStack(spacing: 1) {
                ForEach(0..<10, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(0..<10, id: \.self) { c in
                            cell(r * 10 + c)
                                .frame(width: side - 1, height: side - 1)
                                .contentShape(Rectangle())
                                .onTapGesture { tap?(r * 10 + c) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: small ? 220 : .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
