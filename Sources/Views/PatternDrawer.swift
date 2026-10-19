import SwiftUI

/// Draw a touch instead of performing it: time runs left to right, the bar's 9 positions go
/// up the side. Drag to draw a slide, tap for a short press; lift and start again further
/// right for a gap. The eraser clears where you drag. Feel it on your bracelet (or phone)
/// before saving. Used to make a new meaning and to edit a saved one's pattern.
struct PatternDrawer: View {
    /// The pattern to start from (any generation), or empty for a blank canvas.
    var initial: [Int] = []
    var initialGeneration = 3
    var colorRGB: Int = 0xEC5A89
    var endColorRGB: Int = 0xB173DF
    var title = "Draw a touch"
    /// Called with the drawn samples (generation 3).
    let onSave: ([Int]) -> Void

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var samples: [Int] = []
    @State private var seconds: Double = 3
    @State private var erasing = false
    @State private var lastIndex: Int?
    @State private var lastPos: Int?
    @State private var undoStack: [[Int]] = []

    private var count: Int { Int(seconds * 1000) / TouchPattern.sampleMs }
    private let top = TouchPattern.positions - 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Drag left → right to draw. Up and down is where the finger is on the bar. Lift for a pause.")
                    .font(Theme.font(13)).foregroundStyle(Theme.subtitle).multilineTextAlignment(.center)

                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        grid(size)
                        TouchViz(pattern: samples, generation: 3, colorRGB: colorRGB, endColorRGB: endColorRGB, height: size.height)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in draw(at: v.location, size: size, starting: lastIndex == nil) }
                        .onEnded { _ in lastIndex = nil; lastPos = nil })
                }
                .frame(height: 260)
                .glass(cornerRadius: 22)

                HStack(spacing: 12) {
                    Text("Length").font(Theme.font(14, .bold)).foregroundStyle(Theme.title)
                    Slider(value: Binding(get: { seconds }, set: { resize(to: $0) }), in: 1...10, step: 0.5).tint(Theme.accent)
                    Text(String(format: "%.1f s", seconds)).font(Theme.font(13, .bold)).monospacedDigit().foregroundStyle(Theme.subtitle)
                }

                HStack(spacing: 10) {
                    tool("pencil.tip", "Draw", !erasing) { erasing = false }
                    tool("eraser.fill", "Erase", erasing) { erasing = true }
                    tool("arrow.uturn.backward", "Undo", false) { if let last = undoStack.popLast() { samples = last } }
                        .disabled(undoStack.isEmpty)
                    tool("trash", "Clear", false) { pushUndo(); samples = Array(repeating: TouchPattern.none, count: count) }
                    tool("play.fill", "Feel it", false) { feel() }
                        .disabled(TouchPattern.trimmed(samples).isEmpty)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(TouchPattern.trimmed(samples)); dismiss() }
                        .disabled(TouchPattern.trimmed(samples).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    /// The bar's 9 position lines and a mark every second.
    private func grid(_ size: CGSize) -> some View {
        Canvas { ctx, s in
            for p in 0...top {
                let y = s.height - 8 - (s.height - 16) * CGFloat(p) / CGFloat(top)
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: s.width, y: y))
                ctx.stroke(line, with: .color(Theme.ink.opacity(p == 0 || p == top ? 0.18 : 0.08)), lineWidth: 1)
            }
            let secs = Int(seconds)
            if secs > 0 {
                for i in 1...secs {
                    let x = s.width * CGFloat(Double(i) / seconds)
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: s.height))
                    ctx.stroke(line, with: .color(Theme.ink.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }
        }
    }

    private func tool(_ icon: String, _ label: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(Theme.font(10, .bold))
            }
            .foregroundStyle(on ? Theme.onAccent : Theme.title)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Theme.accent : Theme.ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Drawing

    private func load() {
        var start: [Int]
        if initial.isEmpty { start = [] }
        else if initialGeneration == 3 { start = TouchPattern.trimmed(initial) }
        else { start = TouchPattern.samples(fromOnOff: initial) }
        let n = max(start.count, 20)
        seconds = min(10, max(1, (Double(n * TouchPattern.sampleMs) / 1000 * 2).rounded() / 2))
        samples = start + Array(repeating: TouchPattern.none, count: max(0, count - start.count))
    }

    private func resize(to s: Double) {
        seconds = s
        if samples.count < count { samples += Array(repeating: TouchPattern.none, count: count - samples.count) }
        else if samples.count > count { samples = Array(samples.prefix(count)) }
    }

    private func pushUndo() {
        undoStack.append(samples)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    private func draw(at p: CGPoint, size: CGSize, starting: Bool) {
        guard size.width > 0, count > 0 else { return }
        if starting { pushUndo() }
        if samples.count != count { resize(to: seconds) }
        let i = min(count - 1, max(0, Int(p.x / size.width * CGFloat(count))))
        let pos = min(top, max(0, Int(((1 - (p.y - 8) / (size.height - 16)) * CGFloat(top)).rounded())))
        let value = erasing ? TouchPattern.none : TouchPattern.sample([pos])
        if let li = lastIndex, let lp = lastPos, li != i {
            // Fill every step between the last point and this one, so a quick stroke has no holes.
            let step = i > li ? 1 : -1
            for k in stride(from: li, through: i, by: step) {
                let t = Double(k - li) / Double(i - li)
                let interp = Int((Double(lp) + Double(pos - lp) * t).rounded())
                samples[k] = erasing ? TouchPattern.none : TouchPattern.sample([interp])
            }
        } else {
            samples[i] = value
            // A tap is a short press (150 ms), not a single 50 ms blip.
            if starting, !erasing { for k in i..<min(count, i + 3) where samples[k] == TouchPattern.none { samples[k] = value } }
        }
        if pos != lastPos { UISelectionFeedbackGenerator().selectionChanged() }
        lastIndex = i
        lastPos = pos
    }

    private func feel() {
        model.feel(TouchMessage(senderID: model.myUserID, pattern: TouchPattern.trimmed(samples), generation: 3,
                                colorRGB: colorRGB, endColorRGB: endColorRGB))
    }
}
