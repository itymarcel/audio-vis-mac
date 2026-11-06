# AudioWatch

A native macOS visualizer for whatever your Mac is playing, on any output device.
It uses a Core Audio global process tap (macOS 14.2+), so no virtual audio driver is needed and the audio itself is never changed.

## Build & run
    ./build.sh
    open build/AudioWatch.app

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

**Experimental** (the flask button in the toolbar, Visualizer › Experimental, or the bottom of the Mode picker):
- **Attractor**: delay embedding (Takens). The waveform is drawn as the 3D curve (x(t), x(t−τ), x(t−2τ)), with τ a quarter period of the dominant pitch. A pure tone traces a ring, a chord a knot, noise a cloud. Drag to orbit.
- **Harmonograph**: a 3D harmonograph: lateral pendulums on x, y and z plus a rotary table, each a damped oscillator tuned to a note being played. Just intervals draw calm closed figures, tempered ones precess, clashing notes fill in. Swings (2–10) sets how long the pendulums run.
- **Drumhead**: a circular drum skin in 3D. Each band drives one of the membrane's Bessel modes, J_m(j_mn·r)·cos(mθ), each oscillating at its own drum-frequency ratio.
- **Primitives**: 3D primitives conjured by the music. Kicks bring spheres, tori, octahedra and helices; snares cubes, pyramids, planes and nested frames; hats rays, crosses and barcodes. **Render**: Lines strokes each one in edge by edge; Shaded draws lit solid surfaces; Fresnel draws glassy shapes with glowing rims. Detail = density.
- **Field**: a box of particles at rest, each on a spring to its home spot. Invisible spheres of different sizes and masses appear with the music (kicks: big and heavy, hats: small and brief); particles are pulled toward them but can't enter, so they pile up into shells that reveal the spheres, then drift home when a sphere vanishes. **Springiness** sets how hard they pull back.
- **Mushrooms**: up to 150 glowing mushrooms, from giants (sprouted by kicks) to tiny buttons (hats). Each grows slowly, in small eased steps on the hits in its own frequency range (big ones on kicks, medium on snares, tiny on hats), glows gently with its band, puffs spores on beats, then wilts and fades. All motion is eased or spring-smoothed. **Render**: Lines, Shaded or Fresnel.

All experimental modes are 3D: drag to orbit, scroll to zoom. The Style control only shows for modes it applies to.

**Presets** (top of the settings panel): save the current look under a name, pick one to apply it, overwrite or delete it.
Presets store every setting except Always on Top and Show FPS, plus the camera view (rotation, pan, zoom).

**Reach** (Shape & motion) multiplies how far things move: sphere bulge, halo spoke length, particle steps and trace height. It is remembered per mode.
**Low latency** (Response, on by default): a long FFT reacts late, because an onset only reaches full strength halfway into its window
(~170 ms at 16384). With this on, the long FFT covers only the bass; above ~190 Hz it crossfades to 4096- and 2048-point FFTs,
so a snare registers in ~20 ms instead of ~100 ms. Spectrogram and Flow always use the single long FFT (their look comes from its fine detail).
FFT size only affects the spectrum modes; Oscilloscope, Snippet and Vectorscope draw raw samples, so it's greyed out there.

All modes share one settings panel (S): palette, colour-by, gain, noise floor, treble tilt, smoothing,
frequency range, size, glow, persistence, motion, zoom, stereo, mirror and a mode-specific "detail".
Settings a mode ignores are greyed out.

View controls (in the window, remembered per mode):
- **Drag**: rotate. The sphere orbits in true 3D; the 2D modes tilt as a plane in perspective.
- **Right-drag, ⌥/⇧-drag or two-finger scroll**: pan.
- **Mouse wheel, pinch or ⌘-scroll**: zoom toward the cursor.
- **Double-click, R or the ↺ HUD button**: centre the view (rotation and pan); the zoom is kept.
- **⌘-drag**: move the window.

Other keys: Space freezes the frame, F toggles full screen, T keeps the window on top. Set Background opacity to 0
to get a see-through overlay.


## Post-processing & media layer (Settings)

**Post-processing** grades the final image: Brightness, Contrast (a curve that keeps black black, so transparent windows stay clear), Saturation, Hue, Chromatic aberration, Pixelate, Posterize and Invert.

**Media layer**: choose an image or a video (videos loop, muted, with a Speed control). *Blend*: Behind, Add, Screen, Overlay, Multiply, Mask (visuals only show where the media is bright), Difference, or Hidden. *Fit*: Fill, Fit, Stretch. *Opacity*, *Blur* (also smooths the Displace warp), *Beat pulse* (beats flash the opacity) and *Displace* (warps the visuals with the media as a map: edges push sideways, bright parts push outward; works with Hidden too). The file path is stored, so presets remember their media.

**Media transform**: Scale, X, Y, Rotate, Tile (Off / Repeat / Mirror, mirror hides the seams) and Kaleido (fold into 2–16 mirrored segments).
**Media motion**: Drift (steady scroll in a Direction; endless with Tile), Spin, Wander (slow Ken Burns pan / zoom / tilt), Beat zoom (beats punch the media in), Breathe (scale follows the bass), Shake (snares and hats jolt it off-centre, it wobbles back), Beat jump (chance per beat of a cut: a video jumps to a random moment, a picture to a new spot and orientation).

All of these sliders are also targets in the Nodes window.

## Nodes (N, or the HUD's node button)

A separate window with a node editor that connects the music to any setting. Right-click the dotted grid to add a node, drag from a node's output (right dot) to another node's input (left dot), drag a connected input away to unplug or re-route it. Drag a header to move a node, drag the background to pan, select a node and press ⌫ to delete it (or right-click it: Duplicate / Disconnect / Delete). Numbers are scrubbed by dragging sideways (⌥ = fine); double-click one to type a value (Enter commits, Escape cancels). Constant and Map range use plain number boxes with no limits. Each node shows its live output value and a level bar.

- **Music**: Bass, Mids, Highs or any frequency band, Loudness, Beat, Kick / Snare / Hats hit (with decay), Pitch, Brightness.
- **Generators**: LFO (sine, triangle, saw, square), Random (with glide), Constant.
- **Modifiers**: Map range, Smooth (separate rise and fall), Curve, Invert, Threshold, Steps, Math (+, −, ×, min, max, mix), Accumulate (turns a level into steady motion, e.g. continuous spinning), Sample & hold.
- **Parameter** (output): drives a setting. *Add* puts input × amount × the setting's range on top of its slider value; *Set* lets the input (0 … 1) span the whole range. Targets: response (gain, floor, tilt, smoothing, frequency range), shape & motion (size, glow, trails, motion, zoom, reach), colour, warp, beat, camera (orbit spin, orbit tilt, zoom), per-mode knobs and screen effects.

The patch is saved with the settings and with presets. Modulation never changes the stored slider values; *Patch active* switches the whole patch off. Loops are refused when wiring.

## Rendering
Everything is drawn on the GPU with Metal, with shaders compiled at runtime, so Xcode isn't needed:
- **Sphere:** up to 2M points, with 6 layouts (Poles, Harmonics, Ripples, Terrain, Cells, Time globe).
- **Cymatics and Flow:** up to 4M particles, simulated in compute kernels.
- **Feedback warp:** MilkDrop-style. The previous frame is fed back through Tunnel, Vortex, Ripple, Spin, Kaleido or Implode, driven by the bass.
- **Beat detection:** finds bass onsets in about 5 ms chunks. Each beat flashes the glow, kicks the sphere and halo outward, bursts the warp and shakes the particles.
- **Effects:** bloom, trails, CRT effects, and a background colour with opacity.

## Debugging
Environment variables (debug runs never save settings):
- `AUDIOWATCH_WAV=/path/file.wav` plays a file into the analyser instead of the system tap (`AUDIOWATCH_WAV_CHUNK=4096` simulates a bursty device).
- `AUDIOWATCH_SETTINGS='{"mode":"oscilloscope","scopeShape":"circle"}'` overrides saved settings for that run.
- `AUDIOWATCH_SNAPSHOT=/tmp/shot AUDIOWATCH_SNAPSHOT_FRAMES=10,240` writes `/tmp/shot-<frame>.png` and quits after the last one.
- `AUDIOWATCH_TRACE=1` prints the audio playhead per frame.
- `AUDIOWATCH_PERF=1` prints CPU build time and GPU time (ms) per frame.
- `AUDIOWATCH_NODES_SNAPSHOT=/path.png` opens the Nodes window and saves a picture of it after ~3 s.
- Show FPS also reports the audio device's burst size and the playhead buffer.
