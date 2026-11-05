import AppKit
import SwiftUI

/// Compact native settings panel.
struct SettingsPanel: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState

    private var mode: VizMode { store.s.mode }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $store.s.mode) {
                    ForEach(VizMode.stable) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    Divider()
                    ForEach(VizMode.experimental) { Label("\($0.title) (experimental)", systemImage: $0.symbol).tag($0) }
                }
                if mode == .sphere {
                    Picker("Layout", selection: $store.s.sphereLayout) {
                        ForEach(SphereLayout.allCases) { Text($0.title).tag($0) }
                    }
                    Hint(store.s.sphereLayout.hint)
                } else if mode == .oscilloscope {
                    Picker("Shape", selection: $store.s.scopeShape) {
                        ForEach(ScopeShape.allCases) { Text($0.title).tag($0) }
                    }
                    Hint(store.s.scopeShape.hint)
                } else {
                    Hint(mode.hint)
                }
                if mode.uses(.style) {
                    Picker("Style", selection: $store.s.style) {
                        ForEach(DrawStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode.usesLook {
                    Picker("Render", selection: $store.s.look) {
                        ForEach(SurfaceLook.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Lines: wireframe outlines. Shaded: solid, lit surfaces. Fresnel: glassy, glowing rims.")
                }
                detailRow
                if mode == .field {
                    SliderRow("Springiness", $store.s.fieldSpring, 0...1, "%.2f")
                        .help("How strongly particles are pulled back to their home spot. Low = slow, lazy return; high = snappy.")
                }
            }

            PresetSection(store: store, app: app)

            Section("Colour") {
                Picker("Palette", selection: $store.s.palette) {
                    ForEach(PaletteKind.allCases) { p in
                        HStack { PaletteSwatch(palette: p.palette); Text(p.title) }.tag(p)
                    }
                }
                Picker("Colour by", selection: $store.s.colorBy) {
                    ForEach(ColorBy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .knob(.colorBy, mode)
                SliderRow("Offset", $store.s.hueShift, 0...2, "%.2f")
                SliderRow("Cycling", $store.s.colorCycle, 0...2, "%.2f")
            }

            Section("Response") {
                Picker("FFT size", selection: $store.s.fftSize) {
                    ForEach([2048.0, 4096, 8192, 16384, 32768], id: \.self) { Text("\(Int($0))").tag($0) }
                }
                .help("Bigger = finer frequency detail (good for huge point counts), slower response. Waveform modes don't use the FFT.")
                .knob(.fft, mode)
                Toggle("Low latency", isOn: $store.s.lowLatency)
                    .knob(.fft, mode)
                    .disabled(!mode.supportsLowLatency)
                    .help(mode.supportsLowLatency
                          ? "Above ~200 Hz use short FFTs, so drums and vocals react within ~20 ms. The FFT size then only sets the bass detail."
                          : "Not used here: this mode's look depends on the full FFT's fine frequency detail.")
                SliderRow("Gain", $store.s.gain, 0.2...5, "%.2f×").knob(.gain, mode)
                SliderRow("Floor", $store.s.floorDB, -120...(-30), "%.0f dB").knob(.floor, mode)
                SliderRow("Tilt", $store.s.tilt, 0...6, "%.1f dB").knob(.tilt, mode)
                SliderRow("Smoothing", $store.s.smoothing, 0...0.97) { Self.fallLabel(store.s.smoothing) }
                    .knob(.smoothing, mode)
                    .help("How slowly levels fall back after a hit. Rises are always instant.")
                SliderRow("Low freq", logBinding(\.minFreq), log10(20)...log10(1000)) { hz(store.s.minFreq) }
                    .knob(.freqRange, mode)
                SliderRow("High freq", logBinding(\.maxFreq), log10(1500)...log10(22000)) { hz(store.s.maxFreq) }
                    .knob(.freqRange, mode)
            }

            Section("Shape & motion") {
                SliderRow("Size", $store.s.size, 0.2...4, "%.2f").knob(.size, mode)
                SliderRow("Glow", $store.s.glow, 0...1, "%.2f").knob(.glow, mode)
                SliderRow("Trails", $store.s.persistence, 0...1, "%.2f").knob(.persistence, mode)
                SliderRow("Motion", $store.s.motion, 0...2, "%.2f").knob(.motion, mode)
                SliderRow("Zoom", $store.s.zoom, 0.3...2.5, "%.2f×").knob(.zoom, mode)
                SliderRow("Reach", $store.s.reach, 0...4, "%.2f×").knob(.reach, mode)
                    .help("How far things travel: sphere bulge, spoke length, particle steps, trace height.")
                HStack {
                    Toggle("Stereo", isOn: $store.s.stereo).knob(.stereo, mode)
                    Toggle("Mirror", isOn: $store.s.mirror).knob(.mirror, mode)
                    Toggle("Segmented", isOn: $store.s.segmented).knob(.segmented, mode)
                }
            }

            Section("Feedback & beat") {
                Picker("Warp", selection: $store.s.warpStyle) {
                    ForEach(WarpStyle.allCases) { Text($0.title).tag($0) }
                }
                .knob(.persistence, mode)
                SliderRow("Warp amt", $store.s.warp, 0...1, "%.2f").knob(.persistence, mode)
                SliderRow("Beat", $store.s.beat, 0...1.5, "%.2f")
                Hint("Warp feeds the previous frame back through a zoom/spin/swirl driven by bass. Beat = how hard detected kicks punch the image.")
            }

            Section("Screen") {
                SliderRow("Scanlines", $store.s.scanlines, 0...1, "%.2f")
                SliderRow("Grain", $store.s.grain, 0...1, "%.2f")
                SliderRow("Vignette", $store.s.vignette, 0...1, "%.2f")
                SliderRow("Flicker", $store.s.flicker, 0...1, "%.2f")
            }

            Section("Window") {
                ColorPicker("Background", selection: bgColor, supportsOpacity: false)
                SliderRow("Opacity", $store.s.bgOpacity, 0...1, "%.2f")
                HStack {
                    Toggle("Always on top", isOn: $store.s.alwaysOnTop)
                    Toggle("Show FPS", isOn: $store.s.showFPS)
                }
            }

            Section {
                Button("Reset look") { store.resetLook() }
                Hint("1–8 modes · S settings · Space freeze · F full screen · T on top · R reset view")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.checkbox)
        .controlSize(.mini)
        .font(.system(size: 11))
    }

    @ViewBuilder private var detailRow: some View {
        let d = mode.detail
        let short = d.label.components(separatedBy: " (").first ?? d.label
        if d.isLog {
            SliderRow(short, Binding(
                get: { log10(store.s[keyPath: d.keyPath]) },
                set: { store.s[keyPath: d.keyPath] = Self.niceRound(pow(10, $0)) }
            ), log10(d.range.lowerBound)...log10(d.range.upperBound)) { Self.compact(store.s[keyPath: d.keyPath]) }
        } else {
            SliderRow(short, Binding(
                get: { store.s[keyPath: d.keyPath] },
                set: { store.s[keyPath: d.keyPath] = $0.rounded(toPlaces: d.range.upperBound > 50 ? 0 : 1) }
            ), d.range, d.format)
        }
    }

    /// Rounds to 2 significant digits so log sliders land on clean numbers.
    static func niceRound(_ v: Double) -> Double {
        let mag = pow(10, floor(log10(max(v, 1))) - 1)
        return (v / mag).rounded() * mag
    }

    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))"
    }

    static func compact(_ v: Double) -> String {
        v >= 1_000_000 ? String(format: "%.1fM", v / 1_000_000) : v >= 10_000 ? String(format: "%.0fk", v / 1000) : String(format: "%.0f", v)
    }

    private var bgColor: Binding<Color> {
        Binding(
            get: { Color(.sRGB, red: store.s.bgRed, green: store.s.bgGreen, blue: store.s.bgBlue) },
            set: { c in
                guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return }
                store.s.bgRed = Double(ns.redComponent)
                store.s.bgGreen = Double(ns.greenComponent)
                store.s.bgBlue = Double(ns.blueComponent)
            })
    }

    private func logBinding(_ kp: WritableKeyPath<VizSettings, Double>) -> Binding<Double> {
        Binding(get: { log10(store.s[keyPath: kp]) }, set: { store.s[keyPath: kp] = pow(10, $0).rounded() })
    }

    /// Fall time to ~10 % (2.3 time constants), e.g. "60 ms" / "1.2 s".
    static func fallLabel(_ smoothing: Double) -> String {
        let t = Envelope.fallTau(smoothing) * 2.3
        return t < 1 ? String(format: "%.0f ms", t * 1000) : String(format: "%.1f s", t)
    }

    private func hz(_ f: Double) -> String {
        f >= 1000 ? String(format: "%.1fk", f / 1000) : String(format: "%.0f", f)
    }
}

/// One-line slider: label · slider · value.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var label: (() -> String)?

    init(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String = "", label: (() -> String)? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1).frame(width: 64, alignment: .leading)
            Slider(value: $value, in: range).labelsHidden()
            Text(label?() ?? String(format: format, value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct PaletteSwatch: View {
    let palette: Palette
    var body: some View {
        LinearGradient(gradient: palette.gradient(0, 1, steps: 8), startPoint: .leading, endPoint: .trailing)
            .frame(width: 28, height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

extension View {
    /// Greys out settings that don't affect the current mode.
    func knob(_ k: Knob, _ mode: VizMode) -> some View {
        let on = mode.uses(k)
        return disabled(!on).opacity(on ? 1 : 0.4)
    }
}

extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p))
        return (self * m).rounded() / m
    }
}

/// Named looks: pick to apply, Save As… a new name, overwrite the selected one, delete it.
struct PresetSection: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState
    @State private var selected = ""
    @State private var naming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        Section("Presets") {
            if store.presetNames.isEmpty {
                Hint("No presets yet. Save As… stores the current look under a name.")
            } else {
                Picker("Preset", selection: $selected) {
                    Text("None").tag("")
                    ForEach(store.presetNames, id: \.self) { name in
                        Text(name == selected && !store.matches(name) ? "\(name) (edited)" : name).tag(name)
                    }
                }
                .onChange(of: selected) { _, name in
                    guard !name.isEmpty else { return }
                    if let cam = store.applyPreset(name) { app.camera.set(cam, for: store.s.mode) }
                }
            }
            HStack(spacing: 8) {
                Button("Save As…") {
                    newName = selected
                    naming = true
                }
                Button("Overwrite") { store.savePreset(selected, camera: app.camera.state(for: store.s.mode)) }
                    .disabled(selected.isEmpty)
                    .help("Save the current look and camera view into the selected preset")
                Button("Delete") { confirmDelete = true }
                    .disabled(selected.isEmpty)
                Spacer()
            }
            .buttonStyle(.bordered)
            // Presentation modifiers live on this single row (not the Section) so they attach exactly once.
            .alert("Save Preset", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Save") { saveNew() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves the current look and camera view. Using an existing name replaces that preset.")
            }
            .confirmationDialog("Delete preset \u{201C}\(selected)\u{201D}?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    store.deletePreset(selected)
                    selected = ""
                }
            }
            // Single-key shortcuts (S, F, Space…) would swallow typing while the name dialog is open.
            .onChange(of: naming) { _, open in app.textEditing = open }
        }
        .onAppear {
            if selected.isEmpty, let match = store.presetNames.first(where: { store.matches($0) }) { selected = match }
        }
    }

    private func saveNew() {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        store.savePreset(n, camera: app.camera.state(for: store.s.mode))
        selected = n
    }
}
