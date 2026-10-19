import Foundation

/// Checkers (English draughts): 8×8, men move diagonally forward, captures are compulsory
/// and chain, a man reaching the far row becomes a king (and the move ends). Player A (who
/// created the bond) is red at the bottom and moves first. Moves are stored as the squares
/// visited, e.g. "9-18" or "22-13-4".
struct CheckersPosition {
    /// 0 empty; 1 A man, 2 A king; -1 B man, -2 B king. Index = row * 8 + col, row 0 at A's side.
    var board: [Int] = Array(repeating: 0, count: 64)
    var aToMove = true

    static func start() -> CheckersPosition {
        var p = CheckersPosition()
        for sq in 0..<64 where (sq / 8 + sq % 8) % 2 == 1 {
            if sq / 8 < 3 { p.board[sq] = 1 } else if sq / 8 > 4 { p.board[sq] = -1 }
        }
        return p
    }

    static func from(moves: [String]) -> CheckersPosition {
        var p = start()
        for m in moves {
            let path = m.split(separator: "-").compactMap { Int($0) }
            guard p.legalMoves().contains(path) else { break }
            p.apply(path)
        }
        return p
    }

    private func mine(_ v: Int) -> Bool { aToMove ? v > 0 : v < 0 }
    private func theirs(_ v: Int) -> Bool { aToMove ? v < 0 : v > 0 }
    private static func at(_ r: Int, _ c: Int) -> Int? { (0..<8).contains(r) && (0..<8).contains(c) ? r * 8 + c : nil }

    private func directions(_ piece: Int) -> [(Int, Int)] {
        if abs(piece) == 2 { return [(1, 1), (1, -1), (-1, 1), (-1, -1)] }
        return piece > 0 ? [(1, 1), (1, -1)] : [(-1, 1), (-1, -1)]
    }

    /// Every legal move as the list of squares visited. Captures, when any exist, are the only moves.
    func legalMoves() -> [[Int]] {
        var captures: [[Int]] = []
        var steps: [[Int]] = []
        for sq in 0..<64 where mine(board[sq]) {
            captures += jumps(from: sq, piece: board[sq], board: board)
            let r = sq / 8, c = sq % 8
            for (dr, dc) in directions(board[sq]) {
                if let to = Self.at(r + dr, c + dc), board[to] == 0 { steps.append([sq, to]) }
            }
        }
        return captures.isEmpty ? steps : captures
    }

    private func jumps(from sq: Int, piece: Int, board: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        let r = sq / 8, c = sq % 8
        for (dr, dc) in directions(piece) {
            guard let over = Self.at(r + dr, c + dc), let to = Self.at(r + 2 * dr, c + 2 * dc),
                  theirs(board[over]), board[to] == 0 else { continue }
            var b = board
            b[to] = piece; b[sq] = 0; b[over] = 0
            // Reaching the far row crowns the man and ends the move.
            let crowned = abs(piece) == 1 && (to / 8 == (piece > 0 ? 7 : 0))
            let more = crowned ? [] : jumps(from: to, piece: piece, board: b)
            if more.isEmpty { out.append([sq, to]) } else { out += more.map { [sq] + $0 } }
        }
        return out
    }

    mutating func apply(_ path: [Int]) {
        guard path.count >= 2 else { return }
        var piece = board[path[0]]
        board[path[0]] = 0
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            if abs(a / 8 - b / 8) == 2 { board[(a + b) / 2] = 0 }
        }
        let end = path[path.count - 1]
        if abs(piece) == 1, end / 8 == (piece > 0 ? 7 : 0) { piece *= 2 }
        board[end] = piece
        aToMove.toggle()
    }

    /// "A" or "B" when that side has won (the other has no pieces or no moves), else nil.
    var winner: String? {
        legalMoves().isEmpty ? (aToMove ? "B" : "A") : nil
    }
}
