import SwiftUI

struct SettingsPanel: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState

    private var mode: VizMode { store.s.mode }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $store.s.mode) {
                    ForEach(VizMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Text(mode.hint).font(.caption).foregroundStyle(.secondary)
                Picker("Style", selection: $store.s.style) {
                    ForEach(DrawStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .knob(.style, mode)
                let d = mode.detail
                SliderRow(title: d.label, value: Binding(
                    get: { store.s[keyPath: d.keyPath] },
                    set: { store.s[keyPath: d.keyPath] = $0.rounded(toPlaces: d.range.upperBound > 50 ? 0 : 1) }
                ), range: d.range, format: d.format)
            } header: { Text("Mode") }

            Section("Colour") {
                Picker("Palette", selection: $store.s.palette) {
                    ForEach(PaletteKind.allCases) { p in
                        HStack {
                            PaletteSwatch(palette: p.palette)
                            Text(p.title)
                        }.tag(p)
                    }
                }
                Picker("Colour by", selection: $store.s.colorBy) {
                    ForEach(ColorBy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .knob(.colorBy, mode)
                SliderRow(title: "Palette offset", value: $store.s.hueShift, range: 0...2, format: "%.2f")
                SliderRow(title: "Colour cycling", value: $store.s.colorCycle, range: 0...2, format: "%.2f")
            }

            Section("Response") {
                SliderRow(title: "Gain / sensitivity", value: $store.s.gain, range: 0.2...5, format: "%.2f×")
                    .knob(.gain, mode)
                SliderRow(title: "Noise floor", value: $store.s.floorDB, range: -120...(-30), format: "%.0f dB")
                    .knob(.floor, mode)
                SliderRow(title: "Treble tilt", value: $store.s.tilt, range: 0...6, format: "%.1f dB/oct")
                    .knob(.tilt, mode)
                SliderRow(title: "Smoothing", value: $store.s.smoothing, range: 0...0.97, format: "%.2f")
                    .knob(.smoothing, mode)
                SliderRow(title: "Lowest frequency", value: logBinding(\.minFreq), range: log10(20)...log10(1000), format: "") {
                    hz(store.s.minFreq)
                }
                .knob(.freqRange, mode)
                SliderRow(title: "Highest frequency", value: logBinding(\.maxFreq), range: log10(1500)...log10(22000), format: "") {
                    hz(store.s.maxFreq)
                }
                .knob(.freqRange, mode)
            }

            Section("Shape & Motion") {
                SliderRow(title: "Size / thickness", value: $store.s.size, range: 0.2...4, format: "%.2f").knob(.size, mode)
                SliderRow(title: "Glow", value: $store.s.glow, range: 0...1, format: "%.2f").knob(.glow, mode)
                SliderRow(title: "Persistence (trails)", value: $store.s.persistence, range: 0...1, format: "%.2f").knob(.persistence, mode)
                SliderRow(title: "Motion (rotation / scroll)", value: $store.s.motion, range: 0...2, format: "%.2f").knob(.motion, mode)
                SliderRow(title: "Zoom", value: $store.s.zoom, range: 0.3...2.5, format: "%.2f×").knob(.zoom, mode)
                Toggle("Stereo (split L / R)", isOn: $store.s.stereo).knob(.stereo, mode)
                Toggle("Mirror / symmetric", isOn: $store.s.mirror).knob(.mirror, mode)
            }

            Section("Window") {
                SliderRow(title: "Background opacity", value: $store.s.bgOpacity, range: 0...1, format: "%.2f")
                Toggle("Always on top (T)", isOn: $store.s.alwaysOnTop)
                Toggle("Show FPS", isOn: $store.s.showFPS)
            }

            Section {
                Button("Reset look to defaults") { store.resetLook() }
                Text("Keys: 1–6 modes · S settings · Space freeze · F full screen · T always on top. Drag anywhere to move the window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func logBinding(_ kp: WritableKeyPath<VizSettings, Double>) -> Binding<Double> {
        Binding(get: { log10(store.s[keyPath: kp]) }, set: { store.s[keyPath: kp] = pow(10, $0).rounded() })
    }

    private func hz(_ f: Double) -> String {
        f >= 1000 ? String(format: "%.1f kHz", f / 1000) : String(format: "%.0f Hz", f)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var label: (() -> String)?

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, label: (() -> String)? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(label?() ?? String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).labelsHidden().controlSize(.small)
        }
    }
}

struct PaletteSwatch: View {
    let palette: Palette
    var body: some View {
        LinearGradient(gradient: palette.gradient(0, 1, steps: 8), startPoint: .leading, endPoint: .trailing)
            .frame(width: 36, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
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
