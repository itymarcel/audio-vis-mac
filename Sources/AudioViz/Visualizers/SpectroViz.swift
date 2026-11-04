import Foundation
import simd

/// Scrolling spectrogram waterfall: frequency left→right, newest row on top. History lives in a GPU ring texture.
final class SpectroViz: Visualizer {
    private var smoother = Smoother()
    private var acc: Double = 0
    private let rows = 512

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s
        let n = Int(s.spectroBands)
        let vals = smoother.step(rc.analyzer.bands(count: n, s: s), smoothing: s.smoothing * 0.6, dt: rc.dt, frozen: rc.frozen)

        var newRows: [[Float]] = []
        if !rc.frozen {
            acc += rc.dt * rowsPerSecond(s)
            let pushes = min(Int(acc), 8)
            acc -= Double(Int(acc))
            newRows = Array(repeating: vals, count: pushes)
        }
        var u = SpectroUniforms()
        u.phase = rc.phase
        u.colorByFreq = s.colorBy == .frequency ? 1 : 0
        u.mirror = s.mirror ? 1 : 0
        u.nearest = s.segmented ? 1 : 0
        u.bands = Float(n)
        f.spectro = SpectroDraw(bands: n, newRows: newRows, u: u)

    }

    private func rowsPerSecond(_ s: VizSettings) -> Double { 15 + s.motion * 200 }

}
