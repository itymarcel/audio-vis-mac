import SwiftUI

/// Radial spectrum: bands as spokes around a pulsing ring.
final class HaloViz: Visualizer {
    private var smoother = Smoother()
    private var rot: Double = 0

    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s
        let n = Int(s.haloBands)
        let vals = smoother.step(rc.analyzer.bands(count: n, s: s), smoothing: Float(s.smoothing), frozen: rc.frozen)
        let bass = CGFloat(min(1.2, rc.analyzer.level(20, 140, s: s)))
        rot += rc.dt * s.motion * 0.5

        let c = rc.center
        let r0 = rc.minDim * 0.2 * CGFloat(s.zoom) * (1 + 0.15 * bass)
        let len = rc.minDim * 0.26 * CGFloat(s.zoom)
        let slots = CGFloat(s.mirror ? 2 * n : n)
        let lw = min(40, max(0.5, 2 * .pi * r0 / slots * 0.55 * CGFloat(s.size)))
        let glow = s.glow

        var spokes = Batch(), dots = Batch()
        for i in 0..<n {
            let a = CGFloat(vals[i])
            let frac = (Double(i) + 0.5) / Double(n)
            let angles = s.mirror
                ? [Double.pi / 2 + .pi * frac + rot, Double.pi / 2 - .pi * frac + rot]
                : [Double.pi / 2 + 2 * .pi * frac + rot]
            let t = (s.colorBy == .frequency ? Float(frac) : min(1, Float(a))) + rc.phase
            let alpha = Float(0.3 + 0.7 * min(1, a))
            for th in angles {
                let dx = CGFloat(cos(th)), dy = CGFloat(sin(th))
                let p0 = CGPoint(x: c.x + dx * r0, y: c.y + dy * r0)
                let p1 = CGPoint(x: c.x + dx * (r0 + a * len), y: c.y + dy * (r0 + a * len))
                if s.style != .points {
                    spokes.add(t, alpha) { $0.move(to: p0); $0.addLine(to: p1) }
                }
                if s.style != .lines {
                    let r = lw * 0.6 + a * lw * 0.8
                    dots.add(t, alpha) { $0.addEllipse(in: CGRect(x: p1.x - r, y: p1.y - r, width: 2 * r, height: 2 * r)) }
                }
            }
        }

        let ring = Path(ellipseIn: CGRect(x: c.x - r0, y: c.y - r0, width: 2 * r0, height: 2 * r0))
        g.blendMode = .plusLighter
        g.stroke(ring, with: .color(rc.palette.color(rc.phase, 0.25 + 0.4 * Double(min(bass, 1)))), lineWidth: max(1, rc.unit * 0.8))
        if glow > 0.01 {
            spokes.stroke(&g, rc.palette, width: lw * CGFloat(2.5 + 4 * glow), alpha: 0.15 * glow)
            dots.fill(&g, rc.palette, alpha: 0.6)
        }
        spokes.stroke(&g, rc.palette, width: lw)
        dots.fill(&g, rc.palette)
    }
}
