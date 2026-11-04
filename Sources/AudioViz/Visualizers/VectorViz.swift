import SwiftUI

/// Stereo vectorscope / Lissajous: x = side (L−R), y = mid (L+R).
final class VectorViz: Visualizer {
    private var history: [(lines: Batch, dots: Batch)] = []
    private var rot: Double = 0

    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        rot += rc.dt * s.motion * 0.6

        if !rc.frozen || history.isEmpty {
            let count = min(max(Int(s.vectorMs * 0.001 * a.sampleRate), 16), a.snapSize)
            let start = a.snapSize - count
            let scale = rc.minDim * 0.38 * CGFloat(s.gain * s.zoom)
            let c = rc.center
            let cr = CGFloat(cos(rot)), sr = CGFloat(sin(rot))
            let step = max(1, count / 4000)
            let segments = 12
            let L = a.snapL, R = a.snapR
            let r = rc.unit * 0.9

            var lines = Batch(), dots = Batch()
            for seg in 0..<segments {
                let i0 = start + seg * count / segments
                let i1 = start + (seg + 1) * count / segments
                var pts: [CGPoint] = []
                var radius: CGFloat = 0
                var i = max(start, i0 - step)  // overlap so segments connect
                while i < i1 {
                    let l = CGFloat(L[i]), rr = CGFloat(R[i])
                    let x = (l - rr) * 0.7071, y = (l + rr) * 0.7071
                    radius += hypot(x, y)
                    let xr = x * cr - y * sr, yr = x * sr + y * cr
                    pts.append(CGPoint(x: xr * scale, y: -yr * scale))
                    i += step
                }
                guard pts.count > 1 else { continue }
                radius /= CGFloat(pts.count)
                let age = Float(seg + 1) / Float(segments)
                let t = (s.colorBy == .frequency ? age * 0.8 : min(1, Float(radius) * 3)) + rc.phase
                let alpha = 0.25 + 0.75 * age

                for mirror in (s.mirror ? [false, true] : [false]) {
                    let mp = pts.map { CGPoint(x: c.x + (mirror ? -$0.x : $0.x), y: c.y + $0.y) }
                    if s.style != .points { lines.add(t, alpha) { $0.addLines(mp) } }
                    if s.style != .lines {
                        dots.add(t, alpha) { p in
                            for q in mp { p.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)) }
                        }
                    }
                }
            }
            history.append((lines, dots))
            let keep = 1 + Int(s.persistence * 14)
            if history.count > keep { history.removeFirst(history.count - keep) }
        }

        // faint crosshair
        var axes = Path()
        let c = rc.center, ext = rc.minDim * 0.42
        axes.move(to: CGPoint(x: c.x - ext, y: c.y)); axes.addLine(to: CGPoint(x: c.x + ext, y: c.y))
        axes.move(to: CGPoint(x: c.x, y: c.y - ext)); axes.addLine(to: CGPoint(x: c.x, y: c.y + ext))
        g.stroke(axes, with: .color(rc.palette.color(rc.phase, 0.12)), lineWidth: 1)

        g.blendMode = .plusLighter
        let lw = rc.unit
        for (k, f) in history.enumerated() {
            let age = Double(k + 1) / Double(history.count)
            let alpha = k == history.count - 1 ? 1 : 0.5 * age * age
            if s.glow > 0.01 { f.lines.stroke(&g, rc.palette, width: lw * CGFloat(4 + 8 * s.glow), alpha: alpha * 0.15 * s.glow) }
            f.lines.stroke(&g, rc.palette, width: lw, alpha: alpha)
            f.dots.fill(&g, rc.palette, alpha: alpha)
        }
    }
}
