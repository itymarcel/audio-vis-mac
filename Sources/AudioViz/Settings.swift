import AppKit
import Foundation
import Observation

enum VizMode: String, Codable, CaseIterable, Identifiable {
    case sphere, oscilloscope, snippet, vectorscope, halo, spectrogram
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sphere: "Sphere"
        case .oscilloscope: "Oscilloscope"
        case .snippet: "Snippet"
        case .vectorscope: "Vectorscope"
        case .halo: "Halo"
        case .spectrogram: "Spectrogram"
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
        }
    }

    /// The "Detail" knob means something mode-specific.
    struct Detail {
        let label: String
        let range: ClosedRange<Double>
        let keyPath: WritableKeyPath<VizSettings, Double>
        let format: String
    }

    var detail: Detail {
        switch self {
        case .sphere: Detail(label: "Points (= frequency bands)", range: 100...4000, keyPath: \.spherePoints, format: "%.0f")
        case .oscilloscope: Detail(label: "Time window (ms)", range: 5...200, keyPath: \.scopeMs, format: "%.0f ms")
        case .snippet: Detail(label: "Time window (s)", range: 0.5...15, keyPath: \.snippetSeconds, format: "%.1f s")
        case .vectorscope: Detail(label: "Time window (ms)", range: 5...200, keyPath: \.vectorMs, format: "%.0f ms")
        case .halo: Detail(label: "Bands", range: 16...512, keyPath: \.haloBands, format: "%.0f")
        case .spectrogram: Detail(label: "Bands", range: 64...1024, keyPath: \.spectroBands, format: "%.0f")
        }
    }

    /// Which shared settings affect this mode (others are greyed out in the panel).
    func uses(_ k: Knob) -> Bool {
        switch self {
        case .sphere: return ![.persistence, .stereo].contains(k)
        case .oscilloscope: return ![.floor, .tilt, .smoothing, .freqRange, .motion].contains(k)
        case .snippet: return ![.floor, .tilt, .smoothing, .freqRange, .motion, .persistence].contains(k)
        case .vectorscope: return ![.floor, .tilt, .smoothing, .freqRange, .stereo].contains(k)
        case .halo: return ![.persistence, .stereo].contains(k)
        case .spectrogram: return ![.style, .size, .glow, .persistence, .zoom, .stereo].contains(k)
        }
    }

    var hint: String {
        switch self {
        case .sphere: "Each point on the sphere is one log-spaced frequency band — bass at the bottom pole, treble at the top. Mirror puts bass at both poles."
        case .oscilloscope: "Zero-crossing triggered waveform. Stereo splits L/R into lanes, Mirror reflects the trace."
        case .snippet: "Rolling waveform of the last few seconds. Colour-by-frequency tints each slice by its bass/treble balance."
        case .vectorscope: "Stereo field (Lissajous): vertical = mono content, horizontal = stereo width."
        case .halo: "Radial spectrum. Mirror makes it symmetric with bass at the bottom."
        case .spectrogram: "Scrolling frequency waterfall. Motion = scroll speed, Mirror puts bass in the centre."
        }
    }
}

enum Knob { case style, colorBy, gain, floor, tilt, smoothing, freqRange, size, glow, persistence, motion, zoom, stereo, mirror }

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
    var palette: PaletteKind = .aurora
    var colorBy: ColorBy = .frequency
    var hueShift: Double = 0
    var colorCycle: Double = 0.2

    // Response
    var gain: Double = 1.2
    var floorDB: Double = -80
    var tilt: Double = 3
    var smoothing: Double = 0.7
    var minFreq: Double = 30
    var maxFreq: Double = 16_000

    // Shape & motion
    var size: Double = 1
    var glow: Double = 0.5
    var persistence: Double = 0.3
    var motion: Double = 0.3
    var zoom: Double = 1
    var stereo: Bool = false
    var mirror: Bool = false

    // Per-mode detail
    var spherePoints: Double = 1000
    var scopeMs: Double = 40
    var snippetSeconds: Double = 4
    var vectorMs: Double = 50
    var haloBands: Double = 160
    var spectroBands: Double = 512

    // Window
    var bgOpacity: Double = 1
    var alwaysOnTop: Bool = false
    var showFPS: Bool = false
}

@Observable
final class SettingsStore {
    private static let key = "AudioViz.settings.v1"

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
