import Foundation
import simd

/// Classic zero-crossing-triggered oscilloscope.
final class ScopeViz: Visualizer {
    private var frozenPts: [[SIMD2<Float>]] = []
    private var frozenT: Float = 0

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        let w = rc.size.x, h = rc.size.y

        var traces: [[SIMD2<Float>]]
        var ampT: Float
        if rc.frozen && !frozenPts.isEmpty {
            traces = frozenPts; ampT = frozenT
        } else {
            let count = min(max(Int(s.scopeMs * 0.001 * a.sampleRate), 16), a.snapSize / 2)
            let search = min(Int(a.sampleRate / 25), a.snapSize - count - 1)
            let base = a.snapSize - count - search
            let L = a.snapL, R = a.snapR

            var start = base + search
            var j = search - 1
            while j >= 4 {
                let i = base + j
                if L[i - 1] + R[i - 1] < 0 && L[i] + R[i] >= 0 && L[i - 4] + R[i - 4] < -0.002 { start = i; break }
                j -= 1
            }

            let lanes: [Int] = s.stereo ? [0, 1] : [-1]
            let laneH = h / Float(lanes.count)
            let scale = laneH * 0.42 * Float(s.gain * s.zoom)
            let step = max(1, count / (Int(w) * 2))
            traces = []
            for (li, lane) in lanes.enumerated() {
                let cy = laneH * (Float(li) + 0.5)
                func sample(_ i: Int) -> Float {
                    lane == 0 ? L[i] : (lane == 1 ? R[i] : 0.5 * (L[i] + R[i]))
                }
                for mirror in (s.mirror ? [false, true] : [false]) {
                    let sign: Float = mirror ? 1 : -1
                    var pts: [SIMD2<Float>] = []
                    pts.reserveCapacity(count / step * 2 + 2)
                    var i = 0
                    while i < count {
                        let x = Float(i) / Float(count - 1) * w
                        if step > 1 {
                            var lo: Float = 1e9, hi: Float = -1e9
                            for k in i..<min(i + step, count) { let v = sample(start + k); lo = min(lo, v); hi = max(hi, v) }
                            pts.append(SIMD2(x, cy + sign * lo * scale))
                            pts.append(SIMD2(x, cy + sign * hi * scale))
                        } else {
                            pts.append(SIMD2(x, cy + sign * sample(start + i) * scale))
                        }
                        i += step
                    }
                    traces.append(pts)
                }
            }
            ampT = min(1, a.rms(last: count) * 3 * Float(s.gain))
            frozenPts = traces; frozenT = ampT
        }

        let lw = rc.unit * 1.2
        let dash: Float = s.segmented ? lw * 5 : 0
        for pts in traces {
            func color(_ k: Int) -> SIMD4<Float> {
                let t = s.colorBy == .frequency ? rc.phase + 0.75 * pts[k].x / w : ampT + rc.phase
                return rc.col(t, 1)
            }
            if s.style != .points { f.polyline(pts, lw, dash: dash, color: color) }
            if s.style != .lines {
                let dStep = max(1, pts.count / 3000)
                for k in stride(from: 0, to: pts.count, by: dStep) { f.dot(pts[k], rc.unit * 1.1, color(k), square: s.segmented) }
            }
        }
    }

}
