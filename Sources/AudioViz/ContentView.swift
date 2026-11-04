import AppKit
import MetalKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState
    let engine: VizEngine

    @State private var hudVisible = true
    @State private var hudHovered = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            MetalVizView(store: store, app: app, engine: engine)
                .ignoresSafeArea()

            if hudVisible || hudHovered {
                HUD(store: store, app: app)
                    .padding(.top, 10)
                    .onHover { hudHovered = $0 }
                    .transition(.opacity)
            }

            if store.s.showFPS {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(String(format: "%.0f fps", engine.fps))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(10)
                .allowsHitTesting(false)
            }

            if let status = app.status {
                VStack {
                    Spacer()
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 56).padding(.horizontal, 30)
                }
                .allowsHitTesting(false)
            }
        }
        .background(WindowAccessor { window in
            app.window = window
            configure(window)
        })
        .onContinuousHover { phase in
            if case .active = phase { pokeHUD() }
        }
        .inspector(isPresented: $app.showSettings) {
            SettingsPanel(store: store, app: app)
                .inspectorColumnWidth(min: 230, ideal: 260, max: 360)
        }
        .onChange(of: store.s.alwaysOnTop) { _, onTop in
            app.window?.level = onTop ? .floating : .normal
        }
        .onAppear {
            engine.start(app: app)
            pokeHUD()
        }
    }

    private func configure(_ w: NSWindow) {
        w.isOpaque = false
        w.backgroundColor = .clear
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.level = store.s.alwaysOnTop ? .floating : .normal
    }

    private func pokeHUD() {
        if !hudVisible { withAnimation(.easeOut(duration: 0.2)) { hudVisible = true } }
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { hudVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}

/// Hosts the Metal view; the renderer pulls settings each frame (no SwiftUI redraws involved).
struct MetalVizView: NSViewRepresentable {
    let store: SettingsStore
    let app: AppState
    let engine: VizEngine

    final class Coordinator { var renderer: Renderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let v = DraggableMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.preferredFramesPerSecond = 120
        v.clearColor = MTLClearColorMake(0, 0, 0, 0)
        v.layer?.isOpaque = false
        context.coordinator.renderer = Renderer(view: v, store: store, app: app, engine: engine)
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}

final class DraggableMTKView: MTKView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }
}

/// Small native toolbar that fades out when the mouse is idle.
struct HUD: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState

    var body: some View {
        HStack(spacing: 6) {
            Picker("Mode", selection: $store.s.mode) {
                ForEach(VizMode.allCases) { m in Image(systemName: m.symbol).help(m.title).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { app.frozen.toggle() } label: {
                Image(systemName: app.frozen ? "play.fill" : "pause.fill").frame(width: 14)
            }
            .help("Freeze (Space)")
            Button { app.showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 14)
            }
            .help("Settings (S)")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}
