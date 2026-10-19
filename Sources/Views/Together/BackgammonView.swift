import SwiftUI

/// Backgammon with your partner through iCloud. Roll, then tap a checker (or the bar) and a
/// highlighted point to move it; "Off" bears off once everything's home. Your turn ends by
/// itself when there's nothing left to play.
struct BackgammonView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var selected: Int?
    @State private var confirmNew = false

    private var bondID: String? { model.selectedPartnerID }
    private var game: ChessGame? { together.space(bondID).backgammon }
    private var iAmA: Bool { model.myRole(bondID) == "A" }

    var body: some View {
        let pos = BackgammonPosition.from(moves: game?.moves ?? [])
        let myTurn = pos.aToMove == iAmA && pos.winner == nil
        let moves = myTurn ? pos.legalMoves() : []
        let targets = Set(moves.filter { $0.from == selected }.map(\.to))
        VStack(spacing: 12) {
            Text(status(pos, myTurn: myTurn)).font(Theme.font(17, .heavy)).foregroundStyle(Theme.title)
                .padding(.horizontal, 16).padding(.vertical, 8).glass(Capsule())

            GeometryReader { geo in
                board(pos, size: geo.size, targets: targets, sources: Set(moves.map(\.from)))
            }
            .aspectRatio(1.25, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            HStack(spacing: 12) {
                ForEach(Array(pos.dice.enumerated()), id: \.offset) { _, d in die(d) }
                if myTurn && !pos.rolled {
                    Button("Roll the dice") { roll() }.buttonStyle(AccentButtonStyle(height: 46))
                }
                if targets.contains(pos.offPoint) {
                    Button("Bear off") { move(to: pos.offPoint, pos: pos) }.buttonStyle(AccentButtonStyle(height: 46))
                }
            }
            .frame(minHeight: 46)
            HStack {
                Text("Off: you \(iAmA ? pos.offA : pos.offB) · them \(iAmA ? pos.offB : pos.offA)")
                Spacer()
                Button("New game") { confirmNew = true }.font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
            }
            .font(Theme.font(12)).foregroundStyle(Theme.subtitle)
            Spacer(minLength: 0)
        }
        .padding(16).padding(.bottom, TabBarSpace.fixed)
        .navigationTitle("Backgammon").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start a new game of backgammon?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New game") { together.edit(bondID, note: "started a new game of backgammon 🎲") { $0.backgammon = ChessGame() }; selected = nil }
        }
    }

    // MARK: Board

    /// Points laid out from this player's side: their home board bottom-right.
    private func board(_ pos: BackgammonPosition, size: CGSize, targets: Set<Int>, sources: Set<Int>) -> some View {
        let w = size.width, h = size.height
        let barW = w * 0.08, pointW = (w - barW) / 12
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(rgbInt: 0x2F6B45))
            Rectangle().fill(Color(rgbInt: 0x5B3A29)).frame(width: barW, height: h).offset(x: pointW * 6)
            ForEach(1...24, id: \.self) { point in
                let slot = slotOf(point)
                let top = slot.top
                let x = CGFloat(slot.col) * pointW + (slot.col >= 6 ? barW : 0)
                Triangle(up: !top)
                    .fill(point % 2 == 0 ? Color(rgbInt: 0xE8D2B0) : Color(rgbInt: 0xB0182A))
                    .overlay(Triangle(up: !top).stroke(targets.contains(point) ? Color.yellow : .clear, lineWidth: 3))
                    .frame(width: pointW, height: h * 0.42)
                    .offset(x: x, y: top ? 0 : h * 0.58)
                checkers(pos.points[point], x: x, top: top, pointW: pointW, h: h, selected: selected == point)
                Color.clear.contentShape(Rectangle())
                    .frame(width: pointW, height: h * 0.5)
                    .offset(x: x, y: top ? 0 : h * 0.5)
                    .onTapGesture { tapPoint(point, pos: pos, sources: sources, targets: targets) }
            }
            // The bar, with any checkers on it; tap it to enter from the bar.
            VStack(spacing: 4) {
                ForEach(0..<pos.barB, id: \.self) { _ in piece(false, size: pointW * 0.8) }
                Spacer()
                ForEach(0..<pos.barA, id: \.self) { _ in piece(true, size: pointW * 0.8) }
            }
            .frame(width: barW, height: h).offset(x: pointW * 6)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected == pos.barPoint ? Color.yellow : .clear, lineWidth: 3)
                .frame(width: barW, height: h).offset(x: pointW * 6))
            .contentShape(Rectangle())
            .onTapGesture { if sources.contains(pos.barPoint) { selected = pos.barPoint } }
        }
    }

    /// Where a point sits: column 0…11 from the left, and top or bottom row, from this
    /// player's side (their 1–6 bottom-right, 7–12 bottom-left, 13–18 top-left, 19–24 top-right).
    private func slotOf(_ point: Int) -> (col: Int, top: Bool) {
        let p = iAmA ? point : 25 - point
        if p <= 12 { return (12 - p, false) }
        return (p - 13, true)
    }

    private func checkers(_ n: Int, x: CGFloat, top: Bool, pointW: CGFloat, h: CGFloat, selected: Bool) -> some View {
        let count = abs(n), d = pointW * 0.9
        return ZStack(alignment: .top) {
            ForEach(0..<min(count, 5), id: \.self) { i in
                piece(n > 0, size: d)
                    .overlay(Circle().stroke(selected && i == min(count, 5) - 1 ? Color.yellow : .clear, lineWidth: 3))
                    .offset(y: top ? CGFloat(i) * d * 0.92 : h - d - CGFloat(i) * d * 0.92)
            }
            if count > 5 {
                Text("\(count)").font(Theme.font(11, .heavy)).foregroundStyle(n > 0 ? .black : .white)
                    .offset(y: top ? 4 * d * 0.92 + d * 0.3 : h - d * 0.7 - 4 * d * 0.92)
            }
        }
        .frame(width: pointW, height: h, alignment: .top)
        .offset(x: x + (pointW - d) / 2 - (pointW - d) / 2)
        .allowsHitTesting(false)
    }

    private func piece(_ white: Bool, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: white ? [.white, Color(rgbInt: 0xD8D2C6)] : [Color(rgbInt: 0x555555), Color(rgbInt: 0x111111)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.6))
            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
            .frame(width: size, height: size)
    }

    private func die(_ n: Int) -> some View {
        Text(["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"][max(0, min(5, n - 1))]).font(.system(size: 40)).foregroundStyle(Theme.title)
    }

    // MARK: Play

    private func tapPoint(_ point: Int, pos: BackgammonPosition, sources: Set<Int>, targets: Set<Int>) {
        if let _ = selected, targets.contains(point) { move(to: point, pos: pos); return }
        selected = sources.contains(point) ? point : nil
        if selected != nil { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func roll() {
        let a = Int.random(in: 1...6), b = Int.random(in: 1...6)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        together.edit(bondID) { s in
            if s.backgammon == nil { s.backgammon = ChessGame() }
            s.backgammon?.moves.append("r:\(a),\(b)")
            // Nothing playable with this roll: the turn passes straight away.
            var p = BackgammonPosition.from(moves: s.backgammon?.moves ?? [])
            if p.legalMoves().isEmpty { s.backgammon?.moves.append("e"); p.endTurn() }
            s.backgammon?.edited = Date()
        }
    }

    private func move(to point: Int, pos: BackgammonPosition) {
        guard let from = selected,
              let m = pos.legalMoves().filter({ $0.from == from && $0.to == point }).max(by: { $0.die > $1.die }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var after = pos
        after.apply(m)
        let turnOver = after.winner != nil || after.legalMoves().isEmpty
        let note: String? = after.winner != nil ? "won at backgammon 🏆" : turnOver ? "played their backgammon turn 🎲 — your roll" : nil
        together.edit(bondID, note: note) { s in
            s.backgammon?.moves.append("m:\(m.from)-\(m.to)")
            if turnOver, after.winner == nil { s.backgammon?.moves.append("e") }
            s.backgammon?.edited = Date()
        }
        selected = nil
    }

    private func status(_ p: BackgammonPosition, myTurn: Bool) -> String {
        if let w = p.winner { return w == model.myRole(bondID) ? "You win!" : "\(model.selectedPartner?.displayName ?? "They") won" }
        if !myTurn { return "Waiting for \(model.selectedPartner?.displayName ?? "them")…" }
        return p.rolled ? "Move your checkers" : "Your roll"
    }
}

/// A backgammon point: a long triangle pointing up or down.
private struct Triangle: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        p.closeSubpath()
        return p
    }
}
