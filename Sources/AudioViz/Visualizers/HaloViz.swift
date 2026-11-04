import Foundation
import simd

/// Radial spectrum: bands as spokes around a pulsing ring.
final class HaloViz: Visualizer {
    private var smoother = Smoother()
    private var rot: Double = 0

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s
        let n = Int(s.haloBands)
        let vals = smoother.step(rc.analyzer.bands(count: n, s: s), smoothing: s.smoothing, dt: rc.dt, frozen: rc.frozen)
        let bass = min(1.2, rc.analyzer.level(20, 140, s: s))
        rot += rc.dt * s.motion * 0.5

        let c = rc.center
        let r0 = rc.minDim * 0.2 * Float(s.zoom) * (1 + 0.15 * bass + 0.1 * rc.beat)
        let len = rc.minDim * 0.26 * Float(s.zoom * s.reach)
        let slots = Float(s.mirror ? 2 * n : n)
        let lw = min(40, max(0.5, 2 * .pi * r0 / slots * 0.55 * Float(s.size)))
        let dash: Float = s.segmented ? max(3, len / 22) : 0

        f.circle(c, r0, rc.col(rc.phase, 0.25 + 0.4 * min(bass, 1)), max(1, rc.unit * 0.8))

        for i in 0..<n {
            let a = vals[i]
            let frac = (Double(i) + 0.5) / Double(n)
            let t = (s.colorBy == .frequency ? Float(frac) : min(1, a)) + rc.phase
            let col = rc.col(t, 0.3 + 0.7 * min(1, a))
            let angles = s.mirror ? [Double.pi / 2 + .pi * frac + rot, Double.pi / 2 - .pi * frac + rot]
                                  : [Double.pi / 2 + 2 * .pi * frac + rot]
            for th in angles {
                let d = SIMD2(Float(cos(th)), Float(sin(th)))
                let p0 = c + d * r0, p1 = c + d * (r0 + a * len)
                if s.style != .points { f.spoke(p0, p1, col, lw, dash: dash) }
                if s.style != .lines { f.dot(p1, lw * 0.6 + a * lw * 0.8, col, square: s.segmented) }
            }
        }
    }

}
