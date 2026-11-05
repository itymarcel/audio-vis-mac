import simd

/// User view transform: orbit (yaw/pitch), pan (points) and zoom.
struct CameraState: Equatable, Codable {
    var yaw: Float = 0
    var pitch: Float = 0
    var pan = SIMD2<Float>()
    var zoom: Float = 1

    var isDefault: Bool { self == CameraState() }

    /// Turntable orbit: spin around the vertical axis, then tilt toward / away from the viewer.
    var rotation: simd_float3x3 {
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let ry = simd_float3x3(rows: [SIMD3(cy, 0, sy), SIMD3(0, 1, 0), SIMD3(-sy, 0, cy)])
        let rx = simd_float3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cp, -sp), SIMD3(0, sp, cp)])
        return rx * ry
    }
}

/// One camera per visualizer mode. Input sets a target; the rendered state eases toward it.
/// Mouse input and rendering both happen on the main thread.
final class Camera {
    private var target: [VizMode: CameraState] = [:]
    private var shown: [VizMode: CameraState] = [:]
    private(set) var mode: VizMode = .sphere

    private static let pitchLimit: Float = 1.45

    func rotate(dx: Float, dy: Float) {
        edit {
            $0.yaw += dx * 0.008
            $0.pitch = min(Self.pitchLimit, max(-Self.pitchLimit, $0.pitch + dy * 0.008))
        }
    }

    func pan(dx: Float, dy: Float) { edit { $0.pan += SIMD2(dx, dy) } }

    /// Zooms by `factor`, keeping the point under the cursor (offset from the window centre, in points) in place.
    func zoom(by factor: Float, around p: SIMD2<Float>) {
        edit {
            let z = min(12, max(0.15, $0.zoom * factor))
            let f = z / $0.zoom
            $0.pan = p - (p - $0.pan) * f
            $0.zoom = z
        }
    }

    /// Re-centres the view (orbit and pan) but keeps the zoom.
    func centre() { edit { $0 = CameraState(zoom: $0.zoom) } }

    /// The view `mode` is heading to (what a preset stores).
    func state(for mode: VizMode) -> CameraState { target[mode] ?? CameraState() }

    /// Glides `mode`'s view to `c` (applying a preset).
    func set(_ c: CameraState, for mode: VizMode) { target[mode] = c }

    /// Advances the eased state for `mode` and returns it.
    func step(_ mode: VizMode, dt: Double) -> CameraState {
        self.mode = mode
        let t = target[mode] ?? CameraState()
        var c = shown[mode] ?? t
        let k = Float(1 - exp(-dt * 18))
        c.yaw += (t.yaw - c.yaw) * k
        c.pitch += (t.pitch - c.pitch) * k
        c.pan += (t.pan - c.pan) * k
        c.zoom *= pow(t.zoom / c.zoom, k)
        if abs(t.yaw - c.yaw) < 1e-4, abs(t.pitch - c.pitch) < 1e-4, simd_length(t.pan - c.pan) < 0.01,
           abs(t.zoom / c.zoom - 1) < 1e-4 { c = t }
        shown[mode] = c
        return c
    }

    private func edit(_ f: (inout CameraState) -> Void) {
        var t = target[mode] ?? CameraState()
        f(&t)
        target[mode] = t
    }
}
