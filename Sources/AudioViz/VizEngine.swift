import Foundation
import simd

/// Owns audio capture, analysis and the visualizers. The Metal renderer drives it once per frame.
final class VizEngine {
    let ring = AudioRing()
    lazy var analyzer = Analyzer(ring: ring)
    private var tap: SystemAudioTap?
    private var tapError: String?
    private var statusTimer: Timer?
    private var startTime = Date().timeIntervalSinceReferenceDate
    private var cyclePhase: Float = 0
    /// Smoothed frame rate, written by the renderer.
    var fps: Double = 0

    private let visualizers: [VizMode: Visualizer] = [
        .sphere: SphereViz(),
        .oscilloscope: ScopeViz(),
        .snippet: SnippetViz(),
        .vectorscope: VectorViz(),
        .halo: HaloViz(),
        .spectrogram: SpectroViz(),
        .cymatics: CymaticsViz(),
        .flow: FlowViz(),
    ]

    var outputName: String { tap?.outputName ?? "" }
    var tapOK: Bool { tapError == nil }

    func visualizer(for mode: VizMode) -> Visualizer { visualizers[mode]! }

    func start(app: AppState) {
        guard tap == nil else { return }
        startTime = Date().timeIntervalSinceReferenceDate
        let tap = SystemAudioTap(ring: ring)
        tap.onStatus = { [weak self] msg in self?.tapError = msg }
        self.tap = tap
        tap.start()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak app] _ in
            guard let self, let app else { return }
            let now = Date().timeIntervalSinceReferenceDate
            var msg: String?
            if let err = self.tapError {
                msg = "Audio capture failed: \(err). Requires macOS 14.2 or later."
            } else if !app.frozen && now - self.startTime > 3 && CACurrentMediaTimeSafe() - self.analyzer.lastSoundTime > 3 {
                msg = "No audio signal. If something is playing, allow AudioViz in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch."
            }
            if app.status != msg { app.status = msg }
        }
    }

    func prepare(size: SIMD2<Float>, settings s: VizSettings, dt: Double, time: Double, frozen: Bool) -> RenderContext {
        if !frozen { analyzer.update(now: CACurrentMediaTimeSafe(), fftSize: Int(s.fftSize)) }
        cyclePhase += Float(dt * s.colorCycle * 0.15)
        if cyclePhase > 2 { cyclePhase -= 2 }
        let ink = s.palette.ink
        return RenderContext(
            size: size, s: s, time: time, dt: dt, frozen: frozen, analyzer: analyzer,
            palette: s.palette.palette, phase: Float(s.hueShift) + cyclePhase,
            ink: SIMD3(Float((ink >> 16) & 0xFF) / 255, Float((ink >> 8) & 0xFF) / 255, Float(ink & 0xFF) / 255),
            beat: analyzer.beatPulse * Float(s.beat))
    }
}

import QuartzCore
@inline(__always) func CACurrentMediaTimeSafe() -> Double { CACurrentMediaTime() }
