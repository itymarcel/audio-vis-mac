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
2. **Oscilloscope**: a waveform that locks onto zero crossings so it holds still. Shapes: Line, Circle, Filled, Ridges (a 3D landscape of recent traces you can orbit) and Bloom (the waveform folded into a 6-petal kaleidoscope).
3. **Snippet**: a flat rolling waveform of the last few seconds, tinted by its bass/treble balance.
4. **Vectorscope**: a stereo-field Lissajous plot.
5. **Halo**: a radial spectrum around a ring that pulses with the bass.
6. **Spectrogram**: a scrolling frequency waterfall.
7. **Cymatics**: GPU sand on a vibrating Chladni plate. The dominant pitch picks the plate mode (higher pitch → more intricate figure), and loudness and beats shake the sand.
8. **Flow**: up to millions of particles in a curl-noise field. Each particle follows one frequency band; Lines style draws motion streaks.

**Presets** (top of the settings panel): save the current look under a name, pick one to apply it, overwrite or delete it.
Presets store every setting except Always on Top and Show FPS.

**Reach** (Shape & motion) is a global multiplier on how far things move: sphere bulge, halo spoke length, particle steps and trace height.
**Low latency** (Response, on by default): a long FFT reacts late, because an onset only reaches full strength halfway into its window
(~170 ms at 16384). With this on, the long FFT covers only the bass; above ~190 Hz it crossfades to 4096- and 2048-point FFTs,
so a snare registers in ~20 ms instead of ~100 ms. Spectrogram always uses the single long FFT.
FFT size only affects the spectrum modes; Oscilloscope, Snippet and Vectorscope draw raw samples, so it's greyed out there.

All modes share one settings panel (S): palette, colour-by, gain, noise floor, treble tilt, smoothing,
frequency range, size, glow, persistence, motion, zoom, stereo, mirror and a mode-specific "detail".
Settings a mode ignores are greyed out.

View controls (in the window, remembered per mode):
- **Drag**: rotate. The sphere orbits in true 3D; the 2D modes tilt as a plane in perspective.
- **Right-drag, ⌥/⇧-drag or two-finger scroll**: pan.
- **Mouse wheel, pinch or ⌘-scroll**: zoom toward the cursor.
- **Double-click, R or the ↺ HUD button**: reset the view.
- **⌘-drag**: move the window.

Other keys: Space freezes the frame, F toggles full screen, T keeps the window on top. Set Background opacity to 0
to get a see-through overlay.


## Rendering
Everything is drawn on the GPU with Metal, with shaders compiled at runtime, so Xcode isn't needed:
- **Sphere:** up to 2M points, with 6 layouts (Poles, Harmonics, Ripples, Terrain, Cells, Time globe).
- **Cymatics and Flow:** up to 4M particles, simulated in compute kernels.
- **Feedback warp:** MilkDrop-style. The previous frame is fed back through Tunnel, Vortex, Ripple, Spin, Kaleido or Implode, driven by the bass.
- **Beat detection:** finds bass onsets in about 5 ms chunks. Each beat flashes the glow, kicks the sphere and halo outward, bursts the warp and shakes the particles.
- **Effects:** bloom, trails, CRT effects, and a background colour with opacity.

## Debugging
Environment variables (debug runs never save settings):
- `AUDIOVIZ_WAV=/path/file.wav` plays a file into the analyser instead of the system tap (`AUDIOVIZ_WAV_CHUNK=4096` simulates a bursty device).
- `AUDIOVIZ_SETTINGS='{"mode":"oscilloscope","scopeShape":"circle"}'` overrides saved settings for that run.
- `AUDIOVIZ_SNAPSHOT=/tmp/shot AUDIOVIZ_SNAPSHOT_FRAMES=10,240` writes `/tmp/shot-<frame>.png` and quits after the last one.
- `AUDIOVIZ_TRACE=1` prints the audio playhead per frame.
- Show FPS also reports the audio device's burst size and the playhead buffer.
