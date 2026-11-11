// Real-time render block — runs on the audio I/O thread. No allocation, no locks that block.
import AVFoundation
import os

/// Produces stereo audio for all waveform types. Called from AVAudioSourceNode's render closure.
final class ToneRenderer {
    /// Mute envelope — 5 ms ramp on play/pause.
    private var muteEnv: Smoother

    // Per-channel frequency smoothers — targets and values are in log₂(Hz).
    // Smoothing in the log domain keeps octave steps perceptually symmetric.
    private var freqSmL: Smoother
    private var freqSmR: Smoother

    // Per-channel amplitude smoothers — targets and values are dBFS, clamped to
    // `gainFloorDb`. Smoothing in dB makes a gain drag sound even across the range;
    // the linear factor is derived per sample from the smoothed value.
    private var ampSmL: Smoother
    private var ampSmR: Smoother

    // Per-channel mute gates — linear 0…1. Mute is a gate, not a level: driving the dB
    // smoother to the floor would collapse most of the fade into its first millisecond,
    // whereas a linear gate fades evenly and lands on exactly 0 (the smoother snaps).
    private var muteGateL: Smoother
    private var muteGateR: Smoother

    // Per-channel phase-offset smoothers — values are fractions in [0, 1), moving the
    // short way round the circle so a 0.95 → 0.05 change doesn't sweep through 0.5.
    private var phaseSmL: PhaseSmoother
    private var phaseSmR: PhaseSmoother

    /// Master gain smoother — dBFS, same treatment as the channel amplitudes.
    private var masterAmpSm: Smoother

    // Phase accumulators — continuous, never reset.
    private var oscL: PhaseOscillator
    private var oscR: PhaseOscillator

    // Per-channel waveform crossfades — a waveform change blends old into new over 5 ms
    // instead of cutting, which would step the output by up to the full peak-to-peak.
    private var xfadeL: WaveformCrossfade
    private var xfadeR: WaveformCrossfade

    // L and R noise generators use separate seeds so the streams are uncorrelated.
    private var whiteL = WhiteNoise(state: 0x1234_5678)
    private var whiteR = WhiteNoise(state: 0x8765_4321)
    private var pinkL = PinkNoise(seed: 0x1234_5678)
    private var pinkR = PinkNoise(seed: 0x8765_4321)

    private let bridge: ParamsBridge
    private var lastParams = EngineParams()

    /// Scope feeds — written once per render block, read by the display thread at ~60 Hz.
    let scopeL = SampleRingBuffer(capacity: 4096)
    let scopeR = SampleRingBuffer(capacity: 4096)

    init(sampleRate: Float, bridge: ParamsBridge) {
        let sr = sampleRate
        oscL = PhaseOscillator(sampleRate: sr)
        oscR = PhaseOscillator(sampleRate: sr)
        muteEnv = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 5)
        freqSmL = Smoother(initial: log2f(440), sampleRate: sr, timeConstantMs: 20)
        freqSmR = Smoother(initial: log2f(440), sampleRate: sr, timeConstantMs: 20)
        ampSmL = Smoother(initial: -12, sampleRate: sr, timeConstantMs: 10)
        ampSmR = Smoother(initial: -12, sampleRate: sr, timeConstantMs: 10)
        muteGateL = Smoother(initial: 1, sampleRate: sr, timeConstantMs: 10)
        muteGateR = Smoother(initial: 1, sampleRate: sr, timeConstantMs: 10)
        phaseSmL = PhaseSmoother(initial: 0, sampleRate: sr, timeConstantMs: 30)
        phaseSmR = PhaseSmoother(initial: 0, sampleRate: sr, timeConstantMs: 30)
        masterAmpSm = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 10)
        let fadeLength = max(1, Int(sr * Self.waveformFadeSeconds))
        xfadeL = WaveformCrossfade(initial: .sine, length: fadeLength)
        xfadeR = WaveformCrossfade(initial: .sine, length: fadeLength)
        self.bridge = bridge
    }

    /// Called on the real-time audio thread — must not allocate, block, or dispatch.
    func render(
        frames: Int,
        buffers: UnsafeMutablePointer<AudioBufferList>,
        silence: UnsafeMutablePointer<ObjCBool>
    ) {
        // Snapshot params once per buffer to avoid per-sample lock overhead.
        if let params = bridge.snapshot() {
            lastParams = params
        }
        let p = lastParams
        applyTargets(p)

        let abl = UnsafeMutableAudioBufferListPointer(buffers)
        guard abl.count >= 2,
              let rawL = abl[0].mData,
              let rawR = abl[1].mData
        else {
            silence.pointee = true
            return
        }

        let outL = rawL.bindMemory(to: Float.self, capacity: frames)
        let outR = rawR.bindMemory(to: Float.self, capacity: frames)
        let waveL = p.left.waveform
        let waveR = p.right.waveform
        let sr = oscL.sampleRate

        // While the output is fully gated there is nothing to click, so a waveform change
        // takes effect at once (this also covers the very first buffer after launch).
        if muteEnv.value == 0 || muteGateL.value == 0 {
            xfadeL.jump(to: waveL)
        }
        if muteEnv.value == 0 || muteGateR.value == 0 {
            xfadeR.jump(to: waveR)
        }

        for n in 0 ..< frames {
            let env = muteEnv.next()
            let freqL = exp2f(freqSmL.next())
            let freqR = exp2f(freqSmR.next())
            let ampL = Self.dbToGain(ampSmL.next()) * muteGateL.next()
            let ampR = Self.dbToGain(ampSmR.next()) * muteGateR.next()
            let masterAmp = Self.dbToGain(masterAmpSm.next())
            let phL = phaseSmL.next()
            let phR = phaseSmR.next()

            // Both accumulators advance every sample, even while a channel plays noise.
            // Skipping one would leave L and R at an arbitrary offset once the channel
            // returns to a tonal waveform, breaking the phase control.
            let tL = oscL.step(frequency: freqL)
            let tR = oscR.step(frequency: freqR)

            let sL = Self.channelSample(
                &xfadeL,
                requested: waveL,
                phase: Self.offsetPhase(tL, phL),
                dt: freqL / sr,
                white: &whiteL,
                pink: &pinkL
            )
            let sR = Self.channelSample(
                &xfadeR,
                requested: waveR,
                phase: Self.offsetPhase(tR, phR),
                dt: freqR / sr,
                white: &whiteR,
                pink: &pinkR
            )

            let outSampleL = sL * ampL * masterAmp * env
            let outSampleR = sR * ampR * masterAmp * env
            outL[n] = outSampleL
            outR[n] = outSampleR
        }

        // One publish per channel per buffer keeps lock traffic off the per-sample path.
        scopeL.write(UnsafeBufferPointer(start: outL, count: frames))
        scopeR.write(UnsafeBufferPointer(start: outR, count: frames))

        silence.pointee = false
    }

    /// Points every smoother at the snapshot's values; called once per buffer.
    private func applyTargets(_ p: EngineParams) {
        muteEnv.target = p.playing ? 1 : 0
        freqSmL.target = log2f(max(p.left.frequencyHz, 1))
        freqSmR.target = log2f(max(p.right.frequencyHz, 1))
        ampSmL.target = max(p.left.amplitudeDbfs, Self.gainFloorDb)
        ampSmR.target = max(p.right.amplitudeDbfs, Self.gainFloorDb)
        muteGateL.target = p.left.muted ? 0 : 1
        muteGateR.target = p.right.muted ? 0 : 1
        phaseSmL.target = p.left.phaseFraction
        phaseSmR.target = p.right.phaseFraction
        masterAmpSm.target = max(p.masterGainDbfs, Self.gainFloorDb)
    }

    // MARK: - Phase

    /// Applies the user phase offset to the accumulator phase. Both inputs are in [0, 1),
    /// so one conditional subtract replaces `fmod` and the result stays in [0, 1).
    @inline(__always)
    static func offsetPhase(_ t: Float, _ offset: Float) -> Float {
        let p = t + offset
        return p >= 1 ? p - 1 : p
    }

    // MARK: - Gain

    /// Gain floor. Levels at or below it are treated as true silence rather than −120 dB.
    static let gainFloorDb: Float = -120

    /// log₂(10) / 20 — lets `exp2f` stand in for `pow(10, dB / 20)`, which it equals
    /// exactly in real arithmetic but evaluates more cheaply per sample.
    private static let dbToLog2Gain: Float = 0.166_096_4

    /// Converts a smoothed dBFS value to the linear sample multiplier.
    ///
    /// Returns exactly 0 at the floor so a level parked there is digital silence; the
    /// smoother snaps onto the floor, so the hand-off from 1e-6 to 0 is a −120 dB step.
    @inline(__always)
    static func dbToGain(_ db: Float) -> Float {
        db <= gainFloorDb ? 0 : exp2f(db * dbToLog2Gain)
    }

    // MARK: - Waveforms — t ∈ [0,1), output ∈ [-1, 1]

    /// Duration of the crossfade applied when a channel's waveform changes.
    static let waveformFadeSeconds: Float = 0.005

    /// One sample of a channel's output waveform, blending old into new while `xfade` runs.
    @inline(__always)
    private static func channelSample(
        _ xfade: inout WaveformCrossfade,
        requested: Waveform,
        phase t: Float,
        dt: Float,
        white: inout WhiteNoise,
        pink: inout PinkNoise
    ) -> Float {
        let mix = xfade.next(requested: requested)
        let new = sample(xfade.current, phase: t, dt: dt, white: &white, pink: &pink)
        guard mix < 1 else { return new }
        let old = sample(xfade.previous, phase: t, dt: dt, white: &white, pink: &pink)
        return old + mix * (new - old)
    }

    /// One sample of `wave`. Noise generators are passed in so each channel keeps its own
    /// uncorrelated stream; they advance only while their waveform is audible.
    @inline(__always)
    private static func sample(
        _ wave: Waveform,
        phase t: Float,
        dt: Float,
        white: inout WhiteNoise,
        pink: inout PinkNoise
    ) -> Float {
        switch wave {
        case .whiteNoise: white.next()
        case .pinkNoise: pink.next()
        default: tonal(wave, phase: t, dt: dt)
        }
    }

    @inline(__always)
    private static func tonal(_ wave: Waveform, phase t: Float, dt: Float) -> Float {
        switch wave {
        case .sine: sinf(2 * .pi * t)
        case .square: squareBLEP(t, dt: dt)
        case .triangle: triangleBLAMP(t, dt: dt)
        case .saw: sawBLEP(t, dt: dt)
        default: 0
        }
    }
}

/// Click-free waveform switching for one channel.
///
/// A change of requested waveform starts a linear crossfade from the old waveform to the
/// new one over `length` samples. Requests that arrive mid-fade wait until it completes
/// and then start a fresh fade, so the blend weight never jumps. Value type with no
/// storage beyond its fields — safe on the render thread.
struct WaveformCrossfade {
    /// Waveform being faded in (or playing alone once the fade completes).
    private(set) var current: Waveform
    /// Waveform being faded out. Meaningful only while `next` returns < 1.
    private(set) var previous: Waveform
    private var remaining = 0
    private let length: Int
    private let invLength: Float

    init(initial: Waveform, length: Int) {
        current = initial
        previous = initial
        self.length = max(1, length)
        invLength = 1 / Float(self.length)
    }

    /// Advances one sample toward `requested` and returns the weight of `current`;
    /// `previous` gets `1 − weight`. Returns exactly 1 when no fade is running.
    @inline(__always)
    mutating func next(requested: Waveform) -> Float {
        if remaining == 0 {
            if requested == current { return 1 }
            previous = current
            current = requested
            remaining = length
        }
        remaining -= 1
        return 1 - Float(remaining) * invLength
    }

    /// Switches immediately with no fade — only for when the output is silent anyway.
    mutating func jump(to wave: Waveform) {
        current = wave
        previous = wave
        remaining = 0
    }
}
