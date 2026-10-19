import SwiftUI

/// Checkers with your partner, a move at a time through iCloud. Tap a piece, then where it
/// goes (for a chain of jumps, tap each landing square in turn). Captures are compulsory.
struct CheckersView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var path: [Int] = []
    @State private var confirmNew = false

    private var bondID: String? { model.selectedPartnerID }
    private var game: ChessGame? { together.space(bondID).checkers }
    private var iAmA: Bool { model.myRole(bondID) == "A" }

    var body: some View {
        let pos = CheckersPosition.from(moves: game?.moves ?? [])
        let myTurn = pos.aToMove == iAmA && pos.winner == nil && game?.resigned == nil
        let candidates = pos.legalMoves().filter { $0.starts(with: path) && $0.count > path.count }
        let targets = Set(path.isEmpty ? candidates.map { $0[0] } : candidates.map { $0[path.count] })
        VStack(spacing: 14) {
            Text(status(pos, myTurn: myTurn)).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                .padding(.horizontal, 16).padding(.vertical, 8).glass(Capsule())
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height), cell = side / 8
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let sq = iAmA ? (7 - row) * 8 + col : row * 8 + (7 - col)
                                cellView(sq, pos: pos, cell: cell, target: myTurn && targets.contains(sq))
                                    .onTapGesture { tap(sq, pos: pos, myTurn: myTurn, candidates: candidates) }
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 12) {
                Button("New game") { confirmNew = true }.buttonStyle(GlassButtonStyle(height: 46))
                Button("Undo selection") { path = [] }.buttonStyle(GlassButtonStyle(height: 46)).disabled(path.isEmpty)
            }
            Text("You play \(iAmA ? "red, moving up" : "black, moving up") · captures are compulsory")
                .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            Spacer(minLength: 0)
        }
        .padding(16)
        .navigationTitle("Checkers").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start a new game of checkers?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New game") { together.edit(bondID, note: "started a new game of checkers 🔴") { $0.checkers = ChessGame() }; path = [] }
        }
    }

    private func cellView(_ sq: Int, pos: CheckersPosition, cell: CGFloat, target: Bool) -> some View {
        let dark = (sq / 8 + sq % 8) % 2 == 1
        let v = pos.board[sq]
        return ZStack {
            Rectangle().fill(dark ? Color(rgbInt: 0x5B3A29) : Color(rgbInt: 0xE8D2B0))
            if path.contains(sq) { Rectangle().fill(Theme.accent.opacity(0.45)) }
            if v != 0 {
                Circle()
                    .fill(RadialGradient(colors: v > 0 ? [Color(rgbInt: 0xFF6B6B), Color(rgbInt: 0xB0182A)] : [Color(rgbInt: 0x555555), Color(rgbInt: 0x111111)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: cell * 0.5))
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5).padding(cell * 0.12))
                    .padding(cell * 0.1)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                if abs(v) == 2 { Image(systemName: "crown.fill").font(.system(size: cell * 0.32)).foregroundStyle(.yellow) }
            }
            if target { Circle().fill(Color.white.opacity(0.5)).frame(width: cell * 0.28, height: cell * 0.28) }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
    }

    private func tap(_ sq: Int, pos: CheckersPosition, myTurn: Bool, candidates: [[Int]]) {
        guard myTurn else { return }
        if path.isEmpty || !candidates.contains(where: { $0[path.count] == sq }) {
            // (Re)start from a piece that can move.
            path = pos.legalMoves().contains(where: { $0.first == sq }) ? [sq] : []
            if !path.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
            return
        }
        path.append(sq)
        if let done = pos.legalMoves().first(where: { $0 == path }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            var after = pos
            after.apply(done)
            let note = after.winner != nil ? "won at checkers 🏆" : "made a checkers move 🔴 — your turn"
            together.edit(bondID, note: note) { s in
                if s.checkers == nil { s.checkers = ChessGame() }
                s.checkers?.moves.append(done.map(String.init).joined(separator: "-"))
                s.checkers?.edited = Date()
            }
            path = []
        }
    }

    private func status(_ p: CheckersPosition, myTurn: Bool) -> String {
        if let w = p.winner { return w == model.myRole(bondID) ? "You win!" : "\(model.selectedPartner?.displayName ?? "They") won" }
        if game == nil { return "Make the first move" }
        return myTurn ? "Your move" : "Waiting for \(model.selectedPartner?.displayName ?? "them")…"
    }
}
