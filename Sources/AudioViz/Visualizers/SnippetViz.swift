import Foundation
import simd

/// Flat rolling waveform of the last few seconds (DAW-clip style), newest at the right.
final class SnippetViz: Visualizer {
    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s, a = rc.analyzer
        let w = rc.size.x, h = rc.size.y
        let want = max(8, Int(s.snippetSeconds * a.sampleRate / Double(Analyzer.chunk)))
        let laneCount = s.stereo ? 2 : 1
        let laneH = h / Float(laneCount)
        let scale = laneH * 0.46 * Float(s.gain * s.zoom)

        for lane in 0..<laneCount {
            let cy = laneH * (Float(lane) + 0.5)
            f.line(SIMD2(0, cy), SIMD2(w, cy), rc.inkC(0.18), 1)
        }

        let cols = a.recentColumns(want)
        guard !cols.isEmpty else { return }
        let colW = w / Float(want)
        let barW = max(0.5, colW * min(1, 0.25 + Float(s.size) * 0.4))
        let dash: Float = s.segmented ? max(4, rc.unit * 5) : 0
        let n = cols.count

        for (i, c) in cols.enumerated() {
            let x = w - Float(n - i) * colW
            let t = (s.colorBy == .frequency ? c.bright : min(1, c.rms * 3 * Float(s.gain))) + rc.phase
            let alpha = 0.55 + 0.45 * Float(i) / Float(n)
            for lane in 0..<laneCount {
                let cy = laneH * (Float(lane) + 0.5)
                var lo: Float, hi: Float
                if s.stereo {
                    (lo, hi) = lane == 0 ? (c.minL, c.maxL) : (c.minR, c.maxR)
                } else {
                    lo = min(c.minL, c.minR); hi = max(c.maxL, c.maxR)
                }
                if s.mirror { let p = max(abs(lo), abs(hi)); lo = -p; hi = p }
                let y0 = cy - hi * scale
                let y1 = max(y0 + 1, cy - lo * scale)
                let rr = c.rms * scale
                if s.style != .points {
                    f.rect(x: x, y: y0, w: barW, h: y1 - y0, rc.col(t, alpha * 0.5), dash: dash)
                    f.rect(x: x, y: cy - rr, w: barW, h: max(1, 2 * rr), rc.col(t, alpha), dash: dash)
                }
                if s.style != .lines {
                    let r = max(0.6, min(barW, rc.unit * 2) * 0.7)
                    f.dot(SIMD2(x + barW / 2, y0), r, rc.col(t, alpha), square: s.segmented)
                    f.dot(SIMD2(x + barW / 2, y1), r, rc.col(t, alpha), square: s.segmented)
                }
            }
        }
    }

}
