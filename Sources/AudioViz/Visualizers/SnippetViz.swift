import SwiftUI

/// Flat rolling waveform of the last few seconds (DAW-clip style), newest at the right.
final class SnippetViz: Visualizer {
    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        let w = rc.size.width, h = rc.size.height
        let want = max(8, Int(s.snippetSeconds * a.sampleRate / Double(Analyzer.chunk)))
        let cols = a.recentColumns(want)
        guard !cols.isEmpty else { return }

        let colW = w / CGFloat(want)
        let barW = max(0.5, colW * min(1, 0.25 + CGFloat(s.size) * 0.4))
        let laneCount = s.stereo ? 2 : 1
        let laneH = h / CGFloat(laneCount)
        let scale = laneH * 0.46 * CGFloat(s.gain * s.zoom)
        let glow = Float(s.glow)

        var env = Batch(), core = Batch(), dots = Batch(), halo = Batch()
        let n = cols.count
        for (i, c) in cols.enumerated() {
            let x = w - CGFloat(n - i) * colW
            let t = (s.colorBy == .frequency ? c.bright : min(1, c.rms * 3 * Float(s.gain))) + rc.phase
            let alpha = 0.55 + 0.45 * Float(i) / Float(n)

            for lane in 0..<laneCount {
                let cy = laneH * (CGFloat(lane) + 0.5)
                var lo: Float, hi: Float
                if s.stereo {
                    (lo, hi) = lane == 0 ? (c.minL, c.maxL) : (c.minR, c.maxR)
                } else {
                    lo = min(c.minL, c.minR); hi = max(c.maxL, c.maxR)
                }
                if s.mirror { let p = max(abs(lo), abs(hi)); lo = -p; hi = p }
                let y0 = cy - CGFloat(hi) * scale
                let y1 = max(y0 + 1, cy - CGFloat(lo) * scale)
                let rr = CGFloat(c.rms) * scale

                if s.style != .points {
                    env.add(t, alpha * 0.5) { $0.addRect(CGRect(x: x, y: y0, width: barW, height: y1 - y0)) }
                    core.add(t, alpha) { $0.addRect(CGRect(x: x, y: cy - rr, width: barW, height: max(1, 2 * rr))) }
                }
                if s.style != .lines {
                    let r = max(1, min(barW, rc.unit * 2) * 0.7)
                    dots.add(t, alpha) {
                        $0.addEllipse(in: CGRect(x: x + barW / 2 - r, y: y0 - r, width: 2 * r, height: 2 * r))
                        $0.addEllipse(in: CGRect(x: x + barW / 2 - r, y: y1 - r, width: 2 * r, height: 2 * r))
                    }
                }
                if glow > 0.01 {
                    let pad = (y1 - y0) * CGFloat(0.25 * glow) + 4
                    halo.add(t, alpha * glow * 0.12) { $0.addRect(CGRect(x: x, y: y0 - pad, width: colW, height: y1 - y0 + 2 * pad)) }
                }
            }
        }

        // Centre line(s)
        var axis = Path()
        for lane in 0..<laneCount {
            let cy = laneH * (CGFloat(lane) + 0.5)
            axis.move(to: CGPoint(x: 0, y: cy)); axis.addLine(to: CGPoint(x: w, y: cy))
        }
        g.stroke(axis, with: .color(rc.palette.color(rc.phase, 0.15)), lineWidth: 1)

        g.blendMode = .plusLighter
        halo.fill(&g, rc.palette)
        env.fill(&g, rc.palette)
        core.fill(&g, rc.palette)
        dots.fill(&g, rc.palette)
    }
}
