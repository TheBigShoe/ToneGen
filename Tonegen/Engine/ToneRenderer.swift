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

    // Per-channel amplitude smoothers — targets and values are linear (not dBFS).
    // Conversion from dBFS to linear happens once per buffer when updating the target.
    private var ampSmL: Smoother
    private var ampSmR: Smoother

    // Per-channel phase-offset smoothers — values are fractions in [0, 1).
    private var phaseSmL: Smoother
    private var phaseSmR: Smoother

    /// Master gain smoother — linear.
    private var masterAmpSm: Smoother

    // Phase accumulators — continuous, never reset.
    private var oscL: PhaseOscillator
    private var oscR: PhaseOscillator

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
        let initLinAmp = pow(10, Float(-12) / 20) // -12 dBFS default
        oscL = PhaseOscillator(sampleRate: sr)
        oscR = PhaseOscillator(sampleRate: sr)
        muteEnv = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 5)
        freqSmL = Smoother(initial: log2f(440), sampleRate: sr, timeConstantMs: 20)
        freqSmR = Smoother(initial: log2f(440), sampleRate: sr, timeConstantMs: 20)
        ampSmL = Smoother(initial: initLinAmp, sampleRate: sr, timeConstantMs: 10)
        ampSmR = Smoother(initial: initLinAmp, sampleRate: sr, timeConstantMs: 10)
        phaseSmL = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 30)
        phaseSmR = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 30)
        masterAmpSm = Smoother(initial: 1, sampleRate: sr, timeConstantMs: 10)
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

        // Update smoother targets outside the sample loop.
        muteEnv.target = p.playing ? 1 : 0
        freqSmL.target = log2f(max(p.left.frequencyHz, 1))
        freqSmR.target = log2f(max(p.right.frequencyHz, 1))
        ampSmL.target = p.left.muted ? 0 : pow(10, p.left.amplitudeDbfs / 20)
        ampSmR.target = p.right.muted ? 0 : pow(10, p.right.amplitudeDbfs / 20)
        phaseSmL.target = p.left.phaseFraction
        phaseSmR.target = p.right.phaseFraction
        masterAmpSm.target = pow(10, p.masterGainDbfs / 20)

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

        for n in 0 ..< frames {
            let env = muteEnv.next()
            let freqL = exp2f(freqSmL.next())
            let freqR = exp2f(freqSmR.next())
            let ampL = ampSmL.next()
            let ampR = ampSmR.next()
            let masterAmp = masterAmpSm.next()
            let phL = phaseSmL.next()
            let phR = phaseSmR.next()

            // Both accumulators advance every sample, even while a channel plays noise.
            // Skipping one would leave L and R at an arbitrary offset once the channel
            // returns to a tonal waveform, breaking the phase control.
            let tL = oscL.step(frequency: freqL)
            let tR = oscR.step(frequency: freqR)

            let sL: Float
            switch waveL {
            case .whiteNoise: sL = whiteL.next()
            case .pinkNoise: sL = pinkL.next()
            default:
                let dtL = freqL / sr
                sL = Self.tonal(
                    waveL,
                    phase: (tL + phL).truncatingRemainder(dividingBy: 1),
                    dt: dtL
                )
            }

            let sR: Float
            switch waveR {
            case .whiteNoise: sR = whiteR.next()
            case .pinkNoise: sR = pinkR.next()
            default:
                let dtR = freqR / sr
                sR = Self.tonal(
                    waveR,
                    phase: (tR + phR).truncatingRemainder(dividingBy: 1),
                    dt: dtR
                )
            }

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

    // MARK: - Tonal waveforms — t ∈ [0,1), output ∈ [-1, 1]

    @inline(__always)
    private static func tonal(_ wave: Waveform, phase t: Float, dt: Float) -> Float {
        switch wave {
        case .sine: sinf(2 * .pi * t)
        case .square: squareBLEP(t, dt: dt)
        case .triangle: t < 0.5 ? (4 * t - 1) : (3 - 4 * t)
        case .saw: sawBLEP(t, dt: dt)
        default: 0
        }
    }
}
