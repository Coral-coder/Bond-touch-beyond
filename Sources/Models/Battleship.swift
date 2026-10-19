import Foundation

/// Battleship. Each of you places a fleet (5, 4, 3, 3, 2) on a 10×10 grid that stays on
/// your own phone — only a fingerprint of it is shared, so neither of you can peek. Shots are
/// answered by the defender's phone (hit, miss or sunk) as soon as it sees them. A shoots first.
///
/// Events (both phones add to the same list, so it merges as a union):
///   "ready:A:<fingerprint>"  fleet placed
///   "shot:A:<cell>"          A fires at B's cell 0…99
///   "res:A:<cell>:h|m|s<n>"  B's phone answers A's shot (s<n> = sunk a ship of length n)
///   "fleet:A:<cells>"        A's fleet, revealed when the game ends
struct BattleshipGame: Codable, Equatable {
    var id = UUID()
    var started = Date()
    /// "<seconds since 1970 with ms>|<event>", kept sorted by time.
    var events: [String] = []

    static let fleet = [5, 4, 3, 3, 2]
    static let totalCells = fleet.reduce(0, +)

    static func merge(_ a: BattleshipGame?, _ b: BattleshipGame?) -> BattleshipGame? {
        guard let a else { return b }
        guard let b else { return a }
        if a.id != b.id { return a.started >= b.started ? a : b }
        var g = a
        g.events = Array(Set(a.events + b.events)).sorted()
        return g
    }

    mutating func add(_ event: String) {
        events.append(String(format: "%014.3f", Date().timeIntervalSince1970) + "|" + event)
        events.sort()
    }

    var plain: [String] { events.compactMap { $0.split(separator: "|", maxSplits: 1).last.map(String.init) } }

    func ready(_ side: String) -> Bool { plain.contains { $0.hasPrefix("ready:\(side):") } }
    func shots(by side: String) -> [Int] { plain.compactMap { e in e.hasPrefix("shot:\(side):") ? Int(e.split(separator: ":")[2]) : nil } }
    /// Answers to `side`'s shots: cell → "h", "m" or "s<n>".
    func results(for side: String) -> [Int: String] {
        var out: [Int: String] = [:]
        for e in plain where e.hasPrefix("res:\(side):") {
            let p = e.split(separator: ":")
            if p.count == 4, let c = Int(p[2]) { out[c] = String(p[3]) }
        }
        return out
    }
    func hits(by side: String) -> Int { results(for: side).values.filter { $0 != "m" }.count }

    var winner: String? {
        if hits(by: "A") >= Self.totalCells { return "A" }
        if hits(by: "B") >= Self.totalCells { return "B" }
        return nil
    }

    /// Whose turn: A first; a side shoots once its previous shot is answered and the other has had theirs.
    var turn: String? {
        guard ready("A"), ready("B"), winner == nil else { return nil }
        let a = shots(by: "A").count, b = shots(by: "B").count
        let side = a <= b ? "A" : "B"
        // Wait for the last shot to be answered before the next one.
        let other = side == "A" ? "B" : "A"
        if let last = shots(by: other).last, results(for: other)[last] == nil { return nil }
        return side
    }

    /// Shots at `side`'s fleet that haven't been answered yet.
    func unanswered(against side: String) -> [Int] {
        let other = side == "A" ? "B" : "A"
        let answered = results(for: other)
        return shots(by: other).filter { answered[$0] == nil }
    }

    // MARK: Fleets (kept on this phone)

    /// Ships as lists of cells.
    typealias Fleet = [[Int]]

    static func randomFleet() -> Fleet {
        var taken = Set<Int>()
        var ships: Fleet = []
        for len in fleet {
            while true {
                let horizontal = Bool.random()
                let r = Int.random(in: 0..<(horizontal ? 10 : 11 - len)), c = Int.random(in: 0..<(horizontal ? 11 - len : 10))
                let cells = (0..<len).map { horizontal ? r * 10 + c + $0 : (r + $0) * 10 + c }
                // Ships don't touch, not even at the corners.
                let around = Set(cells.flatMap { cell in
                    (-1...1).flatMap { dr in (-1...1).compactMap { dc -> Int? in
                        let rr = cell / 10 + dr, cc = cell % 10 + dc
                        return (0..<10).contains(rr) && (0..<10).contains(cc) ? rr * 10 + cc : nil
                    } }
                })
                if around.isDisjoint(with: taken) { taken.formUnion(cells); ships.append(cells); break }
            }
        }
        return ships
    }

    static func fingerprint(_ f: Fleet, salt: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in (f.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";") + salt).utf8 {
            h = (h ^ UInt64(b)) &* 1099511628211
        }
        return String(h, radix: 36)
    }

    static func answer(_ cell: Int, fleet: Fleet, alreadyHit: Set<Int>) -> String {
        guard let ship = fleet.first(where: { $0.contains(cell) }) else { return "m" }
        return ship.allSatisfy { $0 == cell || alreadyHit.contains($0) } ? "s\(ship.count)" : "h"
    }

    static func localKey(_ gameID: UUID) -> String { "battleship.fleet.\(gameID.uuidString)" }

    static func loadFleet(_ gameID: UUID) -> Fleet? {
        guard let data = UserDefaults.standard.data(forKey: localKey(gameID)) else { return nil }
        return try? JSONDecoder().decode(Fleet.self, from: data)
    }

    static func saveFleet(_ f: Fleet, gameID: UUID) {
        if let data = try? JSONEncoder().encode(f) { UserDefaults.standard.set(data, forKey: localKey(gameID)) }
    }
}
