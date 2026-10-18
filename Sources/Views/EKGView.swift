import SwiftUI

/// A heart-monitor trace. Live (`start` set): a glowing light sweeps across, drawing the
/// heartbeat behind it — resting on the middle line between beats, spiking up and down on
/// each one. Static (`start` nil): a few beats drawn still, for history.
struct EKGView: View {
    let bpm: Int
    var colorRGB: Int = EKG.colorRGB
    var start: Date? = nil
    /// Seconds of trace across the width.
    var window: Double = 2.4
    var lineWidth: CGFloat = 2.5

    var body: some View {
        if let start {
            TimelineView(.animation) { context in
                Canvas { ctx, size in draw(ctx, size, elapsed: context.date.timeIntervalSince(start)) }
            }
        } else {
            Canvas { ctx, size in draw(ctx, size, elapsed: nil) }
        }
    }

    private var color: Color { Color(rgbInt: colorRGB) }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, elapsed: Double?) {
        let mid = size.height / 2, amp = size.height * 0.44
        func y(_ t: Double) -> CGFloat { mid - CGFloat(EKG.level(elapsed: t, bpm: bpm)) * amp }

        // Faint baseline + grid ticks, like monitor paper.
        var grid = Path()
        grid.move(to: CGPoint(x: 0, y: mid)); grid.addLine(to: CGPoint(x: size.width, y: mid))
        ctx.stroke(grid, with: .color(color.opacity(0.18)), lineWidth: 1)

        let steps = max(2, Int(size.width / 1.5))
        guard let elapsed else {
            var p = Path()
            for i in 0...steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                let t = window * Double(i) / Double(steps) + 0.05
                if i == 0 { p.move(to: CGPoint(x: x, y: y(t))) } else { p.addLine(to: CGPoint(x: x, y: y(t))) }
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            return
        }

        // Sweep: the head moves left→right over `window` seconds, then wraps; the newest trace
        // is bright, older trace fades out toward the gap ahead of the head.
        let sweep = elapsed.truncatingRemainder(dividingBy: window)
        let head = size.width * CGFloat(sweep / window)
        let segments = 24
        for s in 0..<segments {
            let from = Double(s) / Double(segments), to = Double(s + 1) / Double(segments)
            var p = Path()
            var lastX: CGFloat?
            let n = steps / segments + 1
            for j in 0...n {
                let f = from + (to - from) * Double(j) / Double(n)   // 0 = oldest, 1 = head
                let age = (1 - f) * (window - 0.25)
                let t = elapsed - age
                guard t >= 0 else { continue }
                var x = head - CGFloat(age / window) * size.width
                if x < 0 { x += size.width }
                let pt = CGPoint(x: x, y: y(t))
                // Start a new stroke at the start and where the trace wraps (right edge → left).
                if let lx = lastX, x >= lx - 1 { p.addLine(to: pt) } else { p.move(to: pt) }
                lastX = x
            }
            ctx.stroke(p, with: .color(color.opacity(0.15 + 0.85 * to)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // The light at the head: rests on the middle line, flares on the spike.
        let level = EKG.level(elapsed: elapsed, bpm: bpm)
        let flare = CGFloat(min(1, abs(level)))
        let r = 4 + 7 * flare
        let dot = CGRect(x: head - r, y: y(elapsed) - r, width: r * 2, height: r * 2)
        var glow = ctx
        glow.addFilter(.blur(radius: 8 + 10 * flare))
        glow.fill(Path(ellipseIn: dot.insetBy(dx: -6, dy: -6)), with: .color(color.opacity(0.9)))
        ctx.fill(Path(ellipseIn: dot), with: .color(.white))
    }
}

/// The partner's heartbeat arriving (or one replayed from history): a full-width card with
/// the live EKG, the BPM and who it's from. Taps through to dismiss.
struct HeartbeatOverlay: View {
    let show: HeartbeatShow
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color(rgbInt: show.colorRGB))
                Text("\(show.name)'s heartbeat").font(Theme.font(16, .heavy)).foregroundStyle(Theme.title)
                Spacer()
                Text("\(show.bpm)").font(Theme.font(28, .heavy)).foregroundStyle(Theme.title).monospacedDigit()
                Text("BPM").font(Theme.font(12, .bold)).foregroundStyle(Theme.subtitle)
            }
            EKGView(bpm: show.bpm, colorRGB: show.colorRGB, start: show.start)
                .frame(height: 96)
        }
        .padding(16)
        .glass(cornerRadius: 26)
        .shadow(color: Color(rgbInt: show.colorRGB).opacity(0.45), radius: 24)
        .padding(.horizontal, 16)
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.name)'s heartbeat, \(show.bpm) beats per minute")
    }
}
