import SwiftUI

/// The shared whiteboard: draw with your finger; your partner's strokes appear as they sync.
/// Undo takes back your own last stroke; Clear wipes the board for both of you.
struct WhiteboardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var together: TogetherStore
    @State private var current: [CGPoint] = []
    @State private var rgb = 0xEC5A89
    @State private var width = 4.0
    @State private var confirmClear = false
    /// Drew something this visit: one notification for the partner when you leave.
    @State private var drew = false

    private static let colors = [0xEC5A89, 0xB173DF, 0x57C3BB, 0x3D8BD9, 0x9FD257, 0xECA94B, 0xFF6B6B, 0x111111, 0xFFFFFF]

    var body: some View {
        let id = model.selectedPartnerID
        let board = together.board(id)
        VStack(spacing: 12) {
            GeometryReader { geo in
                let size = geo.size
                Canvas { ctx, _ in
                    for s in board.strokes { draw(&ctx, points: points(s, size), rgb: s.rgb, width: s.width) }
                    draw(&ctx, points: current, rgb: rgb, width: width)
                }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgbInt: 0xFDFCF8)))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.ink.opacity(0.2), lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = v.location
                        if let last = current.last, hypot(last.x - p.x, last.y - p.y) < 2 { return }
                        current.append(p)
                    }
                    .onEnded { _ in commit(size) })
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)

            HStack(spacing: 8) {
                ForEach(Self.colors, id: \.self) { c in
                    Circle().fill(Color(rgbInt: c)).frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: rgb == c ? 3 : 0).padding(-4))
                        .onTapGesture { rgb = c }
                        .accessibilityLabel("Colour")
                        .accessibilityAddTraits(rgb == c ? .isSelected : [])
                }
            }
            HStack(spacing: 14) {
                Image(systemName: "scribble").foregroundStyle(Theme.subtitle)
                Slider(value: $width, in: 1.5...16).tint(Theme.accent)
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2) }
                    .accessibilityLabel("Undo my last stroke")
                Button { confirmClear = true } label: { Image(systemName: "trash.circle.fill").font(.title2) }
                    .accessibilityLabel("Clear the board")
            }
            .foregroundStyle(Theme.accent)
        }
        .padding(16).padding(.bottom, TabBarSpace.fixed)
        .navigationTitle("Whiteboard")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if drew { Task { await model.notifyPartner(model.selectedPartnerID, "drew on the whiteboard 🎨 — come look") } }
            drew = false
        }
        .confirmationDialog("Clear the whiteboard for both of you?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { together.editBoard(id) { $0.clearedAt = Date(); $0.strokes = [] } }
        }
    }

    private func points(_ s: Whiteboard.Stroke, _ size: CGSize) -> [CGPoint] {
        stride(from: 0, to: s.points.count - 1, by: 2).map { CGPoint(x: s.points[$0] * size.width, y: s.points[$0 + 1] * size.height) }
    }

    private func draw(_ ctx: inout GraphicsContext, points: [CGPoint], rgb: Int, width: Double) {
        guard let first = points.first else { return }
        var path = Path()
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            ctx.fill(path, with: .color(Color(rgbInt: rgb)))
            return
        }
        path.move(to: first)
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        path.addLine(to: points[points.count - 1])
        ctx.stroke(path, with: .color(Color(rgbInt: rgb)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func commit(_ size: CGSize) {
        guard !current.isEmpty, size.width > 0, size.height > 0 else { return }
        let flat = current.flatMap { [(Double($0.x / size.width) * 1000).rounded() / 1000, (Double($0.y / size.height) * 1000).rounded() / 1000] }
        let stroke = Whiteboard.Stroke(rgb: rgb, width: width, points: flat, by: model.myRole(model.selectedPartnerID))
        current = []
        together.editBoard(model.selectedPartnerID) { $0.strokes.append(stroke) }
        drew = true
    }

    private func undo() {
        let me = model.myRole(model.selectedPartnerID)
        together.editBoard(model.selectedPartnerID) { b in
            guard let last = b.strokes.last(where: { $0.by == me }) else { return }
            b.removed.append(last.id)
            b.strokes.removeAll { $0.id == last.id }
        }
    }
}
