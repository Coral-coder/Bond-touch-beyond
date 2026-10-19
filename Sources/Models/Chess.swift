import Foundation

/// A small, complete chess rules engine: legal moves (castling, en passant, promotion),
/// check, checkmate and stalemate. Positions are rebuilt from the move list, which is all
/// the two phones exchange.
struct ChessPosition {
    struct Piece: Equatable {
        var white: Bool
        /// p n b r q k
        var kind: Character
        var symbol: String {
            switch kind {
            case "k": return white ? "♔" : "♚"
            case "q": return white ? "♕" : "♛"
            case "r": return white ? "♖" : "♜"
            case "b": return white ? "♗" : "♝"
            case "n": return white ? "♘" : "♞"
            default: return white ? "♙" : "♟"
            }
        }
    }

    struct Move: Equatable, Hashable {
        var from: Int
        var to: Int
        var promo: Character?
        var uci: String { Self.name(from) + Self.name(to) + (promo.map(String.init) ?? "") }
        static func name(_ sq: Int) -> String {
            String(Character(UnicodeScalar(UInt8(97 + sq % 8)))) + String(sq / 8 + 1)
        }
        init(from: Int, to: Int, promo: Character? = nil) { self.from = from; self.to = to; self.promo = promo }
        init?(uci: String) {
            let c = Array(uci)
            guard c.count >= 4, let f = Self.square(c[0], c[1]), let t = Self.square(c[2], c[3]) else { return nil }
            from = f; to = t; promo = c.count > 4 ? c[4] : nil
        }
        private static func square(_ file: Character, _ rank: Character) -> Int? {
            guard let f = file.asciiValue, let r = rank.wholeNumberValue, (97...104).contains(f), (1...8).contains(r) else { return nil }
            return (r - 1) * 8 + Int(f - 97)
        }
    }

    enum Status: Equatable { case playing, check, checkmate, stalemate }

    var board: [Piece?] = Array(repeating: nil, count: 64)
    var whiteToMove = true
    var castling: Set<Character> = ["K", "Q", "k", "q"]
    var enPassant: Int?
    var lastMove: Move?

    static func start() -> ChessPosition {
        var p = ChessPosition()
        let back: [Character] = ["r", "n", "b", "q", "k", "b", "n", "r"]
        for f in 0..<8 {
            p.board[f] = Piece(white: true, kind: back[f])
            p.board[8 + f] = Piece(white: true, kind: "p")
            p.board[48 + f] = Piece(white: false, kind: "p")
            p.board[56 + f] = Piece(white: false, kind: back[f])
        }
        return p
    }

    /// The position after `moves` (stops at the first move that isn't legal).
    static func from(moves: [String]) -> ChessPosition {
        var p = start()
        for uci in moves {
            guard let m = Move(uci: uci), let legal = p.legalMoves().first(where: { $0.from == m.from && $0.to == m.to && ($0.promo == nil || $0.promo == (m.promo ?? "q")) })
            else { break }
            p.apply(legal)
        }
        return p
    }

    var status: Status {
        let check = inCheck(white: whiteToMove)
        if legalMoves().isEmpty { return check ? .checkmate : .stalemate }
        return check ? .check : .playing
    }

    // MARK: Moves

    func legalMoves() -> [Move] {
        pseudoMoves().filter { m in
            var next = self
            next.apply(m)
            return !next.inCheck(white: whiteToMove)
        }
    }

    func legalMoves(from sq: Int) -> [Move] { legalMoves().filter { $0.from == sq } }

    private static func file(_ sq: Int) -> Int { sq % 8 }
    private static func rank(_ sq: Int) -> Int { sq / 8 }
    private static func at(_ f: Int, _ r: Int) -> Int? { (0..<8).contains(f) && (0..<8).contains(r) ? r * 8 + f : nil }

    private static let knight = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let king = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    private func pseudoMoves() -> [Move] {
        var out: [Move] = []
        for sq in 0..<64 {
            guard let piece = board[sq], piece.white == whiteToMove else { continue }
            let f = Self.file(sq), r = Self.rank(sq)
            switch piece.kind {
            case "p":
                let dir = piece.white ? 1 : -1, last = piece.white ? 7 : 0, startRank = piece.white ? 1 : 6
                func add(_ to: Int) {
                    if Self.rank(to) == last { for k: Character in ["q", "r", "b", "n"] { out.append(Move(from: sq, to: to, promo: k)) } }
                    else { out.append(Move(from: sq, to: to)) }
                }
                if let one = Self.at(f, r + dir), board[one] == nil {
                    add(one)
                    if r == startRank, let two = Self.at(f, r + 2 * dir), board[two] == nil { out.append(Move(from: sq, to: two)) }
                }
                for df in [-1, 1] {
                    guard let to = Self.at(f + df, r + dir) else { continue }
                    if let target = board[to], target.white != piece.white { add(to) }
                    else if to == enPassant { out.append(Move(from: sq, to: to)) }
                }
            case "n":
                for (df, dr) in Self.knight { if let to = Self.at(f + df, r + dr), board[to]?.white != piece.white { out.append(Move(from: sq, to: to)) } }
            case "k":
                for (df, dr) in Self.king { if let to = Self.at(f + df, r + dr), board[to]?.white != piece.white { out.append(Move(from: sq, to: to)) } }
                out += castlingMoves(white: piece.white)
            default:
                let dirs = piece.kind == "r" ? Self.straight : piece.kind == "b" ? Self.diagonal : Self.straight + Self.diagonal
                for (df, dr) in dirs {
                    var x = f + df, y = r + dr
                    while let to = Self.at(x, y) {
                        if let t = board[to] { if t.white != piece.white { out.append(Move(from: sq, to: to)) }; break }
                        out.append(Move(from: sq, to: to))
                        x += df; y += dr
                    }
                }
            }
        }
        return out
    }

    private func castlingMoves(white: Bool) -> [Move] {
        let base = white ? 0 : 56, kingSq = base + 4
        guard board[kingSq] == Piece(white: white, kind: "k"), !inCheck(white: white) else { return [] }
        var out: [Move] = []
        if castling.contains(white ? "K" : "k"), board[base + 7] == Piece(white: white, kind: "r"),
           board[base + 5] == nil, board[base + 6] == nil,
           !attacked(base + 5, byWhite: !white), !attacked(base + 6, byWhite: !white) {
            out.append(Move(from: kingSq, to: base + 6))
        }
        if castling.contains(white ? "Q" : "q"), board[base] == Piece(white: white, kind: "r"),
           board[base + 1] == nil, board[base + 2] == nil, board[base + 3] == nil,
           !attacked(base + 3, byWhite: !white), !attacked(base + 2, byWhite: !white) {
            out.append(Move(from: kingSq, to: base + 2))
        }
        return out
    }

    mutating func apply(_ m: Move) {
        guard var piece = board[m.from] else { return }
        let captured = board[m.to]
        // En passant: the pawn taken is beside, not on, the square moved to.
        if piece.kind == "p", m.to == enPassant, captured == nil {
            board[m.to + (piece.white ? -8 : 8)] = nil
        }
        // Castling: bring the rook over.
        if piece.kind == "k", abs(m.to - m.from) == 2 {
            let base = piece.white ? 0 : 56
            if m.to == base + 6 { board[base + 5] = board[base + 7]; board[base + 7] = nil }
            else { board[base + 3] = board[base]; board[base] = nil }
        }
        if piece.kind == "p", let promo = m.promo { piece.kind = promo }
        else if piece.kind == "p", Self.rank(m.to) == (piece.white ? 7 : 0) { piece.kind = "q" }
        board[m.to] = piece
        board[m.from] = nil
        enPassant = piece.kind == "p" && abs(m.to - m.from) == 16 ? (m.from + m.to) / 2 : nil
        // Castling rights go when the king or a rook moves, or a rook is taken at home.
        if board[m.to]?.kind == "k" { castling.subtract(piece.white ? ["K", "Q"] : ["k", "q"]) }
        for (sq, right) in [(0, Character("Q")), (7, "K"), (56, "q"), (63, "k")] where m.from == sq || m.to == sq {
            castling.remove(right)
        }
        _ = captured
        whiteToMove.toggle()
        lastMove = m
    }

    // MARK: Attack

    func inCheck(white: Bool) -> Bool {
        guard let k = board.firstIndex(where: { $0 == Piece(white: white, kind: "k") }) else { return false }
        return attacked(k, byWhite: !white)
    }

    func attacked(_ sq: Int, byWhite: Bool) -> Bool {
        let f = Self.file(sq), r = Self.rank(sq)
        let pawnRank = byWhite ? r - 1 : r + 1
        for df in [-1, 1] { if let s = Self.at(f + df, pawnRank), board[s] == Piece(white: byWhite, kind: "p") { return true } }
        for (df, dr) in Self.knight { if let s = Self.at(f + df, r + dr), board[s] == Piece(white: byWhite, kind: "n") { return true } }
        for (df, dr) in Self.king { if let s = Self.at(f + df, r + dr), board[s] == Piece(white: byWhite, kind: "k") { return true } }
        for (dirs, kinds) in [(Self.straight, ["r", "q"] as [Character]), (Self.diagonal, ["b", "q"] as [Character])] {
            for (df, dr) in dirs {
                var x = f + df, y = r + dr
                while let s = Self.at(x, y) {
                    if let p = board[s] { if p.white == byWhite && kinds.contains(p.kind) { return true }; break }
                    x += df; y += dr
                }
            }
        }
        return false
    }
}
