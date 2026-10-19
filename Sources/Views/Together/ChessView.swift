import SwiftUI

/// Chess with your partner, one move at a time through iCloud. Whoever created the bond plays
/// white. Tap a piece, then where it goes; legal squares light up. Promotions become a queen.
struct ChessView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var selected: Int?
    @State private var confirmNew = false
    @State private var confirmResign = false

    private var bondID: String? { model.selectedPartnerID }
    private var game: ChessGame? { together.space(bondID).chess }
    private var iAmWhite: Bool { model.myRole(bondID) == "A" }

    var body: some View {
        let position = ChessPosition.from(moves: game?.moves ?? [])
        let myTurn = position.whiteToMove == iAmWhite && game?.resigned == nil
        let targets = selected.map { Set(position.legalMoves(from: $0).map(\.to)) } ?? []
        VStack(spacing: 14) {
            Text(statusText(position)).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                .padding(.horizontal, 16).padding(.vertical, 8).glass(Capsule())

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 8
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let sq = square(row: row, col: col)
                                square(sq, position: position, cell: cell, target: targets.contains(sq))
                                    .onTapGesture { tap(sq, position: position, myTurn: myTurn) }
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
                Button("Resign") { confirmResign = true }.buttonStyle(GlassButtonStyle(height: 46))
                    .disabled(game == nil || game?.resigned != nil || position.status == .checkmate)
            }
            Text("You play \(iAmWhite ? "white" : "black") · \(game?.moves.count ?? 0) moves")
                .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            Spacer(minLength: 0)
        }
        .padding(16)
        .navigationTitle("Chess")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start a new game? The current one ends for both of you.", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New game") { together.edit(bondID, note: "started a new chess game ♟️") { $0.chess = ChessGame() }; selected = nil }
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) {
                let me = model.myRole(bondID)
                together.edit(bondID, note: "resigned the chess game 🏳️") { s in s.chess?.resigned = me; s.chess?.edited = Date() }
            }
        }
    }

    /// Board squares from this player's side: white at the bottom for white, black for black.
    private func square(row: Int, col: Int) -> Int {
        iAmWhite ? (7 - row) * 8 + col : row * 8 + (7 - col)
    }

    private func square(_ sq: Int, position: ChessPosition, cell: CGFloat, target: Bool) -> some View {
        let light = (sq / 8 + sq % 8) % 2 == 1
        let last = position.lastMove.map { $0.from == sq || $0.to == sq } ?? false
        let kingInCheck = position.board[sq]?.kind == "k" && position.board[sq]?.white == position.whiteToMove
            && position.inCheck(white: position.whiteToMove)
        return ZStack {
            Rectangle().fill(light ? Color(rgbInt: 0xF0D9B5) : Color(rgbInt: 0xB58863))
            if last { Rectangle().fill(Color.yellow.opacity(0.35)) }
            if selected == sq { Rectangle().fill(Theme.accent.opacity(0.55)) }
            if kingInCheck { Rectangle().fill(Color.red.opacity(0.45)) }
            if let piece = position.board[sq] {
                Text(piece.symbol).font(.system(size: cell * 0.78))
                    .foregroundStyle(piece.white ? Color.white : Color.black)
                    .shadow(color: piece.white ? .black.opacity(0.8) : .white.opacity(0.4), radius: 0.8)
            }
            if target {
                Circle().fill(Color.black.opacity(position.board[sq] == nil ? 0.25 : 0))
                    .frame(width: cell * 0.3, height: cell * 0.3)
                if position.board[sq] != nil { Circle().stroke(Color.black.opacity(0.35), lineWidth: 4).padding(3) }
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
    }

    private func tap(_ sq: Int, position: ChessPosition, myTurn: Bool) {
        guard myTurn, position.status != .checkmate, position.status != .stalemate else { return }
        if let from = selected, let move = position.legalMoves(from: from).first(where: { $0.to == sq && ($0.promo == nil || $0.promo == "q") }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            var after = position
            after.apply(move)
            let note = after.status == .checkmate ? "checkmated you ♟️" : after.status == .check ? "put you in check ♟️ — your move" : "made a chess move ♟️ — your turn"
            together.edit(bondID, note: note) { s in
                if s.chess == nil { s.chess = ChessGame() }
                s.chess?.moves.append(move.uci)
                s.chess?.edited = Date()
            }
            selected = nil
        } else if let piece = position.board[sq], piece.white == position.whiteToMove {
            UISelectionFeedbackGenerator().selectionChanged()
            selected = sq
        } else {
            selected = nil
        }
    }

    private func statusText(_ p: ChessPosition) -> String {
        guard let game else { return "Make the first move" }
        if let r = game.resigned { return r == model.myRole(bondID) ? "You resigned" : "\(model.selectedPartner?.displayName ?? "They") resigned — you win!" }
        let mine = p.whiteToMove == iAmWhite
        switch p.status {
        case .checkmate: return mine ? "Checkmate — they win" : "Checkmate — you win!"
        case .stalemate: return "Stalemate — a draw"
        case .check: return mine ? "Check! Your move" : "Check — their move"
        case .playing: return mine ? "Your move" : "Waiting for \(model.selectedPartner?.displayName ?? "them")…"
        }
    }
}
