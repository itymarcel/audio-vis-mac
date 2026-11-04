import Foundation
import simd

/// N points on a Fibonacci sphere, point i = log-spaced frequency band i. Fully GPU-driven.
final class SphereViz: Visualizer {
    private var angle: Double = 0
    /// Harmonics: smoothed per-mode weights and spin angles.
    private var weights = [Float](repeating: 0, count: 8)
    private var spins: [Float] = (0..<8).map { Float($0) * 0.9 }

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s
        let n = max(100, Int(s.spherePoints))
        let layout = s.sphereLayout
        let histBands = min(1024, max(32, Int((Double(n) / 2).squareRoot())))
        let bandCount = layout.usesHistory ? histBands : layout == .harmonics ? 64 : n
        let bass = min(1.2, rc.analyzer.level(20, 140, s: s))

        angle += rc.dt * s.motion * 1.4
        let tilt = 0.45 + 0.2 * sin(angle * 0.37)
        let ca = Float(cos(angle)), sa = Float(sin(angle)), ct = Float(cos(tilt)), st = Float(sin(tilt))
        let R0 = rc.minDim * 0.27 * Float(s.zoom)
        let R = R0 * (1 + 0.12 * bass + 0.1 * rc.beat)
        let cam: Float = 3.4

        // Dots shrink and dim as the count grows so dense spheres stay detailed instead of blowing out.
        let density = Float(n) / 1000
        let dotR = rc.unit * 1.3 * min(1.5, max(0.12, 1 / density.squareRoot()))
        let alphaK = n > 4000 ? max(0.2, pow(4000 / Float(n), 0.22)) : 1

        var u = SphereUniforms()
        u.rot0 = SIMD4(ca, 0, sa, 0)
        u.rot1 = SIMD4(st * sa, ct, -st * ca, 0)
        u.rot2 = SIMD4(-ct * sa, st, ct * ca, 0)
        u.center = rc.center
        u.R = R
        u.cam = cam
        u.dotR = dotR
        u.dispK = 0.55
        u.phase = rc.phase
        u.colorByFreq = s.colorBy == .frequency ? 1 : 0
        u.lineW = rc.unit * 0.9 * min(1, max(0.35, 1 / density.squareRoot() * 2))
        u.alphaK = alphaK
        u.square = s.segmented ? 1 : 0
        u.dash = s.segmented ? rc.unit * 4 : 0
        u.N = UInt32(n)
        u.bandCount = UInt32(bandCount)
        u.mirror = s.mirror ? 1 : 0
        u.layout = layout.shaderMode
        u.histBands = UInt32(histBands)
        if layout == .harmonics {
            if !rc.frozen {
                let b = rc.analyzer.bands(count: 8, s: s)
                let release = Float(pow(min(s.smoothing, 0.98), rc.dt * 60))
                for k in 0..<8 {
                    let v = b[k] * 0.32
                    let kk = v > weights[k] ? release * 0.5 : release
                    weights[k] = weights[k] * kk + v * (1 - kk)
                    // Each mode drifts around the axis at its own speed, faster when it's loud.
                    let dir: Float = k % 2 == 0 ? 1 : -1
                    spins[k] += dir * Float(rc.dt * s.motion) * (0.15 + 0.08 * Float(k)) * (1 + 2 * weights[k] + rc.beat)
                }
            }
            u.w0 = SIMD4(weights[0], weights[1], weights[2], weights[3])
            u.w1 = SIMD4(weights[4], weights[5], weights[6], weights[7])
            u.spin0 = SIMD4(spins[0], spins[1], spins[2], spins[3])
            u.spin1 = SIMD4(spins[4], spins[5], spins[6], spins[7])
        }
        f.sphere = SphereDraw(u: u, n: n, layout: layout, bandCount: bandCount,
                              dots: s.style != .lines, spikes: s.style != .points, baseDots: s.style == .lines)

    }

}
