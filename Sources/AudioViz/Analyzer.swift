import Accelerate
import Foundation

/// Per-frame analysis: snapshot of the latest samples, an FFT spectrum,
/// log-spaced band extraction, and a rolling history of waveform "columns".
final class Analyzer {
    let ring: AudioRing
    private(set) var fftSize = 8192
    let snapSize = 32768

    private(set) var snapL: [Float]
    private(set) var snapR: [Float]
    /// Linear amplitude per FFT bin (full-scale sine ≈ 1.0).
    private(set) var amp: [Float]
    private(set) var sampleRate: Double = 48_000
    private(set) var lastSoundTime: Double = 0
    private(set) var lastDataTime: Double = 0
    private(set) var peakLevel: Float = 0
    private(set) var dominantHz: Double = 0
    private var lastWritten: Int64 = 0

    private var fft: vDSP.FFT<DSPSplitComplex>
    private var window: [Float]
    private var windowed: [Float]
    private var re: [Float]
    private var im: [Float]
    private var sq: [Float]

    // Band mapping cache
    private struct MapKey: Equatable { var count: Int; var fMin: Double; var fMax: Double; var sr: Double }
    private var mapKey: MapKey?
    private var bLo: [Int] = []
    private var bHi: [Int] = []
    private var bCenter: [Float] = []
    private var bOctave: [Float] = []

    // Waveform columns (one per `chunk` frames)
    struct Column {
        var minL: Float = 0, maxL: Float = 0, minR: Float = 0, maxR: Float = 0
        var rms: Float = 0
        /// 0 = bass-heavy, 1 = treble-heavy
        var bright: Float = 0
    }
    static let chunk = 256
    private let colCap = 8192
    private var cols: [Column]
    private(set) var colCount = 0
    private var consumed: Int64 = -1
    private var acc = Column()
    private var accN = 0
    private var accSq: Float = 0
    private var eLow: Float = 0, eMid: Float = 0, eHigh: Float = 0
    private var lp: Float = 0, hpState: Float = 0
    private var tmpL: [Float]
    private var tmpR: [Float]

    init(ring: AudioRing) {
        self.ring = ring
        snapL = .init(repeating: 0, count: snapSize)
        snapR = .init(repeating: 0, count: snapSize)
        amp = .init(repeating: 0, count: fftSize / 2)
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(fftSize))), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        windowed = .init(repeating: 0, count: fftSize)
        re = .init(repeating: 0, count: fftSize / 2)
        im = .init(repeating: 0, count: fftSize / 2)
        sq = .init(repeating: 0, count: fftSize / 2)
        cols = .init(repeating: Column(), count: colCap)
        tmpL = .init(repeating: 0, count: 8192)
        tmpR = .init(repeating: 0, count: 8192)
    }

    // MARK: - Per-frame update

    /// Changes the analysis FFT size (power of two, 1024…32768).
    func configure(fftSize n: Int) {
        guard n != fftSize, n >= 1024, n <= snapSize, n & (n - 1) == 0 else { return }
        fftSize = n
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        windowed = .init(repeating: 0, count: n)
        re = .init(repeating: 0, count: n / 2)
        im = .init(repeating: 0, count: n / 2)
        sq = .init(repeating: 0, count: n / 2)
        amp = .init(repeating: 0, count: n / 2)
        mapKey = nil
    }

    /// Writes a max-pyramid of the amplitude spectrum (level 0 = raw bins) for the GPU. Returns level count.
    func buildPyramid(into p: UnsafeMutablePointer<Float>, capacity: Int, offsets: inout [UInt32]) -> Int {
        let half = fftSize / 2
        guard half * 2 <= capacity else { return 0 }
        amp.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: half) }
        var off = 0, size = half, level = 0
        offsets[0] = 0
        while size > 1 && level < 15 {
            let next = (size + 1) / 2
            let dst = off + size
            for i in 0..<next {
                let a = p[off + 2 * i]
                let b = 2 * i + 1 < size ? p[off + 2 * i + 1] : a
                p[dst + i] = max(a, b)
            }
            off = dst; size = next; level += 1
            offsets[level] = UInt32(off)
        }
        return level + 1
    }

    func update(now: Double, fftSize n: Int) {
        configure(fftSize: n)
        sampleRate = ring.sampleRate
        let written = ring.totalWritten
        if written != lastWritten { lastDataTime = now; lastWritten = written }

        snapL.withUnsafeMutableBufferPointer { l in
            snapR.withUnsafeMutableBufferPointer { r in
                ring.copyLatest(count: snapSize, l: l.baseAddress!, r: r.baseAddress!)
            }
        }

        let off = snapSize - fftSize
        var peak: Float = 0
        for i in 0..<fftSize {
            let m = 0.5 * (snapL[off + i] + snapR[off + i])
            windowed[i] = m * window[i]
            peak = max(peak, abs(m))
        }
        if peak > 1e-4 { lastSoundTime = now }
        peakLevel = peak

        let half = fftSize / 2
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &sq)
            }
        }
        sq[0] = 0
        vForce.sqrt(sq, result: &amp)
        vDSP.multiply(1 / Float(half), amp, result: &amp)
        dominantHz = Double(vDSP.indexOfMaximum(amp).0) * sampleRate / Double(fftSize)

        processColumns()
    }

    // MARK: - Spectrum queries

    /// `count` log-spaced bands between the settings' min/max frequency, normalized 0…~1.5.
    func bands(count: Int, s: VizSettings) -> [Float] {
        let fMin = max(10, s.minFreq)
        let fMax = max(fMin * 1.5, min(s.maxFreq, sampleRate / 2 - 1))
        ensureMap(count: count, fMin: fMin, fMax: fMax)

        var out = [Float](repeating: 0, count: count)
        let floorDB = Float(s.floorDB), gain = Float(s.gain), tilt = Float(s.tilt)
        let inv = 1 / -floorDB
        amp.withUnsafeBufferPointer { a in
            for k in 0..<count {
                let lo = bLo[k], hi = bHi[k]
                var v: Float
                if hi - lo <= 1 {
                    let c = bCenter[k]
                    let i0 = Int(c)
                    let f = c - Float(i0)
                    v = a[i0] * (1 - f) + a[i0 + 1] * f
                } else {
                    v = 0
                    for i in lo..<hi { v = max(v, a[i]) }
                }
                let db = 20 * log10f(v + 1e-9) + tilt * bOctave[k]
                out[k] = min(1.5, max(0, (db - floorDB) * inv) * gain)
            }
        }
        return out
    }

    /// Normalized level of a frequency range (e.g. bass), 0…~1.5.
    func level(_ fLo: Double, _ fHi: Double, s: VizSettings) -> Float {
        let binHz = sampleRate / Double(fftSize)
        let lo = max(1, Int(fLo / binHz)), hi = min(amp.count - 1, max(lo + 1, Int(fHi / binHz)))
        var m: Float = 0
        for i in lo..<hi { m = max(m, amp[i]) }
        let floorDB = Float(s.floorDB)
        let db = 20 * log10f(m + 1e-9)
        return min(1.5, max(0, (db - floorDB) / -floorDB) * Float(s.gain))
    }

    /// RMS of the most recent `count` frames (mono).
    func rms(last count: Int) -> Float {
        let n = min(count, snapSize)
        var sum: Float = 0
        for i in (snapSize - n)..<snapSize {
            let m = 0.5 * (snapL[i] + snapR[i])
            sum += m * m
        }
        return sqrt(sum / Float(max(n, 1)))
    }

    private func ensureMap(count: Int, fMin: Double, fMax: Double) {
        let key = MapKey(count: count, fMin: fMin, fMax: fMax, sr: sampleRate)
        if key == mapKey { return }
        mapKey = key
        let half = fftSize / 2
        let binHz = sampleRate / Double(fftSize)
        let ratio = fMax / fMin
        bLo = .init(repeating: 0, count: count)
        bHi = .init(repeating: 0, count: count)
        bCenter = .init(repeating: 0, count: count)
        bOctave = .init(repeating: 0, count: count)
        for k in 0..<count {
            let f0 = fMin * pow(ratio, Double(k) / Double(count))
            let f1 = fMin * pow(ratio, Double(k + 1) / Double(count))
            let fc = sqrt(f0 * f1)
            let lo = min(max(1, Int(floor(f0 / binHz))), half - 2)
            bLo[k] = lo
            bHi[k] = min(max(lo + 1, Int(ceil(f1 / binHz))), half - 1)
            bCenter[k] = Float(min(max(1, fc / binHz), Double(half - 2)))
            bOctave[k] = Float(log2(fc / 1000))
        }
    }

    // MARK: - Waveform columns

    /// Most recent columns, oldest first.
    func recentColumns(_ n: Int) -> ArraySlice<Column> {
        let count = min(n, colCount, colCap)
        var out = [Column]()
        out.reserveCapacity(count)
        for i in (colCount - count)..<colCount { out.append(cols[i % colCap]) }
        return out[...]
    }

    // Beat detection on bass energy per chunk (~5 ms resolution)
    private var beatFast: Float = 0
    private var beatSlow: Float = 0
    private var sampleClock: Int64 = 0
    private var lastBeatSample: Int64 = -1_000_000
    private(set) var beatCount = 0

    private func detectBeat(lowRMS: Float) {
        let chunkDur = Float(Self.chunk) / Float(sampleRate)
        beatFast += (lowRMS - beatFast) * (1 - exp(-chunkDur / 0.025))
        beatSlow += (lowRMS - beatSlow) * (1 - exp(-chunkDur / 1.2))
        sampleClock += Int64(Self.chunk)
        if beatFast > beatSlow * 1.35 + 0.003 && sampleClock - lastBeatSample > Int64(sampleRate * 0.22) {
            lastBeatSample = sampleClock
            beatCount += 1
        }
    }

    /// 1 right on a detected beat, decaying to 0 over ~150 ms.
    var beatPulse: Float {
        let age = Double(sampleClock - lastBeatSample) / sampleRate
        return age < 0 ? 0 : Float(exp(-age / 0.15))
    }

    private func processColumns() {
        let written = ring.totalWritten
        if consumed < 0 || written - consumed > Int64(sampleRate) {
            consumed = max(0, written - Int64(Self.chunk))
        }
        let aLow = 1 - exp(-2 * Float.pi * 200 / Float(sampleRate))
        let aHigh = 1 - exp(-2 * Float.pi * 2500 / Float(sampleRate))
        let chunk = Self.chunk

        while consumed < written {
            let want = min(Int(written - consumed), tmpL.count)
            let got = tmpL.withUnsafeMutableBufferPointer { l in
                tmpR.withUnsafeMutableBufferPointer { r in
                    ring.copy(from: consumed, count: want, l: l.baseAddress!, r: r.baseAddress!)
                }
            }
            if got == 0 { break }
            for i in 0..<got {
                let l = tmpL[i], r = tmpR[i], m = 0.5 * (l + r)
                if accN == 0 {
                    acc = Column(minL: l, maxL: l, minR: r, maxR: r)
                } else {
                    acc.minL = min(acc.minL, l); acc.maxL = max(acc.maxL, l)
                    acc.minR = min(acc.minR, r); acc.maxR = max(acc.maxR, r)
                }
                accSq += m * m
                lp += aLow * (m - lp)
                hpState += aHigh * (m - hpState)
                let high = m - hpState, mid = hpState - lp
                eLow += lp * lp; eMid += mid * mid; eHigh += high * high
                accN += 1
                if accN == chunk {
                    acc.rms = sqrt(accSq / Float(chunk))
                    let rl = sqrt(eLow), rm = sqrt(eMid), rh = sqrt(eHigh) * 2.5
                    acc.bright = min(1, (0.5 * rm + rh) / (rl + rm + rh + 1e-9))
                    detectBeat(lowRMS: sqrt(eLow / Float(chunk)))
                    cols[colCount % colCap] = acc
                    colCount += 1
                    accN = 0; accSq = 0; eLow = 0; eMid = 0; eHigh = 0
                }
            }
            consumed += Int64(got)
        }
    }
}
