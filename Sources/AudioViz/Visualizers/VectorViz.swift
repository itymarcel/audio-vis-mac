import Foundation
import simd

/// Stereo vectorscope / Lissajous: x = side (L−R), y = mid (L+R).
final class VectorViz: Visualizer {
    private var rot: Double = 0

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        rot += rc.dt * s.motion * 0.6
        let c = rc.center

        let count = min(max(Int(s.vectorMs * 0.001 * a.sampleRate), 16), a.snapSize)
        let start = a.snapSize - count
        let scale = rc.minDim * 0.38 * Float(s.gain * s.zoom)
        let cr = Float(cos(rot)), sr = Float(sin(rot))
        let L = a.snapL, R = a.snapR
        let lw = rc.unit
        let dash: Float = s.segmented ? lw * 5 : 0
        let r = rc.unit * 0.9

        var pts = [SIMD2<Float>](repeating: .zero, count: count)
        var radius = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let l = L[start + i], rr = R[start + i]
            let x = (l - rr) * 0.7071, y = (l + rr) * 0.7071
            radius[i] = (x * x + y * y).squareRoot()
            pts[i] = SIMD2(x * cr - y * sr, -(x * sr + y * cr)) * scale
        }
        func color(_ k: Int) -> SIMD4<Float> {
            let age = Float(k) / Float(count)
            let t = (s.colorBy == .frequency ? age * 0.8 : min(1, radius[k] * 3)) + rc.phase
            return rc.col(t, 0.25 + 0.75 * age)
        }
        let dStep = max(1, count / 8000)
        for mirror in (s.mirror ? [false, true] : [false]) {
            let mp = pts.map { c + SIMD2(mirror ? -$0.x : $0.x, $0.y) }
            if s.style != .points { f.polyline(mp, lw, dash: dash, color: color) }
            if s.style != .lines {
                for k in stride(from: 0, to: count, by: dStep) { f.dot(mp[k], r, color(k), square: s.segmented) }
            }
        }
    }

}
