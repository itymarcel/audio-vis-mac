
#include <metal_stdlib>
using namespace metal;

struct Uniforms { float2 viewPx; float pxScale; float time; };
struct Seg { float2 a; float2 b; float4 color; float width; float dash; float cap; float pad; };

struct SphereU {
    float4 rot0; float4 rot1; float4 rot2;
    float2 center; float R; float cam;
    float dotR; float dispK; float phase; float colorByFreq;
    float lineW; float alphaK; float square; float dash;
    uint N; uint bandCount; uint mirror; uint mode;
    uint timeGlobe; uint histBands; uint histCols; uint head;
};

struct BandU {
    float fMin; float ratio; float binHz; float floorDB;
    float gain; float tilt; float release; float attack;
    uint count; uint halfBins; uint levels; uint frozen;
};

struct WarpU { float decay; float zoom; float rot; float swirl; float ripple; float kaleido; float time; float aspect; };

struct SimU {
    float4 w0; float4 w1;
    float shake; float speed; float dtScale; float time;
    float turb; float noiseScale; float beat; float level;
    uint count; uint frame; uint bandCount; uint kind;
    float aspect; float p0; float p1; float p2;
};

struct PartDrawU {
    float2 origin; float2 extent;
    float dotR; float alphaK; float phase; float colorByFreq;
    float square; float streak; float domT; float speedK;
    uint kind; uint count; uint bandCount; uint pad;
};

struct SpectroU { float head; float rows; float phase; float colorByFreq; float mirror; float nearest; float bands; float cellPx; };

struct CompU {
    float4 ink;
    float4 bg;
    float glow; float scan; float grain; float vignette;
    float flicker; float bandY; float bgOpacity; float sceneGain;
    float cornerR; float time; float pxScale; float flickerRand;
};

// ---------------------------------------------------------------- helpers

constexpr sampler linClamp(filter::linear, address::clamp_to_edge);

static float pingPong(float t) { float m = t - 2.0 * floor(t * 0.5); return m <= 1.0 ? m : 2.0 - m; }

static float3 pal(texture2d<float> p, float t) {
    return p.sample(linClamp, float2((pingPong(t) * 255.0 + 0.5) / 256.0, 0.5)).rgb;
}

static uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
static float rnd(uint a, uint b) { return float(pcg(a ^ pcg(b + 0x9E3779B9u))) * (1.0 / 4294967295.0); }

static float lattice(int3 c) { return float(pcg(uint(c.x) + pcg(uint(c.y) + pcg(uint(c.z))))) * (1.0 / 4294967295.0); }

/// Smooth 3D value noise in [0,1].
static float vnoise(float3 p) {
    int3 i = int3(floor(p));
    float3 f = fract(p);
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float n000 = lattice(i), n100 = lattice(i + int3(1,0,0)), n010 = lattice(i + int3(0,1,0)), n110 = lattice(i + int3(1,1,0));
    float n001 = lattice(i + int3(0,0,1)), n101 = lattice(i + int3(1,0,1)), n011 = lattice(i + int3(0,1,1)), n111 = lattice(i + int3(1,1,1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

static float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

// ---------------------------------------------------------------- segments (lines, dots, rects)

struct SegOut {
    float4 pos [[position]];
    float2 local;
    float4 color;
    float len; float hw; float dash; float cap; float dashBase; float alphaK;
};

static SegOut makeSeg(float2 aPt, float2 bPt, float widthPt, float4 color, float dashPt, float cap,
                      uint vid, constant Uniforms& U) {
    SegOut o;
    float s = U.pxScale;
    float2 a = aPt * s, b = bPt * s;
    float wpx = widthPt * s;
    float hw = max(wpx * 0.5, 0.5);
    float2 d = b - a;
    float len = length(d);
    float2 dir = len > 1e-4 ? d / len : float2(1.0, 0.0);
    float2 nrm = float2(-dir.y, dir.x);
    float ext = hw + 1.0;
    float u = (vid & 1) ? len + ext : -ext;
    float v = (vid & 2) ? ext : -ext;
    float2 p = a + dir * u + nrm * v;
    float2 ndc = p / U.viewPx * 2.0 - 1.0;
    o.pos = float4(ndc.x, -ndc.y, 0.0, 1.0);
    o.local = float2(u, v);
    o.color = color;
    o.len = len; o.hw = hw; o.dash = dashPt * s; o.cap = cap;
    o.dashBase = dot(a, dir);
    o.alphaK = min(1.0, wpx);
    return o;
}

vertex SegOut segVert(uint vid [[vertex_id]], uint iid [[instance_id]],
                      const device Seg* segs [[buffer(0)]], constant Uniforms& U [[buffer(1)]]) {
    Seg g = segs[iid];
    return makeSeg(g.a, g.b, g.width, g.color, g.dash, g.cap, vid, U);
}

fragment float4 segFrag(SegOut in [[stage_in]]) {
    float u = in.local.x, v = in.local.y;
    float d;
    if (in.cap < 0.5) {
        float cu = clamp(u, 0.0, in.len);
        d = length(float2(u - cu, v)) - in.hw;
    } else {
        float du = in.len < 1e-3 ? abs(u) - in.hw : max(-u, u - in.len);
        d = max(du, abs(v) - in.hw);
    }
    float cov = clamp(0.5 - d, 0.0, 1.0) * in.alphaK;
    if (in.dash > 0.0) {
        float k = fract((in.dashBase + u) / in.dash);
        cov *= step(k, 0.62);
    }
    float a = in.color.a * cov;
    return float4(in.color.rgb * a, a);
}

// ---------------------------------------------------------------- sphere (fully GPU)

vertex SegOut sphereVert(uint vid [[vertex_id]], uint iid [[instance_id]],
                         const device float4* unit [[buffer(0)]], const device float* vals [[buffer(1)]],
                         constant SphereU& S [[buffer(2)]], constant Uniforms& U [[buffer(3)]],
                         const device float* hist [[buffer(4)]],
                         texture2d<float> palTex [[texture(0)]]) {
    float4 u4 = unit[iid];
    float3 p = u4.xyz;
    float frac = u4.w;                                   // where in the spectrum this point sits (0 = low)
    if (S.mirror != 0) frac = 1.0 - abs(2.0 * frac - 1.0);
    float a;
    if (S.timeGlobe != 0) {
        uint b = min(uint(frac * float(S.histBands)), S.histBands - 1);
        float az = atan2(p.z, p.x) / (2.0 * M_PI_F) + 0.5;
        uint c = min(uint(az * float(S.histCols)), S.histCols - 1);
        uint row = (S.head + S.histCols - c) % S.histCols;
        a = hist[row * S.histBands + b];
    } else {
        a = vals[min(uint(frac * float(S.bandCount)), S.bandCount - 1)];
    }
    float3 q = float3(dot(S.rot0.xyz, p), dot(S.rot1.xyz, p), dot(S.rot2.xyz, p));
    float disp = 1.0 + a * S.dispK;
    float proj = S.cam / (S.cam - q.z * disp);
    float2 sp = S.center + float2(q.x, -q.y) * disp * S.R * proj;
    float fade = 0.15 + 0.85 * (q.z + 1.0) * 0.5;
    float t = (S.colorByFreq > 0.5 ? frac : min(a, 1.0)) + S.phase;
    float3 col = pal(palTex, t);
    float alpha = fade * (0.3 + 0.7 * min(a * 1.2, 1.0)) * S.alphaK;

    if (S.mode == 0) {
        float r = S.dotR * proj * (0.6 + 1.6 * a);
        return makeSeg(sp, sp, 2.0 * r, float4(col, alpha), 0.0, S.square, vid, U);
    }
    float p0 = S.cam / (S.cam - q.z);
    float2 bp = S.center + float2(q.x, -q.y) * S.R * p0;
    if (S.mode == 1) {
        return makeSeg(bp, sp, S.lineW, float4(col, alpha), S.dash, S.dash > 0.0 ? 1.0 : 0.0, vid, U);
    }
    float r = S.dotR * p0 * 0.45;
    return makeSeg(bp, bp, 2.0 * r, float4(col, fade * 0.35 * S.alphaK), 0.0, S.square, vid, U);
}

/// Per-point frequency band value with attack/release smoothing, sampled from a max-pyramid of the spectrum.
kernel void bandKernel(device float* vals [[buffer(0)]], const device float* pyr [[buffer(1)]],
                       constant uint* offs [[buffer(2)]], constant BandU& B [[buffer(3)]],
                       uint i [[thread_position_in_grid]]) {
    if (i >= B.count) return;
    float old = vals[i];
    if (B.frozen != 0) return;
    float n = float(B.count);
    float f0 = B.fMin * pow(B.ratio, float(i) / n);
    float f1 = B.fMin * pow(B.ratio, float(i + 1) / n);
    float fc = sqrt(f0 * f1);
    float b0 = f0 / B.binHz, b1 = f1 / B.binHz;
    float hb = float(B.halfBins);
    float a;
    if (b1 - b0 < 1.0) {
        float c = clamp(fc / B.binHz, 1.0, hb - 2.0);
        uint i0 = uint(c);
        float f = c - float(i0);
        a = mix(pyr[i0], pyr[i0 + 1], f);
    } else {
        uint L = min(B.levels - 1, uint(floor(log2(b1 - b0))));
        uint lo = uint(clamp(b0, 1.0, hb - 1.0)) >> L;
        uint hi = uint(clamp(b1, 1.0, hb - 1.0)) >> L;
        a = 0.0;
        for (uint k = lo; k <= hi; k++) a = max(a, pyr[offs[L] + k]);
    }
    float db = 20.0 * log10(a + 1e-9) + B.tilt * log2(fc / 1000.0);
    float v = min(1.5, max(0.0, (db - B.floorDB) / -B.floorDB) * B.gain);
    float k = v > old ? B.attack : B.release;
    vals[i] = old * k + v * (1.0 - k);
}

/// Copies the current band values into one column of the time-globe history ring.
kernel void pushKernel(device float* hist [[buffer(0)]], const device float* vals [[buffer(1)]],
                       constant uint2& P [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    if (i < P.x) hist[P.y + i] = vals[i];
}

// ---------------------------------------------------------------- particles (Cymatics + Flow)

constant int2 chladniModes[8] = { int2(1,2), int2(2,3), int2(1,4), int2(3,4), int2(2,5), int2(4,5), int2(3,7), int2(5,6) };

/// Superposition of 8 square-plate Chladni modes, weighted by the spectrum (low bands → low modes).
static float chladni(float2 p, constant SimU& U) {
    float w[8] = { U.w0.x, U.w0.y, U.w0.z, U.w0.w, U.w1.x, U.w1.y, U.w1.z, U.w1.w };
    float f = 0.0;
    for (int k = 0; k < 8; k++) {
        float n = float(chladniModes[k].x), m = float(chladniModes[k].y);
        f += w[k] * (cos(n * M_PI_F * p.x) * cos(m * M_PI_F * p.y) - cos(m * M_PI_F * p.x) * cos(n * M_PI_F * p.y));
    }
    return f;
}

/// Sand on a vibrating plate: shaken where the plate moves, drifting toward the still nodal lines.
kernel void cymaticsKernel(device float4* P [[buffer(0)]], constant SimU& U [[buffer(1)]], uint i [[thread_position_in_grid]]) {
    if (i >= U.count) return;
    float2 p = P[i].xy;
    const float e = 0.002;
    float f = chladni(p, U);
    float fx = chladni(p + float2(e, 0), U), fy = chladni(p + float2(0, e), U);
    float2 g = float2(fx * fx - f * f, fy * fy - f * f) / e;          // ∇(f²)
    float amp = abs(f);
    float2 jitter = float2(rnd(i, U.frame * 2u), rnd(i, U.frame * 2u + 1u)) - 0.5;
    float2 v = -g * 0.00025 * U.speed + jitter * amp * (U.shake + U.beat * 2.0) * 0.012;
    v *= U.dtScale;
    p += v;
    if (any(p < 0.0) || any(p > 1.0) || rnd(i, U.frame + 777u) < 0.0004) {
        p = float2(rnd(i, U.frame + 11u), rnd(i, U.frame + 23u));
        v = 0.0;
    }
    P[i] = float4(p, v);
}

/// Curl-noise flow; every particle belongs to a frequency band and moves with that band's energy.
kernel void flowKernel(device float4* P [[buffer(0)]], const device float* vals [[buffer(1)]],
                       constant SimU& U [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    if (i >= U.count) return;
    float2 p = P[i].xy;
    float frac = rnd(i, 12345u);
    float level = vals[min(uint(frac * float(U.bandCount)), U.bandCount - 1)];
    float3 q = float3(p.x * U.aspect * U.noiseScale, p.y * U.noiseScale, U.time * 0.12);
    const float e = 0.01;
    float t2 = U.turb;
    float n0 = vnoise(q) + t2 * 0.5 * vnoise(q * 2.3 + 7.1);
    float nx = vnoise(q + float3(e, 0, 0)) + t2 * 0.5 * vnoise((q + float3(e, 0, 0)) * 2.3 + 7.1);
    float ny = vnoise(q + float3(0, e, 0)) + t2 * 0.5 * vnoise((q + float3(0, e, 0)) * 2.3 + 7.1);
    float2 curl = float2(ny - n0, -(nx - n0)) / e;
    float speed = U.speed * (0.08 + level * 1.4);
    float2 v = curl * speed * 0.0016;
    v.x /= U.aspect;
    float2 d = p - 0.5;
    v += normalize(d + 1e-5) * U.beat * 0.006;                           // beat burst
    v *= U.dtScale;
    p = fract(p + v + 1.0);
    if (rnd(i, U.frame + 99u) < 0.0015) p = float2(rnd(i, U.frame + 5u), rnd(i, U.frame + 6u));
    P[i] = float4(p, v);
}

vertex SegOut partVert(uint vid [[vertex_id]], uint iid [[instance_id]],
                       const device float4* P [[buffer(0)]], const device float* vals [[buffer(1)]],
                       constant PartDrawU& D [[buffer(2)]], constant Uniforms& U [[buffer(3)]],
                       texture2d<float> palTex [[texture(0)]]) {
    float4 s = P[iid];
    float2 sp = D.origin + s.xy * D.extent;
    float2 vpx = s.zw * D.extent;
    float speed = length(s.zw) * D.speedK;
    float t;
    float alpha;
    if (D.kind == 0) {   // cymatics
        t = D.colorByFreq > 0.5 ? D.domT + 0.35 * length(s.xy - 0.5) : min(speed, 1.0);
        alpha = D.alphaK * (0.55 + 0.45 * min(speed, 1.0));
    } else {             // flow
        float frac = rnd(iid, 12345u);
        float level = vals[min(uint(frac * float(D.bandCount)), D.bandCount - 1)];
        t = D.colorByFreq > 0.5 ? frac : min(speed, 1.0);
        alpha = D.alphaK * (0.25 + 0.75 * min(level, 1.0));
    }
    float3 col = pal(palTex, t + D.phase);
    if (D.streak > 0.0 && length(vpx) > 0.05) {
        float2 tail = sp - vpx * D.streak;
        if (length(tail - sp) > D.extent.x * 0.25) tail = sp;            // skip wrap-around jumps
        return makeSeg(tail, sp, D.dotR * 2.0, float4(col, alpha), 0.0, 0.0, vid, U);
    }
    return makeSeg(sp, sp, D.dotR * 2.0, float4(col, alpha), 0.0, D.square, vid, U);
}

// ---------------------------------------------------------------- full-screen passes

struct FSOut { float4 pos [[position]]; float2 uv; };

vertex FSOut fsVert(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FSOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

fragment float4 spectroFrag(FSOut in [[stage_in]], texture2d<float> hist [[texture(0)]],
                            texture2d<float> palTex [[texture(1)]], constant SpectroU& P [[buffer(0)]]) {
    float x = in.uv.x;
    if (P.mirror > 0.5) x = abs(x - 0.5) * 2.0;
    float rowF = P.head - in.uv.y * (P.rows - 1.0);
    rowF = rowF - P.rows * floor(rowF / P.rows);
    float v;
    if (P.nearest > 0.5) {
        float bx = min(x * P.bands, P.bands - 1.0);
        v = hist.read(uint2(uint(bx), uint(rowF))).r;
        if (P.cellPx > 4.0) v *= step(0.14, fract(bx)) * step(0.25, fract(rowF));
    } else {
        constexpr sampler s(filter::linear, s_address::clamp_to_edge, t_address::repeat);
        v = hist.sample(s, float2(x, (rowF + 0.5) / P.rows)).r;
    }
    v = min(v, 1.0);
    float t = (P.colorByFreq > 0.5 ? x * 0.85 + v * 0.15 : v) + P.phase;
    float a = pow(v, 1.3);
    return float4(pal(palTex, t) * a, a);
}

/// MilkDrop-style feedback: previous frame resampled through an audio-driven zoom / spin / swirl / ripple / kaleidoscope.
fragment float4 fadeFrag(FSOut in [[stage_in]], texture2d<float> prev [[texture(0)]], constant WarpU& W [[buffer(0)]]) {
    float2 p = in.uv - 0.5;
    p.x *= W.aspect;
    float r = length(p);
    float a = atan2(p.y, p.x);
    a -= W.rot + W.swirl * exp(-r * 3.0);
    if (W.kaleido > 1.5) {
        float seg = 2.0 * M_PI_F / W.kaleido;
        a = fmod(a + 8.0 * M_PI_F, seg);
        a = abs(a - seg * 0.5);
    }
    r /= W.zoom;
    r += W.ripple * 0.003 * sin(r * 45.0 - W.time * 5.0);
    p = float2(cos(a), sin(a)) * r;
    p.x /= W.aspect;
    float2 uv = p + 0.5;
    float edge = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return prev.sample(linClamp, uv) * W.decay * edge;
}

fragment float4 blurFrag(FSOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float2& step [[buffer(0)]]) {
    const float w[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
    float4 c = src.sample(linClamp, in.uv) * w[0];
    for (int i = 1; i < 5; i++) {
        c += src.sample(linClamp, in.uv + step * float(i)) * w[i];
        c += src.sample(linClamp, in.uv - step * float(i)) * w[i];
    }
    return c;
}

fragment float4 compositeFrag(FSOut in [[stage_in]], texture2d<float> scene [[texture(0)]],
                              texture2d<float> bloom [[texture(1)]],
                              constant CompU& C [[buffer(0)]]) {
    float2 px = in.pos.xy;
    float2 size = float2(scene.get_width(), scene.get_height());
    float3 c = scene.read(uint2(px)).rgb * C.sceneGain;
    c += bloom.sample(linClamp, in.uv).rgb * C.glow * 2.2 * C.sceneGain;
    // Hue-preserving tonemap: compress brightness by the max channel so dense overlaps keep their palette colour
    float m = max(c.r, max(c.g, c.b));
    if (m > 1e-5) c *= (1.0 - exp(-m * 1.3)) / m;

    // rolling refresh band
    float bd = (in.uv.y - C.bandY) / 0.08;
    c += C.ink.rgb * C.flicker * 0.06 * exp(-bd * bd);
    // scanlines
    float line = fract(px.y / (3.0 * C.pxScale));
    c *= 1.0 - C.scan * 0.55 * smoothstep(0.42, 0.62, line);
    // grain
    float n = hash(floor(px / C.pxScale) + fract(C.time * 7.31) * 913.0);
    c *= 1.0 + (n * n * n - 0.12) * C.grain * 0.9;   // multiplicative so grain doesn't grey out colours
    // flicker
    c *= 1.0 - C.flickerRand;
    c = max(c, 0.0);
    // background colour underneath the (additive) light
    float lit = clamp(max(c.r, max(c.g, c.b)), 0.0, 1.0);
    c += C.bg.rgb * C.bgOpacity * (1.0 - lit);
    float alpha = lit + C.bgOpacity * (1.0 - lit);
    // vignette
    float2 q = (in.uv - 0.5) * float2(size.x / size.y, 1.0);
    c *= 1.0 - C.vignette * 0.85 * smoothstep(0.3, 1.0, length(q));
    // rounded CRT corners
    float r = C.cornerR;
    float2 h = size * 0.5;
    float2 pp = abs(px - h) - (h - r);
    float d = length(max(pp, 0.0)) + min(max(pp.x, pp.y), 0.0) - r;
    float mask = clamp(0.5 - d, 0.0, 1.0);
    c *= mask;
    alpha = mix(C.bgOpacity, alpha, mask);
    return float4(min(c, alpha), alpha);
}
