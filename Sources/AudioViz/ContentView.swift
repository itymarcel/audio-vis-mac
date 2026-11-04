import AppKit
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
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    engine.render(&ctx, size: size, date: timeline.date, settings: store.s, frozen: app.frozen)
                }
            }
            .ignoresSafeArea()

            if hudVisible || hudHovered {
                HUD(store: store, app: app)
                    .padding(.top, 10)
                    .onHover { hudHovered = $0 }
                    .transition(.opacity)
            }

            if let status = app.status {
                VStack {
                    Spacer()
                    Text(status)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        .padding(20)
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
                .inspectorColumnWidth(min: 270, ideal: 310, max: 420)
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

/// Floating mode switcher that fades out when the mouse is idle.
struct HUD: View {
    @Bindable var store: SettingsStore
    @Bindable var app: AppState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(VizMode.allCases.enumerated()), id: \.element) { i, mode in
                Button { store.s.mode = mode } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 28)
                        .background(store.s.mode == mode ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("\(mode.title)  (\(i + 1))")
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            Button { app.frozen.toggle() } label: {
                Image(systemName: app.frozen ? "play.fill" : "pause.fill").frame(width: 30, height: 28)
            }
            .buttonStyle(.plain).help("Freeze frame (Space)")
            Button { app.showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 30, height: 28)
            }
            .buttonStyle(.plain).help("Settings (S)")
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}
