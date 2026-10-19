import CoreGraphics
import Foundation

/// 8-ball pool. The table is 2 × 1 units; balls 0 (cue) to 15. Each shot is simulated on
/// the shooter's phone and stored with where every ball ended up, so both phones always
/// agree; the partner's phone replays the shot from its start to show it.
enum Pool {
    static let width = 2.0, height = 1.0
    static let radius = 0.026
    static let pocketRadius = 0.058
    static let pockets: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: -0.012), CGPoint(x: 2, y: 0),
                                     CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1.012), CGPoint(x: 2, y: 1)]
    static let maxSpeed = 4.2

    /// Balls on the table (nil = potted), index = ball number.
    typealias Rack = [CGPoint?]

    static func rack() -> Rack {
        var balls: Rack = Array(repeating: nil, count: 16)
        balls[0] = CGPoint(x: 0.5, y: 0.5)
        // A triangle with the 8 in the middle, a solid and a stripe in the back corners.
        let order = [1, 9, 2, 10, 8, 3, 11, 7, 14, 4, 5, 13, 15, 6, 12]
        var k = 0
        let d = radius * 2.02
        for row in 0..<5 {
            for i in 0...row {
                let x = 1.45 + Double(row) * d * 0.866
                let y = 0.5 + (Double(i) - Double(row) / 2) * d
                balls[order[k]] = CGPoint(x: x, y: y)
                k += 1
            }
        }
        return balls
    }

    struct Shot: Codable, Equatable {
        var by: String          // "A" or "B"
        var angle: Double
        var power: Double       // 0…1
        var start: [[Double]?]  // positions before the shot
        var end: [[Double]?]    // positions after
        var potted: [Int]
        var firstHit: Int?
        var scratch: Bool
    }

    static func encode(_ r: Rack) -> [[Double]?] { r.map { $0.map { [($0.x * 10000).rounded() / 10000, ($0.y * 10000).rounded() / 10000] } } }
    static func decode(_ r: [[Double]?]) -> Rack { r.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } } }

    /// Runs a shot: returns frames (positions every 1/60 s) and what happened.
    static func simulate(_ start: Rack, angle: Double, power: Double) -> (frames: [Rack], potted: [Int], firstHit: Int?) {
        var pos: [CGPoint?] = start
        var vel = Array(repeating: CGVector.zero, count: 16)
        let speed = max(0.05, min(1, power)) * maxSpeed
        vel[0] = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        var frames: [Rack] = [pos]
        var potted: [Int] = []
        var firstHit: Int?
        let dt = 1.0 / 240.0, friction = 0.55, rail = 0.78
        var step = 0
        while step < 240 * 20 {
            step += 1
            for i in 0..<16 {
                guard let p = pos[i] else { continue }
                var v = vel[i]
                let s = hypot(v.dx, v.dy)
                if s > 0 {
                    let ns = max(0, s - friction * dt)
                    v = CGVector(dx: v.dx / s * ns, dy: v.dy / s * ns)
                }
                var np = CGPoint(x: p.x + v.dx * dt, y: p.y + v.dy * dt)
                // Pockets.
                if pockets.contains(where: { hypot($0.x - np.x, $0.y - np.y) < pocketRadius }) {
                    pos[i] = nil; vel[i] = .zero; potted.append(i); continue
                }
                // Cushions (with a gap at the pockets).
                if np.x < radius { np.x = radius; v.dx = -v.dx * rail }
                if np.x > width - radius { np.x = width - radius; v.dx = -v.dx * rail }
                if np.y < radius { np.y = radius; v.dy = -v.dy * rail }
                if np.y > height - radius { np.y = height - radius; v.dy = -v.dy * rail }
                pos[i] = np; vel[i] = v
            }
            // Ball-to-ball (equal masses, elastic, a little loss).
            for i in 0..<16 {
                guard let a = pos[i] else { continue }
                for j in (i + 1)..<16 {
                    guard let b = pos[j] else { continue }
                    let dx = b.x - a.x, dy = b.y - a.y
                    let dist = hypot(dx, dy)
                    guard dist < radius * 2, dist > 0 else { continue }
                    if firstHit == nil, i == 0 { firstHit = j }
                    let nx = dx / dist, ny = dy / dist
                    let rel = (vel[i].dx - vel[j].dx) * nx + (vel[i].dy - vel[j].dy) * ny
                    if rel > 0 {
                        let imp = rel * 0.97
                        vel[i].dx -= imp * nx; vel[i].dy -= imp * ny
                        vel[j].dx += imp * nx; vel[j].dy += imp * ny
                    }
                    let overlap = (radius * 2 - dist) / 2
                    pos[i] = CGPoint(x: a.x - nx * overlap, y: a.y - ny * overlap)
                    pos[j] = CGPoint(x: b.x + nx * overlap, y: b.y + ny * overlap)
                }
            }
            if step % 4 == 0 { frames.append(pos) }
            if vel.allSatisfy({ hypot($0.dx, $0.dy) < 0.01 }) { break }
        }
        frames.append(pos)
        return (frames, potted, firstHit)
    }

    /// The game so far, worked out from the shots.
    struct State {
        var balls: Rack = rack()
        var aToShoot = true
        /// Who has solids (1–7): "A", "B" or nil while the table is open.
        var solids: String?
        var winner: String?
        var lastShot: Shot?
        var ballInHand = false
    }

    static func state(_ shots: [Shot]) -> State {
        var s = State()
        for shot in shots {
            let shooter = shot.by
            s.lastShot = shot
            s.balls = decode(shot.end)
            let mineSolid: Bool? = s.solids.map { $0 == shooter }
            let pottedObj = shot.potted.filter { $0 != 0 && $0 != 8 }
            // The first ball potted after the break picks each side's group.
            if s.solids == nil, let first = pottedObj.first, !shot.scratch {
                s.solids = first < 8 ? shooter : (shooter == "A" ? "B" : "A")
            }
            let solidsMine = s.solids.map { $0 == shooter } ?? mineSolid ?? true
            let ownGroup: (Int) -> Bool = { solidsMine ? (1...7).contains($0) : (9...15).contains($0) }
            if shot.potted.contains(8) {
                let cleared = s.solids != nil && !(1...15).contains(where: { $0 != 8 && ownGroup($0) && s.balls[$0] != nil })
                s.winner = (cleared && !shot.scratch) ? shooter : (shooter == "A" ? "B" : "A")
                return s
            }
            let keepsTurn = !shot.scratch && pottedObj.contains(where: { s.solids == nil || ownGroup($0) })
            s.ballInHand = shot.scratch
            if shot.scratch || s.balls[0] == nil {
                s.balls[0] = freeSpot(s.balls, near: CGPoint(x: 0.5, y: 0.5))
            }
            if !keepsTurn { s.aToShoot = !(shooter == "A") }
            else { s.aToShoot = shooter == "A" }
        }
        return s
    }

    /// A clear spot for the cue ball near `p`.
    static func freeSpot(_ balls: Rack, near p: CGPoint) -> CGPoint {
        var c = p
        for _ in 0..<40 {
            if !balls.enumerated().contains(where: { $0.offset != 0 && $0.element.map { hypot($0.x - c.x, $0.y - c.y) < radius * 2.2 } ?? false }) {
                return c
            }
            c.y += radius * 2.3
            if c.y > height - radius { c.y = radius * 2; c.x += radius * 2.3 }
        }
        return c
    }
}
