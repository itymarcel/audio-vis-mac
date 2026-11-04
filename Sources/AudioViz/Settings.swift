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
        case .oscilloscope: return ![.floor, .tilt, .smoothing, .freqRange, .motion].contains(k)
        case .snippet: return ![.floor, .tilt, .smoothing, .freqRange, .motion].contains(k)
        case .vectorscope: return ![.floor, .tilt, .smoothing, .freqRange, .stereo].contains(k)
        case .halo: return ![.stereo].contains(k)
        case .spectrogram: return ![.style, .size, .persistence, .zoom, .stereo].contains(k)
        case .cymatics: return ![.style, .stereo, .mirror, .tilt].contains(k)
        case .flow: return ![.stereo, .mirror].contains(k)
        }
    }

    var hint: String {
        switch self {
        case .sphere: "Each point is a log-spaced frequency band; Layout decides where each frequency sits (and how the globe moves). Mirror puts bass at both ends of the spectrum."
        case .oscilloscope: "Zero-crossing triggered waveform. Stereo splits L/R into lanes, Mirror reflects the trace."
        case .snippet: "Rolling waveform of the last few seconds. Colour-by-frequency tints each slice by its bass/treble balance."
        case .vectorscope: "Stereo field (Lissajous): vertical = mono content, horizontal = stereo width."
        case .halo: "Radial spectrum. Mirror makes it symmetric with bass at the bottom."
        case .spectrogram: "Scrolling frequency waterfall. Motion = scroll speed, Mirror puts bass in the centre."
        case .cymatics: "Sand on a vibrating plate: 8 Chladni modes mixed by the spectrum (bass → simple, treble → intricate). Beats shake it."
        case .flow: "Particles drifting through curl noise. Each particle listens to one frequency band. Lines style = motion streaks."
        }
    }
}

enum Knob { case segmented, style, colorBy, gain, floor, tilt, smoothing, freqRange, size, glow, persistence, motion, zoom, stereo, mirror }

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
    var minFreq: Double = 30
    var maxFreq: Double = 16_000

    // Shape & motion
    var size: Double = 1
    var glow: Double = 0.5
    var persistence: Double = 0.25
    var motion: Double = 0.3
    var zoom: Double = 1
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

    var s: VizSettings {
        didSet { if s != oldValue { save() } }
    }

    init() { s = Self.load() }

    func resetLook() {
        var d = VizSettings()
        d.mode = s.mode
        d.alwaysOnTop = s.alwaysOnTop
        d.bgOpacity = s.bgOpacity
        s = d
    }

    private func save() {
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Merges saved values over defaults so new settings fields never break old saves.
    private static func load() -> VizSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defData = try? JSONEncoder().encode(VizSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defData)) as? [String: Any]
        else { return VizSettings() }
        merged.merge(saved) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? JSONDecoder().decode(VizSettings.self, from: mergedData)
        else { return VizSettings() }
        return s
    }
}

@Observable
final class AppState {
    var showSettings = false
    var frozen = false
    var status: String?
    @ObservationIgnored weak var window: NSWindow?
}
