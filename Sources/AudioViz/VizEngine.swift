import SwiftUI

/// Owns audio capture, analysis and the visualizers; renders one frame per Canvas pass.
final class VizEngine {
    let ring = AudioRing()
    lazy var analyzer = Analyzer(ring: ring)
    private var tap: SystemAudioTap?
    private var tapError: String?
    private var statusTimer: Timer?
    private var lastTime: Double?
    private var fps: Double = 60
    private var cyclePhase: Float = 0

    private let visualizers: [VizMode: Visualizer] = [
        .sphere: SphereViz(),
        .oscilloscope: ScopeViz(),
        .snippet: SnippetViz(),
        .vectorscope: VectorViz(),
        .halo: HaloViz(),
        .spectrogram: SpectroViz(),
    ]

    func start(app: AppState) {
        guard tap == nil else { return }
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
            } else if !app.frozen && now - self.analyzer.lastSoundTime > 3 {
                msg = "Waiting for sound… If audio is playing, allow AudioViz under System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch."
            }
            if app.status != msg { app.status = msg }
        }
    }

    func render(_ g: inout GraphicsContext, size: CGSize, date: Date, settings s: VizSettings, frozen: Bool) {
        let t = date.timeIntervalSinceReferenceDate
        let dt = min(max(lastTime.map { t - $0 } ?? 1 / 60, 0), 0.1)
        lastTime = t
        if dt > 0 { fps = fps * 0.95 + (1 / dt) * 0.05 }

        if !frozen { analyzer.update(now: t) }
        cyclePhase += Float(dt * s.colorCycle * 0.15)
        if cyclePhase > 2 { cyclePhase -= 2 }

        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(s.bgOpacity)))

        let rc = RenderContext(
            size: size, s: s, time: t, dt: dt, frozen: frozen,
            analyzer: analyzer, palette: s.palette.palette,
            phase: Float(s.hueShift) + cyclePhase)
        var layer = g
        visualizers[s.mode]?.draw(&layer, rc)

        if s.showFPS {
            g.draw(Text(String(format: "%.0f fps", fps)).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.6)),
                   at: CGPoint(x: 12, y: size.height - 12), anchor: .bottomLeading)
        }
    }
}
