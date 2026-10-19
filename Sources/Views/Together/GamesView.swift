import SwiftUI

/// Games you play together, a turn at a time through iCloud: chess, checkers, backgammon and
/// pool. Each shows whose turn it is.
struct GamesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore

    private var space: TogetherSpace { together.space(model.selectedPartnerID) }
    private var me: String { model.myRole(model.selectedPartnerID) }
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                game("Pool", "🎱", poolStatus, [0x1F9A5A, 0x116B3C]) { PoolView() }
                game("Chess", "♟️", chessStatus, [0xB58863, 0x6B4A2E]) { ChessView() }
                game("Checkers", "🔴", checkersStatus, [0xB0182A, 0x5B3A29]) { CheckersView() }
                game("Backgammon", "🎲", backgammonStatus, [0x2F6B45, 0x5B3A29]) { BackgammonView() }
                game("Battleship", "🚢", battleshipStatus, [0x1E6FB8, 0x0E2A4A]) { BattleshipView() }
                if Feature.coop.isOn {
                    game("Story together", "📖", storyStatus, [0x8E5BD6, 0x3F2A7A]) { StoryTogetherView() }
                    game("Same wavelength", "🌊", wavelengthStatus, [0x18A5B8, 0x0E4A6A]) { WavelengthView() }
                }
            }
            .padding(16).padding(.bottom, 90)
        }
        .navigationTitle("Games")
    }

    private func game<D: View>(_ title: String, _ icon: String, _ status: String, _ rgb: [Int],
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination().screenBackground() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(icon).font(.system(size: 40))
                Spacer(minLength: 0)
                Text(title).font(Theme.font(18, .heavy)).foregroundStyle(.white)
                Text(status).font(Theme.font(12, .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(LinearGradient(colors: rgb.map { Color(rgbInt: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func turn(_ aToMove: Bool) -> String { (aToMove ? "A" : "B") == me ? "Your turn" : "Their turn" }

    private var chessStatus: String {
        guard let g = space.chess else { return "Start a game" }
        if g.resigned != nil { return "Game over" }
        let p = ChessPosition.from(moves: g.moves)
        if p.status == .checkmate { return "Checkmate" }
        if p.status == .stalemate { return "Stalemate" }
        return turn(p.whiteToMove)
    }

    private var checkersStatus: String {
        guard let g = space.checkers else { return "Start a game" }
        let p = CheckersPosition.from(moves: g.moves)
        if let w = p.winner { return w == me ? "You won 🏆" : "They won" }
        return turn(p.aToMove)
    }

    private var backgammonStatus: String {
        guard let g = space.backgammon else { return "Start a game" }
        let p = BackgammonPosition.from(moves: g.moves)
        if let w = p.winner { return w == me ? "You won 🏆" : "They won" }
        return turn(p.aToMove)
    }

    private var battleshipStatus: String {
        guard let g = space.battleship else { return "Place your fleet" }
        if let w = g.winner { return w == me ? "You won 🏆" : "They won" }
        if BattleshipGame.loadFleet(g.id) == nil { return "Place your fleet" }
        if g.turn == nil { return "Waiting…" }
        return g.turn == me ? "Your shot" : "Their shot"
    }

    private var storyStatus: String {
        let lines = syncLive(space.story).sorted { $0.created < $1.created }
        guard let last = lines.last else { return "Write one, a line each" }
        return last.by == me ? "Their line" : "Your line"
    }

    private var wavelengthStatus: String {
        let them = me == "A" ? "B" : "A"
        var mine: [Int: Int] = [:], theirs: [Int: Int] = [:]
        for p in syncLive(space.wavelength) {
            if p.by == me { mine[p.q] = p.pick } else if p.by == them { theirs[p.q] = p.pick }
        }
        var both = 0, matches = 0
        for (q, pick) in mine {
            guard let other = theirs[q] else { continue }
            both += 1
            if other == pick { matches += 1 }
        }
        return both == 0 ? "Co-op: think alike" : "\(matches) / \(both) in sync"
    }

    private var poolStatus: String {
        guard let g = space.pool else { return "Rack 'em up" }
        let shots = g.moves.compactMap { try? JSONDecoder().decode(Pool.Shot.self, from: Data($0.utf8)) }
        let s = Pool.state(shots)
        if let w = s.winner { return w == me ? "You won 🏆" : "They won" }
        return turn(s.aToShoot)
    }
}
