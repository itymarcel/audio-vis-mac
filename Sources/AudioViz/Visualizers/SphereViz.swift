import SwiftUI
import simd

/// N points evenly distributed on a sphere (Fibonacci lattice); point i = frequency band i.
final class SphereViz: Visualizer {
    private var unit: [SIMD3<Float>] = []
    private var smoother = Smoother()
    private var angle: Double = 0

    private static func fibonacci(_ n: Int) -> [SIMD3<Float>] {
        let golden = Float.pi * (3 - sqrt(5))
        return (0..<n).map { i in
            let y = -1 + 2 * (Float(i) + 0.5) / Float(n)   // bass at the bottom pole
            let r = sqrt(max(0, 1 - y * y))
            let th = golden * Float(i)
            return SIMD3(cos(th) * r, y, sin(th) * r)
        }
    }

    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s
        let n = Int(s.spherePoints)
        if unit.count != n { unit = Self.fibonacci(n) }

        let bandCount = s.mirror ? (n + 1) / 2 : n
        let vals = smoother.step(rc.analyzer.bands(count: bandCount, s: s), smoothing: Float(s.smoothing), frozen: rc.frozen)
        let bass = min(1.2, rc.analyzer.level(20, 140, s: s))

        angle += rc.dt * s.motion * 1.4
        let tilt = 0.45 + 0.2 * sin(angle * 0.37)
        let ca = Float(cos(angle)), sa = Float(sin(angle))
        let ct = Float(cos(tilt)), st = Float(sin(tilt))

        let R = Float(rc.minDim) * 0.27 * Float(s.zoom) * (1 + 0.12 * bass)
        let cx = Float(rc.size.width / 2), cy = Float(rc.size.height / 2)
        let cam: Float = 3.4
        let dot = Float(rc.unit) * 1.3
        let glow = Float(s.glow)
        let wantDots = s.style != .lines, wantLines = s.style != .points

        var dots = Batch(), halo = Batch(), spikes = Batch()
        for i in 0..<n {
            let bi = s.mirror ? min(i, n - 1 - i) : i
            let a = vals[bi]
            let p = unit[i]
            // rotate around Y, then tilt around X
            let x1 = p.x * ca + p.z * sa
            let z1 = -p.x * sa + p.z * ca
            let y2 = p.y * ct - z1 * st
            let z2 = p.y * st + z1 * ct

            let disp = 1 + a * 0.55
            let proj = cam / (cam - z2 * disp)
            let sx = cx + x1 * disp * R * proj
            let sy = cy - y2 * disp * R * proj

            let depth = (z2 + 1) * 0.5
            let fade = 0.15 + 0.85 * depth
            let t = (s.colorBy == .frequency ? Float(bi) / Float(max(bandCount - 1, 1)) : min(a, 1)) + rc.phase
            let alpha = fade * (0.3 + 0.7 * min(a * 1.2, 1))

            if wantDots {
                let r = CGFloat(dot * proj * (0.6 + 1.6 * a))
                dots.add(t, alpha) { $0.addEllipse(in: CGRect(x: CGFloat(sx) - r, y: CGFloat(sy) - r, width: 2 * r, height: 2 * r)) }
                if glow > 0.01 && a > 0.05 {
                    let gr = r * CGFloat(2.5 + 5 * glow)
                    halo.add(t, alpha * glow * 0.22 * a) {
                        $0.addEllipse(in: CGRect(x: CGFloat(sx) - gr, y: CGFloat(sy) - gr, width: 2 * gr, height: 2 * gr))
                    }
                }
            }
            if wantLines {
                let p0 = cam / (cam - z2)
                let bx = CGFloat(cx + x1 * R * p0), by = CGFloat(cy - y2 * R * p0)
                spikes.add(t, alpha) {
                    $0.move(to: CGPoint(x: bx, y: by))
                    $0.addLine(to: CGPoint(x: CGFloat(sx), y: CGFloat(sy)))
                }
                if !wantDots {
                    let r = CGFloat(dot * p0 * 0.45)
                    dots.add(t, fade * 0.35) { $0.addEllipse(in: CGRect(x: bx - r, y: by - r, width: 2 * r, height: 2 * r)) }
                }
            }
        }

        g.blendMode = .plusLighter
        halo.fill(&g, rc.palette)
        if wantLines {
            let w = rc.unit * 0.9
            if glow > 0.01 { spikes.stroke(&g, rc.palette, width: w * CGFloat(3 + 4 * glow), alpha: Double(0.15 * glow)) }
            spikes.stroke(&g, rc.palette, width: w)
        }
        dots.fill(&g, rc.palette)
    }
}
