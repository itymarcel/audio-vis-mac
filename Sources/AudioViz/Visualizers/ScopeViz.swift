import SwiftUI

/// Classic triggered oscilloscope.
final class ScopeViz: Visualizer {
    private struct Frame { var line = Path(); var dots = Path(); var t: Float }
    private var history: [Frame] = []

    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        let w = rc.size.width, h = rc.size.height

        if !rc.frozen || history.isEmpty {
            let count = min(max(Int(s.scopeMs * 0.001 * a.sampleRate), 16), a.snapSize / 2)
            let search = min(Int(a.sampleRate / 25), a.snapSize - count - 1)
            let base = a.snapSize - count - search
            let L = a.snapL, R = a.snapR

            // Trigger: newest rising zero crossing (with a little hysteresis) in the search region.
            var start = base + search
            var j = search - 1
            while j >= 4 {
                let i = base + j
                let m1 = L[i] + R[i], m0 = L[i - 1] + R[i - 1], mPrev = L[i - 4] + R[i - 4]
                if m0 < 0 && m1 >= 0 && mPrev < -0.002 { start = i; break }
                j -= 1
            }

            let lanes: [Int] = s.stereo ? [0, 1] : [-1]
            let laneH = h / CGFloat(lanes.count)
            let scale = laneH * 0.42 * CGFloat(s.gain * s.zoom)
            let cols = max(Int(w), 2)
            let step = max(1, count / (cols * 2))
            var frame = Frame(t: 0)

            for (li, lane) in lanes.enumerated() {
                let cy = laneH * (CGFloat(li) + 0.5)
                func sample(_ i: Int) -> Float {
                    switch lane {
                    case 0: return L[i]
                    case 1: return R[i]
                    default: return 0.5 * (L[i] + R[i])
                    }
                }
                for mirror in (s.mirror ? [false, true] : [false]) {
                    let sign: CGFloat = mirror ? 1 : -1
                    var pts: [CGPoint] = []
                    pts.reserveCapacity(count / step + 2)
                    var i = 0
                    while i < count {
                        if step > 1 {
                            // min/max decimation keeps peaks visible on long windows
                            var lo: Float = 1e9, hi: Float = -1e9
                            for k in i..<min(i + step, count) { let v = sample(start + k); lo = min(lo, v); hi = max(hi, v) }
                            let x = CGFloat(i) / CGFloat(count - 1) * w
                            pts.append(CGPoint(x: x, y: cy + sign * CGFloat(lo) * scale))
                            pts.append(CGPoint(x: x, y: cy + sign * CGFloat(hi) * scale))
                        } else {
                            pts.append(CGPoint(x: CGFloat(i) / CGFloat(count - 1) * w, y: cy + sign * CGFloat(sample(start + i)) * scale))
                        }
                        i += step
                    }
                    if s.style != .points { frame.line.addLines(pts) }
                    if s.style != .lines {
                        let r = rc.unit * 1.1
                        let dStep = max(1, pts.count / 1500)
                        for k in stride(from: 0, to: pts.count, by: dStep) {
                            frame.dots.addEllipse(in: CGRect(x: pts[k].x - r, y: pts[k].y - r, width: 2 * r, height: 2 * r))
                        }
                    }
                }
            }
            frame.t = min(1, a.rms(last: count) * 3 * Float(s.gain))
            history.append(frame)
            let keep = 1 + Int(s.persistence * 14)
            if history.count > keep { history.removeFirst(history.count - keep) }
        }

        g.blendMode = .plusLighter
        let lw = rc.unit * 1.2
        let glow = s.glow
        for (k, f) in history.enumerated() {
            let isNewest = k == history.count - 1
            let age = Double(k + 1) / Double(history.count)
            g.opacity = isNewest ? 1 : 0.5 * age * age
            let shading: GraphicsContext.Shading = s.colorBy == .frequency
                ? .linearGradient(rc.palette.gradient(rc.phase, rc.phase + 0.75), startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
                : .color(rc.palette.color(f.t + rc.phase))
            if glow > 0.01 {
                var gg = g
                gg.opacity *= 0.18 * glow
                gg.stroke(f.line, with: shading, style: StrokeStyle(lineWidth: lw * (4 + 8 * glow), lineCap: .round, lineJoin: .round))
            }
            g.stroke(f.line, with: shading, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            g.fill(f.dots, with: shading)
        }
        g.opacity = 1
    }
}
