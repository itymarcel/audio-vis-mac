# AudioViz

A native macOS visualizer for whatever your Mac is playing, on any output device.
It uses a Core Audio global process tap (macOS 14.2+), so no virtual audio driver is needed and the audio itself is never changed.

## Build & run
    ./build.sh
    open build/AudioViz.app

The first time it runs, allow **System Audio Recording** (System Settings › Privacy & Security ›
Screen & System Audio Recording). The app is ad-hoc signed, so after a rebuild macOS may ask for this permission again.

## Modes (keys 1–8)
1. **Sphere**: N points on a Fibonacci sphere (default 1000), one log-spaced frequency band each, bass at the bottom pole.
2. **Oscilloscope**: a waveform that locks onto zero crossings so it holds still.
3. **Snippet**: a flat rolling waveform of the last few seconds, tinted by its bass/treble balance.
4. **Vectorscope**: a stereo-field Lissajous plot.
5. **Halo**: a radial spectrum around a ring that pulses with the bass.
6. **Spectrogram**: a scrolling frequency waterfall.
7. **Cymatics**: GPU sand on a vibrating Chladni plate. 8 plate modes are mixed live by the spectrum, and beats shake the sand.
8. **Flow**: up to millions of particles in a curl-noise field. Each particle follows one frequency band; Lines style draws motion streaks.

All modes share one settings panel (S): palette, colour-by, gain, noise floor, treble tilt, smoothing,
frequency range, size, glow, persistence, motion, zoom, stereo, mirror and a mode-specific "detail".
Settings a mode ignores are greyed out.

Other keys: Space freezes the frame, F toggles full screen, T keeps the window on top. Set Background opacity to 0
to get a see-through overlay.


## Rendering
Everything is drawn on the GPU with Metal, with shaders compiled at runtime, so Xcode isn't needed:
- **Sphere:** up to 2M points, with 6 layouts (Poles, Harmonics, Ripples, Terrain, Cells, Time globe).
- **Cymatics and Flow:** up to 4M particles, simulated in compute kernels.
- **Feedback warp:** MilkDrop-style. The previous frame is fed back through Tunnel, Vortex, Ripple, Spin, Kaleido or Implode, driven by the bass.
- **Beat detection:** finds bass onsets in about 5 ms chunks. Each beat flashes the glow, kicks the sphere and halo outward, bursts the warp and shakes the particles.
- **Effects:** bloom, trails, CRT effects, and a background colour with opacity.
