import SwiftUI

/// Scrolling spectrogram waterfall: frequency left→right, newest row on top.
final class SpectroViz: Visualizer {
    private let rows = 360
    private var width = 0
    private var pixels: [UInt8] = []
    private var smoother = Smoother()
    private var acc: Double = 0
    private var image: Image?

    func draw(_ g: inout GraphicsContext, _ rc: RenderContext) {
        let s = rc.s
        let n = Int(s.spectroBands)
        if n != width {
            width = n
            pixels = .init(repeating: 0, count: n * rows * 4)
            image = nil
        }
        let vals = smoother.step(rc.analyzer.bands(count: n, s: s), smoothing: Float(s.smoothing) * 0.6, frozen: rc.frozen)

        if !rc.frozen {
            acc += rc.dt * (15 + s.motion * 200)
            let pushes = min(Int(acc), 8)
            acc -= Double(Int(acc))
            for _ in 0..<pushes { pushRow(vals, rc) }
            if pushes > 0 || image == nil { image = makeImage() }
        }
        guard let image else { return }

        let W = rc.size.width, H = rc.size.height
        if s.mirror {
            var left = g
            left.translateBy(x: W / 2, y: 0)
            left.scaleBy(x: -1, y: 1)
            left.draw(image, in: CGRect(x: 0, y: 0, width: W / 2, height: H))
            g.draw(image, in: CGRect(x: W / 2, y: 0, width: W / 2, height: H))
        } else {
            g.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        }
    }

    private func pushRow(_ vals: [Float], _ rc: RenderContext) {
        let rowBytes = width * 4
        pixels.withUnsafeMutableBytes { buf in
            let p = buf.baseAddress!
            memmove(p + rowBytes, p, rowBytes * (rows - 1))
        }
        for x in 0..<width {
            let v = min(1, vals[x])
            let frac = Float(x) / Float(max(width - 1, 1))
            let t = (rc.s.colorBy == .frequency ? frac * 0.85 + v * 0.15 : v) + rc.phase
            let c = rc.palette.rgb(t)
            let alpha = pow(v, 1.3)
            let o = x * 4
            pixels[o] = UInt8(min(255, c.x * alpha * 255))
            pixels[o + 1] = UInt8(min(255, c.y * alpha * 255))
            pixels[o + 2] = UInt8(min(255, c.z * alpha * 255))
            pixels[o + 3] = UInt8(min(255, alpha * 255))
        }
    }

    private func makeImage() -> Image? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return Image(decorative: cg, scale: 1).interpolation(.medium)
    }
}
