import Foundation

/// Backgammon. Player A (who created the bond) is white and moves from point 24 down to 1,
/// bearing off below 1; B is black and moves from 1 up to 24. Each turn is stored as moves
/// in the shared list: "r:3,5" (the roll), then "m:24-21" for each checker moved (from/to
/// in points; 25 = A's bar / B's off, 0 = A's off / B's bar), then "e" (end of turn).
struct BackgammonPosition {
    /// Checkers per point 1…24 (index 1…24): positive = A, negative = B. Index 0 and 25 unused.
    var points: [Int] = Array(repeating: 0, count: 26)
    var barA = 0, barB = 0
    var offA = 0, offB = 0
    var aToMove = true
    /// Dice still to use this turn (doubles give four).
    var dice: [Int] = []
    var rolled = false

    static func start() -> BackgammonPosition {
        var p = BackgammonPosition()
        p.points[24] = 2; p.points[13] = 5; p.points[8] = 3; p.points[6] = 5
        p.points[1] = -2; p.points[12] = -5; p.points[17] = -3; p.points[19] = -5
        return p
    }

    static func from(moves: [String]) -> BackgammonPosition {
        var p = start()
        for m in moves {
            if m.hasPrefix("r:") {
                let d = m.dropFirst(2).split(separator: ",").compactMap { Int($0) }
                guard d.count == 2, !p.rolled else { break }
                p.dice = d[0] == d[1] ? Array(repeating: d[0], count: 4) : d
                p.rolled = true
            } else if m.hasPrefix("m:") {
                let ft = m.dropFirst(2).split(separator: "-").compactMap { Int($0) }
                guard ft.count == 2, let move = p.legalMoves().first(where: { $0.from == ft[0] && $0.to == ft[1] }) else { break }
                p.apply(move)
            } else if m == "e" {
                p.endTurn()
            }
        }
        return p
    }

    struct Move: Equatable { var from: Int; var to: Int; var die: Int }

    private var sign: Int { aToMove ? 1 : -1 }
    var bar: Int { aToMove ? barA : barB }
    var off: Int { aToMove ? offA : offB }
    /// The "bar" point number for the side to move, and the "off" target.
    var barPoint: Int { aToMove ? 25 : 0 }
    var offPoint: Int { aToMove ? 0 : 25 }

    private func count(_ point: Int) -> Int { points[point] * sign }   // own checkers there (negative = theirs)

    private func allHome() -> Bool {
        guard bar == 0 else { return false }
        let outside = aToMove ? (7...24) : (1...18)
        return !outside.contains { count($0) > 0 }
    }

    /// Single-checker moves possible with any remaining die.
    func legalMoves() -> [Move] {
        guard rolled else { return [] }
        var out: [Move] = []
        for die in Set(dice) {
            if bar > 0 {
                let to = aToMove ? 25 - die : die
                if count(to) >= -1 { out.append(Move(from: barPoint, to: to, die: die)) }
                continue
            }
            for from in 1...24 where count(from) > 0 {
                let to = aToMove ? from - die : from + die
                if (1...24).contains(to) {
                    if count(to) >= -1 { out.append(Move(from: from, to: to, die: die)) }
                } else if allHome() {
                    // Bear off: an exact die, or a higher one from the farthest checker.
                    let distance = aToMove ? from : 25 - from
                    let farther = aToMove ? ((from + 1)...24).contains { count($0) > 0 }
                                          : (1..<from).contains { count($0) > 0 }
                    if distance == die || (die > distance && !farther) {
                        out.append(Move(from: from, to: offPoint, die: die))
                    }
                }
            }
        }
        return out
    }

    mutating func apply(_ m: Move) {
        if m.from == barPoint { if aToMove { barA -= 1 } else { barB -= 1 } }
        else { points[m.from] -= sign }
        if m.to == offPoint {
            if aToMove { offA += 1 } else { offB += 1 }
        } else {
            if count(m.to) == -1 {   // hit a lone opposing checker
                points[m.to] = 0
                if aToMove { barB += 1 } else { barA += 1 }
            }
            points[m.to] += sign
        }
        if let i = dice.firstIndex(of: m.die) { dice.remove(at: i) }
    }

    mutating func endTurn() {
        dice = []
        rolled = false
        aToMove.toggle()
    }

    var winner: String? { offA == 15 ? "A" : offB == 15 ? "B" : nil }
}
