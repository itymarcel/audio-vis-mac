import SwiftUI
import simd

enum PaletteKind: String, Codable, CaseIterable, Identifiable {
    case aurora, neon, fire, ocean, sunset, acid, rainbow, mono
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var palette: Palette {
        switch self {
        case .aurora: Palette([0x0B3D91, 0x00C2A8, 0x7CFFB2, 0xB47CFF, 0xFF5FA2])
        case .neon: Palette([0xFF00C8, 0x8A2BFF, 0x00E5FF, 0x39FF14])
        case .fire: Palette([0x4A0000, 0xC01800, 0xFF6A00, 0xFFC400, 0xFFF6D0])
        case .ocean: Palette([0x021B4D, 0x0050A0, 0x00A6D6, 0x7FE7F2, 0xE8FFFF])
        case .sunset: Palette([0x2D0B59, 0x8E1E7A, 0xE8475C, 0xFF9A3C, 0xFFE07A])
        case .acid: Palette([0x0A3D00, 0x58D600, 0xE6FF00, 0xFFFFFF])
        case .rainbow: Palette([0xFF2D2D, 0xFFA21F, 0xF5F52A, 0x2BE36B, 0x26C6FF, 0x5A4BFF, 0xD13BFF])
        case .mono: Palette([0x5A6270, 0xC8D0DC, 0xFFFFFF])
        }
    }
}

struct Palette {
    let stops: [SIMD3<Float>]

    init(_ hex: [UInt32]) {
        stops = hex.map {
            SIMD3(Float(($0 >> 16) & 0xFF) / 255, Float(($0 >> 8) & 0xFF) / 255, Float($0 & 0xFF) / 255)
        }
    }

    /// Maps any t onto 0…1 by bouncing back and forth, so cycling stays smooth.
    @inline(__always) static func pingPong(_ t: Float) -> Float {
        let m = t - 2 * floor(t / 2)
        return m <= 1 ? m : 2 - m
    }

    func rgb(_ t: Float) -> SIMD3<Float> {
        let u = Palette.pingPong(t) * Float(stops.count - 1)
        let i = min(Int(u), stops.count - 2)
        let f = u - Float(i)
        return stops[i] + (stops[i + 1] - stops[i]) * f
    }

    func color(_ t: Float, _ alpha: Double = 1) -> Color {
        let c = rgb(t)
        return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: alpha)
    }

    func gradient(_ t0: Float, _ t1: Float, steps: Int = 12) -> Gradient {
        Gradient(stops: (0...steps).map { i in
            let f = Float(i) / Float(steps)
            return .init(color: color(t0 + (t1 - t0) * f), location: CGFloat(f))
        })
    }
}

/// Groups shapes by quantized (colour, alpha) so thousands of dots become a few dozen draw calls.
struct Batch {
    static let tLevels = 64
    static let aLevels = 16
    private(set) var paths: [Int: Path] = [:]

    mutating func add(_ t: Float, _ alpha: Float, _ build: (inout Path) -> Void) {
        let ai = Int(min(max(alpha, 0), 1) * Float(Batch.aLevels - 1) + 0.5)
        guard ai > 0 else { return }
        let ti = Int(Palette.pingPong(t) * Float(Batch.tLevels - 1) + 0.5)
        build(&paths[ti * Batch.aLevels + ai, default: Path()])
    }

    private func decode(_ k: Int) -> (Float, Double) {
        (Float(k / Batch.aLevels) / Float(Batch.tLevels - 1), Double(k % Batch.aLevels) / Double(Batch.aLevels - 1))
    }

    func fill(_ g: inout GraphicsContext, _ p: Palette, alpha: Double = 1) {
        for (k, path) in paths {
            let (t, a) = decode(k)
            g.fill(path, with: .color(p.color(t, a * alpha)))
        }
    }

    func stroke(_ g: inout GraphicsContext, _ p: Palette, width: CGFloat, alpha: Double = 1) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        for (k, path) in paths {
            let (t, a) = decode(k)
            g.stroke(path, with: .color(p.color(t, a * alpha)), style: style)
        }
    }
}

/// Fast attack, configurable release.
struct Smoother {
    private(set) var v: [Float] = []

    mutating func step(_ x: [Float], smoothing: Float, frozen: Bool) -> [Float] {
        if v.count != x.count { v = x; return v }
        if frozen { return v }
        let release = min(smoothing, 0.98), attack = release * 0.35
        for i in x.indices {
            let k = x[i] > v[i] ? attack : release
            v[i] = v[i] * k + x[i] * (1 - k)
        }
        return v
    }
}

struct RenderContext {
    let size: CGSize
    let s: VizSettings
    let time: Double
    let dt: Double
    let frozen: Bool
    let analyzer: Analyzer
    let palette: Palette
    /// Palette offset (hue shift + colour cycling)
    let phase: Float

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var minDim: CGFloat { min(size.width, size.height) }
    /// Base line width / dot size scaled to the window.
    var unit: CGFloat { max(0.5, CGFloat(s.size) * minDim / 600) }
}

protocol Visualizer: AnyObject {
    func draw(_ g: inout GraphicsContext, _ rc: RenderContext)
}
