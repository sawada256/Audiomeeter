import Foundation
import Accelerate

/// Biquad Filter Coefficients and State for 3-band EQ
public struct BiquadFilter {
    private var b0: Float = 1.0, b1: Float = 0.0, b2: Float = 0.0
    private var a1: Float = 0.0, a2: Float = 0.0
    private var x1_L: Float = 0.0, x2_L: Float = 0.0, y1_L: Float = 0.0, y2_L: Float = 0.0
    private var x1_R: Float = 0.0, x2_R: Float = 0.0, y1_R: Float = 0.0, y2_R: Float = 0.0
    // Coefficients currently applied by processBlock; they ramp toward the targets above,
    // so EQ edits glide over one block instead of stepping (zipper noise).
    private var c0: Float = 1, c1: Float = 0, c2: Float = 0, d1: Float = 0, d2: Float = 0
    private var primed = false

    public init() {}

    public mutating func reset() {
        x1_L = 0; x2_L = 0; y1_L = 0; y2_L = 0
        x1_R = 0; x2_R = 0; y1_R = 0; y2_R = 0
        primed = false
    }
    /// Clears the signal state only (a filter resuming after being skipped).
    public mutating func clearState() {
        x1_L = 0; x2_L = 0; y1_L = 0; y2_L = 0
        x1_R = 0; x2_R = 0; y1_R = 0; y2_R = 0
    }
    var targetIsIdentity: Bool { b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0 }
    var isSettled: Bool { primed && c0 == b0 && c1 == b1 && c2 == b2 && d1 == a1 && d2 == a2 }

    /// Block processing with per-sample linear coefficient interpolation after a change.
    public mutating func processBlock(_ buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        if !primed { c0 = b0; c1 = b1; c2 = b2; d1 = a1; d2 = a2; primed = true }
        let ramp = !isSettled
        let scale = 1 / Float(frames)
        let s0 = (b0 - c0) * scale, s1 = (b1 - c1) * scale, s2 = (b2 - c2) * scale, t1 = (a1 - d1) * scale, t2 = (a2 - d2) * scale
        for i in 0..<frames {
            if ramp { c0 += s0; c1 += s1; c2 += s2; d1 += t1; d2 += t2 }
            let left = buffer[i * 2], right = buffer[i * 2 + 1]
            let outL = c0 * left + c1 * x1_L + c2 * x2_L - d1 * y1_L - d2 * y2_L
            x2_L = x1_L; x1_L = left; y2_L = y1_L; y1_L = outL
            let outR = c0 * right + c1 * x1_R + c2 * x2_R - d1 * y1_R - d2 * y2_R
            x2_R = x1_R; x1_R = right; y2_R = y1_R; y1_R = outR
            buffer[i * 2] = outL; buffer[i * 2 + 1] = outR
        }
        if ramp { c0 = b0; c1 = b1; c2 = b2; d1 = a1; d2 = a2 }
    }

    public mutating func setLowShelf(sampleRate: Float, cutoffHz: Float = 100.0, gainDB: Float) {
        if abs(gainDB) < 0.05 {
            b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0
            return
        }
        let A = powf(10.0, gainDB / 40.0)
        let w0 = 2.0 * Float.pi * cutoffHz / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 / 2.0 * sqrtf((A + 1.0 / A) * (1.0 / 0.707 - 1.0) + 2.0)

        let a0 = (A + 1.0) + (A - 1.0) * cosw0 + 2.0 * sqrtf(A) * alpha
        b0 = (A * ((A + 1.0) - (A - 1.0) * cosw0 + 2.0 * sqrtf(A) * alpha)) / a0
        b1 = (2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)) / a0
        b2 = (A * ((A + 1.0) - (A - 1.0) * cosw0 - 2.0 * sqrtf(A) * alpha)) / a0
        a1 = (-2.0 * ((A - 1.0) + (A + 1.0) * cosw0)) / a0
        a2 = ((A + 1.0) + (A - 1.0) * cosw0 - 2.0 * sqrtf(A) * alpha) / a0
    }

    public mutating func setPeaking(sampleRate: Float, freqHz: Float = 1000.0, Q: Float = 1.0, gainDB: Float) {
        if abs(gainDB) < 0.05 {
            b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0
            return
        }
        let A = powf(10.0, gainDB / 40.0)
        let w0 = 2.0 * Float.pi * freqHz / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 / (2.0 * Q)

        let a0 = 1.0 + alpha / A
        b0 = (1.0 + alpha * A) / a0
        b1 = (-2.0 * cosw0) / a0
        b2 = (1.0 - alpha * A) / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha / A) / a0
    }

    public mutating func setHighShelf(sampleRate: Float, cutoffHz: Float = 8000.0, gainDB: Float) {
        if abs(gainDB) < 0.05 {
            b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0
            return
        }
        let A = powf(10.0, gainDB / 40.0)
        let w0 = 2.0 * Float.pi * cutoffHz / sampleRate
        let cosw0 = cosf(w0)
        let sinw0 = sinf(w0)
        let alpha = sinw0 / 2.0 * sqrtf((A + 1.0 / A) * (1.0 / 0.707 - 1.0) + 2.0)

        let a0 = (A + 1.0) - (A - 1.0) * cosw0 + 2.0 * sqrtf(A) * alpha
        b0 = (A * ((A + 1.0) + (A - 1.0) * cosw0 + 2.0 * sqrtf(A) * alpha)) / a0
        b1 = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)) / a0
        b2 = (A * ((A + 1.0) + (A - 1.0) * cosw0 - 2.0 * sqrtf(A) * alpha)) / a0
        a1 = (2.0 * ((A - 1.0) - (A + 1.0) * cosw0)) / a0
        a2 = ((A + 1.0) - (A - 1.0) * cosw0 - 2.0 * sqrtf(A) * alpha) / a0
    }

    public mutating func setHighPass(sampleRate: Float, freqHz: Float = 80.0, Q: Float = 0.707) {
        let w0 = 2.0 * Float.pi * max(20.0, min(freqHz, sampleRate * 0.49)) / sampleRate
        let cosw0 = cosf(w0)
        let alpha = sinf(w0) / (2.0 * max(0.1, Q))

        let a0 = 1.0 + alpha
        b0 = ((1.0 + cosw0) / 2.0) / a0
        b1 = (-(1.0 + cosw0)) / a0
        b2 = ((1.0 + cosw0) / 2.0) / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    public mutating func setLowPass(sampleRate: Float, freqHz: Float = 12000.0, Q: Float = 0.707) {
        let w0 = 2.0 * Float.pi * max(20.0, min(freqHz, sampleRate * 0.49)) / sampleRate
        let cosw0 = cosf(w0)
        let alpha = sinf(w0) / (2.0 * max(0.1, Q))

        let a0 = 1.0 + alpha
        b0 = ((1.0 - cosw0) / 2.0) / a0
        b1 = (1.0 - cosw0) / a0
        b2 = ((1.0 - cosw0) / 2.0) / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    public mutating func setNotch(sampleRate: Float, freqHz: Float = 1000.0, Q: Float = 2.0) {
        let w0 = 2.0 * Float.pi * max(20.0, min(freqHz, sampleRate * 0.49)) / sampleRate
        let cosw0 = cosf(w0)
        let alpha = sinf(w0) / (2.0 * max(0.1, Q))

        let a0 = 1.0 + alpha
        b0 = 1.0 / a0
        b1 = (-2.0 * cosw0) / a0
        b2 = 1.0 / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    public mutating func configure(type: FilterType, sampleRate: Float, freqHz: Float, gainDB: Float, q: Float) {
        switch type {
        case .peaking:
            setPeaking(sampleRate: sampleRate, freqHz: freqHz, Q: q, gainDB: gainDB)
        case .lowShelf:
            setLowShelf(sampleRate: sampleRate, cutoffHz: freqHz, gainDB: gainDB)
        case .highShelf:
            setHighShelf(sampleRate: sampleRate, cutoffHz: freqHz, gainDB: gainDB)
        case .highPass:
            setHighPass(sampleRate: sampleRate, freqHz: freqHz, Q: q)
        case .lowPass:
            setLowPass(sampleRate: sampleRate, freqHz: freqHz, Q: q)
        case .notch:
            setNotch(sampleRate: sampleRate, freqHz: freqHz, Q: q)
        }
    }

    /// Calculate frequency response in dB at specified frequency for UI drawing
    public func frequencyResponseDB(freq: Float, sampleRate: Float) -> Float {
        let w = 2.0 * Float.pi * freq / sampleRate
        let cosw = cosf(w)
        let sinw = sinf(w)
        let cos2w = cosf(2.0 * w)
        let sin2w = sinf(2.0 * w)

        let numReal = b0 + b1 * cosw + b2 * cos2w
        let numImag = -(b1 * sinw + b2 * sin2w)

        let denReal = 1.0 + a1 * cosw + a2 * cos2w
        let denImag = -(a1 * sinw + a2 * sin2w)

        let numMagSq = numReal * numReal + numImag * numImag
        let denMagSq = denReal * denReal + denImag * denImag

        if denMagSq < 1e-12 { return 0.0 }
        let magSq = numMagSq / denMagSq
        let magDB = 10.0 * log10f(max(magSq, 1e-6))
        return max(-36.0, min(36.0, magDB))
    }

    @inline(__always)
    public mutating func process(left: Float, right: Float) -> (Float, Float) {
        let out_L = b0 * left + b1 * x1_L + b2 * x2_L - a1 * y1_L - a2 * y2_L
        x2_L = x1_L; x1_L = left; y2_L = y1_L; y1_L = out_L

        let out_R = b0 * right + b1 * x1_R + b2 * x2_R - a1 * y1_R - a2 * y2_R
        x2_R = x1_R; x1_R = right; y2_R = y1_R; y1_R = out_R

        return (out_L, out_R)
    }
}

/// 6-Band Parametric Master Bus EQ
public final class ParametricEQ6Band {
    private var filters: [BiquadFilter] = Array(repeating: BiquadFilter(), count: 6)
    private var skipped = [Bool](repeating: true, count: 6)
    private var lastConfig: MasterEQConfig?
    private var lastSampleRate: Float = 0.0

    public init() {}

    public func reset() {
        for i in 0..<filters.count {
            filters[i].reset()
        }
    }

    public func update(config: MasterEQConfig, sampleRate: Float) {
        if lastConfig == config && lastSampleRate == sampleRate { return }
        lastConfig = config
        lastSampleRate = sampleRate

        for i in 0..<min(6, config.bands.count) {
            let band = config.bands[i]
            if band.isEnabled {
                filters[i].configure(type: band.type, sampleRate: sampleRate, freqHz: band.freqHz, gainDB: band.gainDB, q: band.q)
            } else {
                filters[i].configure(type: .peaking, sampleRate: sampleRate, freqHz: 1000.0, gainDB: 0.0, q: 1.0)
            }
        }
    }

    public func process(buffer: UnsafeMutablePointer<Float>, frames: Int) {
        guard let config = lastConfig, config.isEnabled else { return }
        for i in 0..<min(6, config.bands.count) {
            // A disabled band glides to unity before it is skipped; a re-enabled band
            // restarts from clean state at unity and glides to its new response.
            let active = config.bands[i].isEnabled || !(filters[i].isSettled && filters[i].targetIsIdentity)
            guard active else { skipped[i] = true; continue }
            if skipped[i] { filters[i].clearState(); skipped[i] = false }
            filters[i].processBlock(buffer, frames: frames)
        }
    }

    /// Configure each filter once for an entire display curve, rather than per pixel.
    public static func responseCurve(config: MasterEQConfig, sampleRate: Float, points: Int = 201) -> [Float] {
        let filters = config.bands.filter { $0.isEnabled }.map { band -> BiquadFilter in
            var filter = BiquadFilter()
            filter.configure(type: band.type, sampleRate: sampleRate, freqHz: band.freqHz, gainDB: band.gainDB, q: band.q)
            return filter
        }
        return (0..<max(2,points)).map { i in
            let frequency = 20 * powf(1000,Float(i)/Float(max(2,points)-1))
            let sum = filters.reduce(Float(0)) { $0 + $1.frequencyResponseDB(freq:frequency,sampleRate:sampleRate) }
            return max(-30,min(30,sum))
        }
    }

    /// Calculate combined frequency response in dB across all 6 bands
    public static func combinedResponseDB(config: MasterEQConfig, freq: Float, sampleRate: Float = 48000.0) -> Float {
        var totalDB: Float = 0.0
        var tempFilter = BiquadFilter()

        for band in config.bands {
            if band.isEnabled {
                tempFilter.configure(type: band.type, sampleRate: sampleRate, freqHz: band.freqHz, gainDB: band.gainDB, q: band.q)
                totalDB += tempFilter.frequencyResponseDB(freq: freq, sampleRate: sampleRate)
            }
        }
        return max(-30.0, min(30.0, totalDB))
    }
}

/// Karaoke Center Cancel (Vocal Remover) with Bass Preservation
public final class KaraokeProcessor {
    private var bassLP_L = BiquadFilter()
    private var bassHP_L = BiquadFilter()
    private var isConfigured = false

    public init() {}

    public func reset() {
        bassLP_L.reset()
        bassHP_L.reset()
        isConfigured = false
    }

    private func configure(sampleRate: Float) {
        // Crossover at 150 Hz to preserve bass and kick drum
        bassLP_L.setLowPass(sampleRate: sampleRate, freqHz: 150.0, Q: 0.707)
        bassHP_L.setHighPass(sampleRate: sampleRate, freqHz: 150.0, Q: 0.707)
        isConfigured = true
    }

    public func process(buffer: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Float, isEnabled: Bool) {
        if !isEnabled { return }
        if !isConfigured { configure(sampleRate: sampleRate) }

        for i in 0..<frames {
            let l = buffer[i * 2]
            let r = buffer[i * 2 + 1]

            // 1. Separate bass (< 150 Hz) and mid/highs (> 150 Hz)
            let (lBass, rBass) = bassLP_L.process(left: l, right: r)
            let (lHigh, rHigh) = bassHP_L.process(left: l, right: r)

            // 2. Compute mid (vocal center) component on mid/highs
            let midHigh = (lHigh + rHigh) * 0.5

            // 3. Subtract center vocal component while preserving stereo side ambience
            let lHighCancel = lHigh - midHigh
            let rHighCancel = rHigh - midHigh

            // 4. Recombine with intact mono bass
            let monoBass = (lBass + rBass) * 0.5
            buffer[i * 2] = monoBass + lHighCancel * 1.2
            buffer[i * 2 + 1] = monoBass + rHighCancel * 1.2
        }
    }
}

/// Dynamics Processor (Noise Gate & Compressor)
public final class DynamicsProcessor {
    private var envelope: Float = 0.0
    private var gateGain: Float = 1.0

    public init() {}

    public func reset() {
        envelope = 0.0
        gateGain = 1.0
    }

    /// Process interleaved stereo audio in-place
    public func process(
        buffer: UnsafeMutablePointer<Float>,
        frames: Int,
        sampleRate: Float,
        compKnob: Float, // 0.0 ... 10.0
        gateKnob: Float  // 0.0 ... 10.0
    ) {
        let hasComp = compKnob > 0.05
        let hasGate = gateKnob > 0.05
        if !hasComp && !hasGate { return }

        // Compressor parameters based on knob 0-10
        let compThresholdDB = -10.0 - (compKnob * 2.5) // -10dB to -35dB
        let compRatio = 1.0 + (compKnob * 0.5)         // 1:1 to 6:1
        let makeupGainLinear = powf(10.0, (compKnob * 0.8) / 20.0)

        // Noise gate parameters based on knob 0-10
        let gateThresholdDB = -60.0 + (gateKnob * 3.0) // -60dB to -30dB
        let gateThresholdLinear = powf(10.0, gateThresholdDB / 20.0)

        let attackCoeff = expf(-1.0 / (0.010 * sampleRate))  // 10ms attack
        let releaseCoeff = expf(-1.0 / (0.150 * sampleRate)) // 150ms release
        let gateAttackCoeff = expf(-1.0 / (0.002 * sampleRate)) // 2ms gate attack
        let gateReleaseCoeff = expf(-1.0 / (0.080 * sampleRate)) // 80ms gate release

        for i in 0..<frames {
            let left = buffer[i * 2]
            let right = buffer[i * 2 + 1]
            let peak = max(abs(left), abs(right))

            // Envelope follower
            if peak > envelope {
                envelope = attackCoeff * envelope + (1.0 - attackCoeff) * peak
            } else {
                envelope = releaseCoeff * envelope + (1.0 - releaseCoeff) * peak
            }

            // Noise Gate calculation
            if hasGate {
                let targetGateGain: Float = envelope < gateThresholdLinear ? 0.0 : 1.0
                if targetGateGain > gateGain {
                    gateGain = gateAttackCoeff * gateGain + (1.0 - gateAttackCoeff) * targetGateGain
                } else {
                    gateGain = gateReleaseCoeff * gateGain + (1.0 - gateReleaseCoeff) * targetGateGain
                }
            }

            // Compressor calculation
            var compGain: Float = 1.0
            if hasComp && envelope > 1e-5 {
                let envDB = 20.0 * log10f(envelope)
                if envDB > compThresholdDB {
                    let overDB = envDB - compThresholdDB
                    let gainReductionDB = overDB * (1.0 - 1.0 / compRatio)
                    compGain = powf(10.0, -gainReductionDB / 20.0)
                }
            }

            let totalGain = gateGain * compGain * (hasComp ? makeupGainLinear : 1.0)
            buffer[i * 2] = left * totalGain
            buffer[i * 2 + 1] = right * totalGain
        }
    }
}

/// Strip DSP (Fader, EQ, Intellipan, Dynamics, Karaoke)
public final class StripDSP {
    private var currentGainLinear: Float = 1.0
    private var targetGainLinear: Float = 1.0
    private var lowFilter = BiquadFilter()
    private var midFilter = BiquadFilter()
    private var highFilter = BiquadFilter()
    private var dynamics = DynamicsProcessor()
    private var karaoke = KaraokeProcessor()
    private let padDSP = InputPadDSP()
    private var lastEQ: EQ3Band?
    private var lastEQRate: Float = 0

    public init() {}

    public func reset() {
        lowFilter.reset()
        midFilter.reset()
        highFilter.reset()
        dynamics.reset()
        karaoke.reset()
        padDSP.reset()
    }

    /// Process input strip audio in-place
    public func process(
        buffer: UnsafeMutablePointer<Float>,
        frames: Int,
        sampleRate: Float,
        gainDB: Float,
        isMuted: Bool,
        dynamicsConfig: DynamicsConfig,
        intellipan: IntellipanState,
        eq: EQ3Band,
        isVirtual: Bool,
        isKaraoke: Bool = false,
        padMode: InputPadMode = .intellipan, padState: IntellipanState = IntellipanState(), pitchSmooth: Bool = false
    ) {
        if isMuted || gainDB <= -59.5 {
            targetGainLinear = 0.0
        } else {
            targetGainLinear = powf(10.0, gainDB / 20.0)
        }

        // Apply Dynamics (Comp & Gate for hardware strips)
        if !isVirtual {
            dynamics.process(
                buffer: buffer,
                frames: frames,
                sampleRate: sampleRate,
                compKnob: dynamicsConfig.compKnob,
                gateKnob: dynamicsConfig.gateKnob
            )
        }

        // Apply Karaoke / Center Cancel (for virtual strips)
        if isVirtual && isKaraoke {
            karaoke.process(buffer: buffer, frames: frames, sampleRate: sampleRate, isEnabled: isKaraoke)
        }

        // Apply 3-Band EQ (Virtual strips or hardware)
        if isVirtual {
            if lastEQ != eq || lastEQRate != sampleRate {
            lastEQ = eq
            lastEQRate = sampleRate
            lowFilter.setLowShelf(sampleRate: sampleRate, cutoffHz: 100.0, gainDB: eq.lowGainDB)
            midFilter.setPeaking(sampleRate: sampleRate, freqHz: 1000.0, Q: 1.0, gainDB: eq.midGainDB)
            highFilter.setHighShelf(sampleRate: sampleRate, cutoffHz: 8000.0, gainDB: eq.highGainDB)

            }
            lowFilter.processBlock(buffer, frames: frames)
            midFilter.processBlock(buffer, frames: frames)
            highFilter.processBlock(buffer, frames: frames)
        }

        if !isVirtual { padDSP.process(buffer: buffer, frames: frames, rate: sampleRate, mode: padMode,
                                      state: padMode == .intellipan ? intellipan : padState, smooth: pitchSmooth) }
        // Only the hardware color PAD uses its horizontal coordinate as balance.
        // Virtual strips pan with StripSettings.pan in the mixer; a legacy
        // intellipan.x there would otherwise be a hidden second balance stage.
        let pan = max(-1.0, min(1.0, (!isVirtual && padMode == .intellipan) ? intellipan.x : 0))
        let panL = cosf(max(0, pan) * Float.pi / 2.0)
        let panR = cosf(max(0, -pan) * Float.pi / 2.0)

        // Gain smoothing (ramping over frame buffer to avoid clicks)
        let gainStep = (targetGainLinear - currentGainLinear) / Float(max(frames, 1))

        for i in 0..<frames {
            currentGainLinear += gainStep
            let l = buffer[i * 2] * currentGainLinear * panL
            let r = buffer[i * 2 + 1] * currentGainLinear * panR
            buffer[i * 2] = l
            buffer[i * 2 + 1] = r
        }
        currentGainLinear = targetGainLinear
    }
}

/// Master Bus DSP (Gain, Bus Mode, 6-band Parametric EQ, Limiter)
public final class BusDSP {
    private var currentGainLinear: Float = 1.0
    private var targetGainLinear: Float = 1.0
    private var eq = ParametricEQ6Band()

    public private(set) var limiterReductionDB: Float = 0
    private var limiterHoldFrames = 0
    private let lookaheadCapacity = 8192
    private var lookaheadAudio = [Float](repeating:0,count:16384)
    private var peakValues = [Float](repeating:0,count:8192)
    private var peakTimes = [Int64](repeating:0,count:8192)
    private var peakHead = 0, peakTail = 0, lookaheadFrames = 0
    private var lookaheadTime: Int64 = 0
    private var lookaheadGain: Float = 1
    // Moving average of the released gain over the lookahead window: the attack ramps
    // linearly across the window and still reaches the required gain at the peak.
    private var gainWindow = [Float](repeating: 1, count: 8192)
    private var gainWindowSum: Double = 0
    private var gainWindowIndex = 0
    public static func limiterLatency(sampleRate: Float, milliseconds: Double, enabled: Bool = true) -> Int {
        guard enabled, milliseconds.isFinite else { return 0 }
        return min(8190,max(0,Int(Double(sampleRate)*min(20,max(0,milliseconds))/1000)))
    }
    private func resetLookahead(_ frames: Int) {
        lookaheadFrames = frames; lookaheadTime = 0; peakHead = 0; peakTail = 0; lookaheadGain = 1
        for i in lookaheadAudio.indices { lookaheadAudio[i] = 0 }
        for i in gainWindow.indices { gainWindow[i] = 1 }
        gainWindowSum = Double(frames + 1); gainWindowIndex = 0
    }

    public init() {}

    public func reset() {
        limiterReductionDB = 0; limiterHoldFrames = 0
        eq.reset(); resetLookahead(0)
    }

    public func process(
        buffer: UnsafeMutablePointer<Float>,
        frames: Int,
        sampleRate: Float,
        gainDB: Float,
        isMuted: Bool,
        mode: BusMode,
        isEQEnabled: Bool = false,
        eqConfig: MasterEQConfig = MasterEQConfig(),
        limiterEnabled: Bool = true
    ) {
        if isEQEnabled { processEQ(buffer: buffer, frames: frames, sampleRate: sampleRate, config: eqConfig) }
        if isMuted || gainDB <= -59.5 {
            targetGainLinear = 0.0
        } else {
            targetGainLinear = powf(10.0, gainDB / 20.0)
        }

        let gainStep = (targetGainLinear - currentGainLinear) / Float(max(frames, 1))

        for i in 0..<frames {
            currentGainLinear += gainStep
            var l = buffer[i * 2] * currentGainLinear
            var r = buffer[i * 2 + 1] * currentGainLinear

            // Bus Mode processing
            switch mode {
            case .normal:
                break
            case .mixdown:
                let mono = (l + r) * 0.7071
                l = mono
                r = mono
            case .mono:
                let mono = (l + r) * 0.5
                l = mono
                r = mono
            }

            if !l.isFinite { l = 0 }
            if !r.isFinite { r = 0 }

            buffer[i * 2] = l
            buffer[i * 2 + 1] = r
        }
        currentGainLinear = targetGainLinear
        if limiterEnabled { processLimiter(buffer: buffer, frames: frames, sampleRate: sampleRate) }
    }

    public func processEQ(buffer: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Float, config: MasterEQConfig) {
        eq.update(config: config, sampleRate: sampleRate)
        eq.process(buffer: buffer, frames: frames)
    }

    /// Zero-lookahead soft knee, preserving the original transfer curve by default.
    public func processLimiter(buffer: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Float,
                               enabled: Bool = true, thresholdDB: Float = -0.91515, ceilingDB: Float = 0, lookaheadMS: Double = 0) {
        let delay = Self.limiterLatency(sampleRate: sampleRate, milliseconds: lookaheadMS, enabled: enabled)
        if delay != lookaheadFrames { resetLookahead(delay) }
        guard enabled else { limiterReductionDB = 0; limiterHoldFrames = 0; return }
        let ceiling = powf(10, min(0, max(-24, ceilingDB.isFinite ? ceilingDB : 0)) / 20)
        let threshold = min(ceiling, powf(10, min(0, max(-36, thresholdDB.isFinite ? thresholdDB : -0.91515)) / 20))
        let knee = max(0.000001, ceiling - threshold)
        var maximumRatio: Float = 1
        if delay > 0 {
            let release = expf(-1 / max(1,sampleRate*0.05))
            for i in 0..<frames {
                let time = lookaheadTime, index = Int(time % Int64(lookaheadCapacity))
                let l = buffer[i*2].isFinite ? buffer[i*2] : 0, r = buffer[i*2+1].isFinite ? buffer[i*2+1] : 0
                lookaheadAudio[index*2] = l; lookaheadAudio[index*2+1] = r
                let peak = max(abs(l),abs(r))
                while peakHead != peakTail && peakTimes[peakHead] < time-Int64(delay) { peakHead = (peakHead+1)%lookaheadCapacity }
                while peakHead != peakTail {
                    let previous = (peakTail+lookaheadCapacity-1)%lookaheadCapacity
                    if peakValues[previous] > peak { break }
                    peakTail = previous
                }
                peakValues[peakTail] = peak; peakTimes[peakTail] = time; peakTail = (peakTail+1)%lookaheadCapacity
                let maximum = peakValues[peakHead]
                let limited = maximum > threshold ? min(ceiling,threshold+knee*tanhf((maximum-threshold)/knee)) : maximum
                let target = maximum > 0 ? limited/maximum : 1
                lookaheadGain = target < lookaheadGain ? target : release*lookaheadGain+(1-release)*target
                // Every released gain in the last delay+1 samples is <= the gain the delayed
                // output sample requires, so their mean is too (ceiling still holds).
                gainWindowSum += Double(lookaheadGain - gainWindow[gainWindowIndex])
                gainWindow[gainWindowIndex] = lookaheadGain
                gainWindowIndex = gainWindowIndex == delay ? 0 : gainWindowIndex + 1
                let gain = Float(gainWindowSum / Double(delay + 1))
                let read = Int((time-Int64(delay)+Int64(lookaheadCapacity))%Int64(lookaheadCapacity))
                buffer[i*2] = lookaheadAudio[read*2]*gain
                buffer[i*2+1] = lookaheadAudio[read*2+1]*gain
                maximumRatio = max(maximumRatio,1/max(0.000001,gain))
                lookaheadTime += 1
            }
        } else { for i in 0..<(frames * 2) {
            let input = buffer[i]
            guard input.isFinite else { buffer[i] = 0; continue }
            let magnitude = abs(input)
            if magnitude > threshold {
                let output = min(ceiling, threshold + knee * tanhf((magnitude - threshold) / knee))
                buffer[i] = copysignf(output, input)
                maximumRatio = max(maximumRatio, magnitude / max(0.000001, output))
            }
        }
        }
        let reduction = 20 * log10f(maximumRatio)
        if reduction > 0.001 {
            limiterReductionDB = reduction; limiterHoldFrames = Int(sampleRate * 0.15)
        } else {
            limiterHoldFrames = max(0, limiterHoldFrames - frames)
            if limiterHoldFrames == 0 { limiterReductionDB = 0 }
        }
    }
}

/// Audio Metering Helper (computes Peak & RMS in dB)
public struct MeterCalculator {
    public static func compute(
        buffer: UnsafePointer<Float>,
        frames: Int,
        previousPeakL: Float,
        previousPeakR: Float,
        sampleRate: Float = 48000
    ) -> MeterLevel {
        if frames <= 0 {
            return MeterLevel()
        }

        var maxL: Float = 0.0
        var maxR: Float = 0.0
        var sumSqL: Float = 0.0
        var sumSqR: Float = 0.0
        let count = vDSP_Length(frames)
        vDSP_maxmgv(buffer, 2, &maxL, count)
        vDSP_maxmgv(buffer + 1, 2, &maxR, count)
        vDSP_svesq(buffer, 2, &sumSqL, count)
        vDSP_svesq(buffer + 1, 2, &sumSqR, count)

        let rmsL = sqrtf(sumSqL / Float(frames))
        let rmsR = sqrtf(sumSqR / Float(frames))

        let peakLDB = maxL > 1e-5 ? 20.0 * log10f(maxL) : -100.0
        let peakRDB = maxR > 1e-5 ? 20.0 * log10f(maxR) : -100.0
        let rmsLDB = rmsL > 1e-5 ? 20.0 * log10f(rmsL) : -100.0
        let rmsRDB = rmsR > 1e-5 ? 20.0 * log10f(rmsR) : -100.0

        // Peak fall is time-based (1.2 dB per 256 frames at 48 kHz), so the
        // meter ballistics no longer change with the device buffer size.
        let decay = 1.2 * Float(frames) / 256 * 48000 / max(8000, sampleRate.isFinite ? sampleRate : 48000)
        let decayedPeakL = max(peakLDB, previousPeakL - decay)
        let decayedPeakR = max(peakRDB, previousPeakR - decay)

        return MeterLevel(
            leftPeakDB: decayedPeakL,
            rightPeakDB: decayedPeakR,
            leftRMSDB: rmsLDB,
            rightRMSDB: rmsRDB
        )
    }
}
