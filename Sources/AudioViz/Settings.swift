import AppKit
import Foundation
import Observation

enum VizMode: String, Codable, CaseIterable, Identifiable {
    case sphere, oscilloscope, snippet, vectorscope, halo, spectrogram, cymatics, flow
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sphere: "Sphere"
        case .oscilloscope: "Oscilloscope"
        case .snippet: "Snippet"
        case .vectorscope: "Vectorscope"
        case .halo: "Halo"
        case .spectrogram: "Spectrogram"
        case .cymatics: "Cymatics"
        case .flow: "Flow"
        }
    }

    var symbol: String {
        switch self {
        case .sphere: "globe"
        case .oscilloscope: "waveform.path"
        case .snippet: "waveform"
        case .vectorscope: "scope"
        case .halo: "sun.max"
        case .spectrogram: "square.stack.3d.down.forward"
        case .cymatics: "circle.grid.cross"
        case .flow: "wind"
        }
    }

    /// The "Detail" knob means something mode-specific.
    struct Detail {
        let label: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<VizSettings, Double>
        let format: String
        var isLog = false
    }

    var detail: Detail {
        switch self {
        case .sphere: Detail(label: "Points (= frequency bands)", range: 100...2_000_000, keyPath: \.spherePoints, format: "%.0f", isLog: true)
        case .oscilloscope: Detail(label: "Time window (ms)", range: 5...300, keyPath: \.scopeMs, format: "%.0f ms")
        case .snippet: Detail(label: "Time window (s)", range: 0.5...15, keyPath: \.snippetSeconds, format: "%.1f s")
        case .vectorscope: Detail(label: "Time window (ms)", range: 5...500, keyPath: \.vectorMs, format: "%.0f ms")
        case .halo: Detail(label: "Bands", range: 16...4096, keyPath: \.haloBands, format: "%.0f", isLog: true)
        case .spectrogram: Detail(label: "Bands", range: 64...2048, keyPath: \.spectroBands, format: "%.0f")
        case .cymatics, .flow: Detail(label: "Particles", range: 10_000...4_000_000, keyPath: \.particleCount, format: "%.0f", isLog: true)
        }
    }

    /// Which shared settings affect this mode (others are greyed out in the panel).
    func uses(_ k: Knob) -> Bool {
        switch self {
        case .sphere: return ![.stereo].contains(k)
        // Waveform modes work on raw samples, so the FFT settings don't apply to them.
        case .oscilloscope: return ![.floor, .tilt, .smoothing, .freqRange, .fft].contains(k)
        case .snippet: return ![.floor, .tilt, .smoothing, .freqRange, .motion, .fft].contains(k)
        case .vectorscope: return ![.floor, .tilt, .smoothing, .freqRange, .stereo, .fft].contains(k)
        case .halo: return ![.stereo].contains(k)
        case .spectrogram: return ![.style, .size, .persistence, .zoom, .stereo, .reach].contains(k)
        case .cymatics: return ![.style, .stereo, .mirror, .tilt].contains(k)
        case .flow: return ![.stereo, .mirror].contains(k)
        }
    }

    var hint: String {
        switch self {
        case .sphere: "Each point is a log-spaced frequency band; Layout decides where each frequency sits (and how the globe moves). Mirror puts bass at both ends of the spectrum."
        case .oscilloscope: "Zero-crossing triggered waveform. Stereo splits L/R, Mirror reflects the trace."
        case .snippet: "Rolling waveform of the last few seconds. Colour-by-frequency tints each slice by its bass/treble balance."
        case .vectorscope: "Stereo field (Lissajous): vertical = mono content, horizontal = stereo width."
        case .halo: "Radial spectrum. Mirror makes it symmetric with bass at the bottom."
        case .spectrogram: "Scrolling frequency waterfall. Motion = scroll speed, Mirror puts bass in the centre."
        case .cymatics: "Sand on a vibrating Chladni plate. The dominant pitch picks the plate mode (low → simple figure, high → intricate); loudness and beats shake the sand."
        case .flow: "Particles drifting through curl noise. Each particle listens to one frequency band. Lines style = motion streaks."
        }
    }
}

extension VizSettings {
    /// Modes that build real 3D geometry and apply the camera orbit themselves; the others are tilted as a flat plane.
    var isVolumetric: Bool { mode == .sphere || (mode == .oscilloscope && scopeShape == .ridgeline) }
}

enum Knob { case segmented, style, colorBy, gain, floor, tilt, smoothing, freqRange, size, glow, persistence, motion, zoom, stereo, mirror, fft, reach }

enum SphereLayout: String, Codable, CaseIterable, Identifiable {
    case poles, harmonics, ripples, terrain, cells, timeGlobe
    var id: String { rawValue }
    var title: String {
        switch self {
        case .poles: "Poles"
        case .harmonics: "Harmonics"
        case .ripples: "Ripples"
        case .terrain: "Terrain"
        case .cells: "Cells"
        case .timeGlobe: "Time globe"
        }
    }
    var hint: String {
        switch self {
        case .poles: "Bass at the bottom pole, treble at the top."
        case .harmonics: "The globe morphs into spherical-harmonic shapes: bass drives broad lobes, treble fine ridges."
        case .ripples: "The newest spectrum is born at the top pole and rolls down the globe as a ring; frequency runs around each ring."
        case .terrain: "A smooth noise map: bass fills the valleys, treble the peaks, so the spectrum flows across the surface like contour lines."
        case .cells: "Patches each repeat the full spectrum, bass at their centres."
        case .timeGlobe: "Latitude = frequency, longitude = time. The recent past wraps around the globe."
        }
    }
    /// Layouts that read from the spectrum-history ring.
    var usesHistory: Bool { self == .timeGlobe || self == .ripples }
    /// Shader mode: 0 = static band per point, 1 = time globe, 2 = ripples, 3 = harmonics.
    var shaderMode: UInt32 {
        switch self {
        case .timeGlobe: 1
        case .ripples: 2
        case .harmonics: 3
        default: 0
        }
    }

    /// Saved layouts that no longer exist fall back to Poles instead of resetting every setting.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SphereLayout(rawValue: raw) ?? .poles
    }
}

enum ScopeShape: String, Codable, CaseIterable, Identifiable {
    case line, circle, filled, ridgeline, bloom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .line: "Line"
        case .circle: "Circle"
        case .filled: "Filled"
        case .ridgeline: "Ridges"
        case .bloom: "Bloom"
        }
    }
    var hint: String {
        switch self {
        case .line: "Classic scope trace, triggered on zero crossings so it holds still."
        case .circle: "The trace wrapped around a ring. Stereo puts L outside and R inside."
        case .filled: "Solid area between the trace and the centre line, like a DAW clip zoomed right in."
        case .ridgeline: "Recent traces stacked into a 3D ridge landscape that scrolls back in time. Tilt it with the mouse."
        case .bloom: "The trace mirrored into a rotating kaleidoscope flower (6 petals). Motion spins it."
        }
    }
    init(from decoder: Decoder) throws {
        self = ScopeShape(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .line
    }
}

enum WarpStyle: String, Codable, CaseIterable, Identifiable {
    case tunnel, vortex, ripple, spin, kaleido, implode
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DrawStyle: String, Codable, CaseIterable, Identifiable {
    case points, lines, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ColorBy: String, Codable, CaseIterable, Identifiable {
    case frequency, amplitude
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct VizSettings: Codable, Equatable {
    var mode: VizMode = .sphere
    var style: DrawStyle = .points

    // Color
    var palette: PaletteKind = .phosphor
    var colorBy: ColorBy = .frequency
    var hueShift: Double = 0
    var colorCycle: Double = 0.2

    // Response
    var gain: Double = 1.2
    var floorDB: Double = -80
    var tilt: Double = 3
    var smoothing: Double = 0.7
    var fftSize: Double = 8192
    /// Multi-resolution spectrum: long FFT for bass detail, short FFTs above ~200 Hz for fast reaction.
    var lowLatency: Bool = true
    var minFreq: Double = 30
    var maxFreq: Double = 16_000

    // Shape & motion
    var size: Double = 1
    var glow: Double = 0.5
    var persistence: Double = 0.25
    var motion: Double = 0.3
    var zoom: Double = 1
    /// Global multiplier on how far things move/displace (sphere bulge, spoke length, particle steps, trace height).
    var reach: Double = 1
    var stereo: Bool = false
    var mirror: Bool = false

    // Per-mode detail
    var spherePoints: Double = 20000
    var sphereLayout: SphereLayout = .poles
    var particleCount: Double = 400_000

    // Feedback warp + beat
    var warp: Double = 0
    var warpStyle: WarpStyle = .tunnel
    var beat: Double = 0.5
    var scopeMs: Double = 40
    var scopeShape: ScopeShape = .line
    var snippetSeconds: Double = 4
    var vectorMs: Double = 50
    var haloBands: Double = 160
    var spectroBands: Double = 512

    // Window
    // Screen (CRT treatment)
    var scanlines: Double = 0.5
    var grain: Double = 0.35
    var vignette: Double = 0.6
    var flicker: Double = 0.3
    var segmented: Bool = false

    var bgOpacity: Double = 1
    var bgRed: Double = 0
    var bgGreen: Double = 0
    var bgBlue: Double = 0
    var alwaysOnTop: Bool = false
    var showFPS: Bool = false
}

@Observable
final class SettingsStore {
    private static let key = "AudioViz.settings.v2"
    private static let presetsKey = "AudioViz.presets.v1"
    /// Debug runs (AUDIOVIZ_SETTINGS) never write anything back.
    private static let persist = ProcessInfo.processInfo.environment["AUDIOVIZ_SETTINGS"] == nil

    var s: VizSettings {
        didSet { if s != oldValue { save() } }
    }

    /// Named looks. A preset stores every setting except the window ones (see `windowOnly`).
    private(set) var presets: [String: VizSettings] = [:]
    var presetNames: [String] { presets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    init() {
        s = Self.load()
        presets = Self.loadPresets()
    }

    func resetLook() {
        var d = VizSettings()
        d.mode = s.mode
        d.alwaysOnTop = s.alwaysOnTop
        d.bgOpacity = s.bgOpacity
        s = d
    }

    // MARK: - Presets

    /// Creates or overwrites the preset `name` with the current settings.
    func savePreset(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        presets[n] = s
        savePresets()
    }

    func deletePreset(_ name: String) {
        presets[name] = nil
        savePresets()
    }

    func applyPreset(_ name: String) {
        guard var p = presets[name] else { return }
        Self.keepWindow(from: s, into: &p)
        s = p
    }

    /// True when the current look matches the preset (window settings ignored).
    func matches(_ name: String) -> Bool {
        guard var p = presets[name] else { return false }
        Self.keepWindow(from: s, into: &p)
        return p == s
    }

    /// Window behaviour belongs to the machine, not the look.
    private static func keepWindow(from cur: VizSettings, into p: inout VizSettings) {
        p.alwaysOnTop = cur.alwaysOnTop
        p.showFPS = cur.showFPS
    }

    private func savePresets() {
        guard Self.persist else { return }
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: Self.presetsKey) }
    }

    private static func loadPresets() -> [String: VizSettings] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return [:] }
        return saved.compactMapValues { decodeMerged($0) }
    }

    // MARK: - Current settings

    private func save() {
        guard Self.persist else { return }
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    private static func load() -> VizSettings {
        var saved: [String: Any] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { saved = d }
        // Debug aid: AUDIOVIZ_SETTINGS='{"mode":"cymatics"}' overrides saved values for this run.
        if let json = ProcessInfo.processInfo.environment["AUDIOVIZ_SETTINGS"]?.data(using: .utf8),
           let over = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] {
            saved.merge(over) { _, new in new }
        }
        return decodeMerged(saved) ?? VizSettings()
    }

    /// Merges saved values over defaults so new settings fields never break old saves or presets.
    private static func decodeMerged(_ saved: [String: Any]) -> VizSettings? {
        guard let defData = try? JSONEncoder().encode(VizSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defData)) as? [String: Any] else { return nil }
        merged.merge(saved) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(VizSettings.self, from: data)
    }
}

@Observable
final class AppState {
    var showSettings = false
    var frozen = false
    var status: String?
    /// While a text field is being edited, single-key shortcuts are switched off so typing works.
    var textEditing = false
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored let camera = Camera()
}
