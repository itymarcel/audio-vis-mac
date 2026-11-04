import Foundation
import simd

/// Chladni-plate cymatics: GPU particles settle on the nodal lines of 8 plate modes mixed by the spectrum.
final class CymaticsViz: Visualizer {
    private var smoother = Smoother()
    private var frame: UInt32 = 0

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s
        let n = max(1000, Int(s.particleCount))
        // 8 octave-ish bands → 8 plate modes (low band → simplest mode)
        let raw = rc.analyzer.bands(count: 8, s: s)
        let lv = smoother.step(raw, smoothing: max(0.6, s.smoothing), dt: rc.dt, frozen: rc.frozen)
        var w = lv.map { $0 * $0 }
        let sum = w.reduce(0, +)
        if sum > 1e-4 { w = w.map { $0 / sum } } else { w = [1, 0, 0, 0, 0, 0, 0, 0] }
        let dom = Float(w.indices.max(by: { w[$0] < w[$1] }) ?? 0) / 7
        let level = min(1.2, lv.max() ?? 0)
        if !rc.frozen { frame &+= 1 }

        var sim = SimUniforms()
        sim.w0 = SIMD4(w[0], w[1], w[2], w[3])
        sim.w1 = SIMD4(w[4], w[5], w[6], w[7])
        sim.shake = rc.frozen ? 0 : 0.25 + level * 1.2
        sim.speed = rc.frozen ? 0 : Float(0.3 + s.motion * 1.5)
        sim.dtScale = Float(rc.dt * 60)
        sim.time = Float(rc.time)
        sim.beat = rc.frozen ? 0 : rc.beat
        sim.count = UInt32(n)
        sim.frame = frame
        sim.kind = ParticleKind.cymatics.rawValue

        let side = rc.minDim * 0.9 * Float(s.zoom) * (1 + 0.04 * rc.beat)
        var d = PartDrawUniforms()
        d.origin = rc.center - SIMD2(side, side) / 2
        d.extent = SIMD2(side, side)
        d.dotR = rc.unit * 0.9 * min(1.2, max(0.25, (200_000 / Float(n)).squareRoot()))
        d.alphaK = n > 200_000 ? max(0.25, pow(200_000 / Float(n), 0.35)) : 1
        d.phase = rc.phase
        d.colorByFreq = s.colorBy == .frequency ? 1 : 0
        d.square = s.segmented ? 1 : 0
        d.domT = dom
        d.speedK = 120
        d.kind = ParticleKind.cymatics.rawValue
        d.count = UInt32(n)
        f.particles = ParticleDraw(kind: .cymatics, count: n, bandCount: 0, sim: sim, draw: d)

        // Plate outline
        let o = d.origin, e = d.extent
        let c = rc.inkC(0.12)
        f.line(o, o + SIMD2(e.x, 0), c, 1)
        f.line(o + SIMD2(e.x, 0), o + e, c, 1)
        f.line(o + e, o + SIMD2(0, e.y), c, 1)
        f.line(o + SIMD2(0, e.y), o, c, 1)
    }
}

/// Curl-noise particle flow; each particle is bound to a frequency band and moves with its energy.
final class FlowViz: Visualizer {
    private var frame: UInt32 = 0
    private var time: Double = 0

    func build(_ f: FrameBuilder, _ rc: RenderContext) {
        let s = rc.s
        let n = max(1000, Int(s.particleCount))
        let bands = 256
        let treble = min(1.5, rc.analyzer.level(4000, 14000, s: s))
        if !rc.frozen {
            frame &+= 1
            time += rc.dt * (0.4 + s.motion)
        }

        var sim = SimUniforms()
        sim.speed = rc.frozen ? 0 : Float(0.5 + s.motion)
        sim.dtScale = Float(rc.dt * 60)
        sim.time = Float(time)
        sim.turb = 0.3 + treble * 1.5
        sim.noiseScale = Float(2.5 / s.zoom)
        sim.beat = rc.frozen ? 0 : rc.beat
        sim.count = UInt32(n)
        sim.frame = frame
        sim.bandCount = UInt32(bands)
        sim.kind = ParticleKind.flow.rawValue
        sim.aspect = rc.size.x / max(rc.size.y, 1)

        var d = PartDrawUniforms()
        d.origin = .zero
        d.extent = rc.size
        d.dotR = rc.unit * 0.8 * min(1.2, max(0.25, (200_000 / Float(n)).squareRoot()))
        d.alphaK = n > 200_000 ? max(0.25, pow(200_000 / Float(n), 0.35)) : 1
        d.phase = rc.phase
        d.colorByFreq = s.colorBy == .frequency ? 1 : 0
        d.square = s.segmented ? 1 : 0
        d.streak = s.style == .points ? 0 : 4
        d.speedK = 150
        d.kind = ParticleKind.flow.rawValue
        d.count = UInt32(n)
        d.bandCount = UInt32(bands)
        f.particles = ParticleDraw(kind: .flow, count: n, bandCount: bands, sim: sim, draw: d)
    }
}
