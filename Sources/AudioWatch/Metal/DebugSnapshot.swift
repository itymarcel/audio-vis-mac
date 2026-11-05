import AppKit
import Metal

/// Debug aid: with AUDIOWATCH_SNAPSHOT=/path/prefix set, saves the composited frame as PNG at the frame numbers
/// listed in AUDIOWATCH_SNAPSHOT_FRAMES (comma separated, default "60"), then quits after the last one.
enum DebugSnapshot {
    static let prefix = ProcessInfo.processInfo.environment["AUDIOWATCH_SNAPSHOT"]
    static let frames: [Int] = (ProcessInfo.processInfo.environment["AUDIOWATCH_SNAPSHOT_FRAMES"] ?? "60")
        .split(separator: ",").compactMap { Int($0) }
    static var enabled: Bool { prefix != nil }

    static func capture(_ tex: MTLTexture, frame: Int, cmd: MTLCommandBuffer, device: MTLDevice) {
        guard let prefix, frames.contains(frame) else { return }
        let w = tex.width, h = tex.height
        guard let dst = device.makeBuffer(length: w * h * 4, options: .storageModeShared),
              let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: dst, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
        blit.endEncoding()
        let last = frame == frames.max()
        cmd.addCompletedHandler { _ in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            // The buffer outlives the context, so its memory stays valid while the image is made.
            if let ctx = CGContext(data: dst.contents(), width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: cs, bitmapInfo: info),
               let img = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: img)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(frame).png"))
            }
            if last { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
    }
}

extension DebugSnapshot {
    /// Debug aid: AUDIOWATCH_NODES_SNAPSHOT=/path.png opens the Nodes window and saves a picture of it after ~3 s.
    static let nodesPath = ProcessInfo.processInfo.environment["AUDIOWATCH_NODES_SNAPSHOT"]

    static func captureWindow(_ view: NSView) {
        guard let nodesPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: nodesPath))
        }
    }
}
