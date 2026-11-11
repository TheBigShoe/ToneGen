// Verifies smoothed parameters in the render path settle at expected time constants.
import Accelerate
import AVFoundation
import XCTest
@testable import Tonegen

final class ParameterSmoothingTests: XCTestCase {
    private let sampleRate: Float = 48000

    // MARK: - Mute envelope

    func testMuteEnvelopeSettlesAfterFiveTau() {
        // After 5τ (5 × 5 ms = 25 ms = 1200 samples), the mute envelope should be at
        // least 99% open. Render 1200 samples with playing=true and measure the RMS.
        let bridge = makeBridge(playing: true, waveform: .sine, freq: 440)
        let renderer = ToneRenderer(sampleRate: sampleRate, bridge: bridge)

        let warmup = 1200
        var throwawayL = [Float](repeating: 0, count: warmup)
        var throwawayR = [Float](repeating: 0, count: warmup)
        renderBlock(renderer, left: &throwawayL, right: &throwawayR)

        // After warm-up the envelope is open; 1200 more samples should be near full amplitude.
        let measure = 4800
        var left = [Float](repeating: 0, count: measure)
        var right = [Float](repeating: 0, count: measure)
        renderBlock(renderer, left: &left, right: &right)

        // Expected RMS for a -12 dBFS sine: A_peak/√2 ≈ 0.2512/1.414 ≈ 0.1777.
        let expectedRms: Float = pow(10, Float(-12) / 20) / .sqrt(2)
        let rmsL = rms(left)
        XCTAssertEqual(
            rmsL,
            expectedRms,
            accuracy: expectedRms * 0.02,
            "RMS should be within 2% of expected after mute envelope settles"
        )
    }

    func testMutedOutputIsZero() {
        let bridge = makeBridge(playing: false, waveform: .sine, freq: 440)
        let renderer = ToneRenderer(sampleRate: sampleRate, bridge: bridge)

        var left = [Float](repeating: 0, count: 48000)
        var right = [Float](repeating: 0, count: 48000)
        renderBlock(renderer, left: &left, right: &right)

        XCTAssertEqual(rms(left), 0, accuracy: 1e-6)
    }

    // MARK: - Frequency smoothing

    func testFrequencySmoothingFollowsChange() {
        // Start at 440 Hz, switch to 880 Hz, and verify the output after 5τ (100 ms)
        // has settled to 880 Hz using the Goertzel algorithm.
        let bridge = makeBridge(playing: true, waveform: .sine, freq: 440)
        let renderer = ToneRenderer(sampleRate: sampleRate, bridge: bridge)

        // Let the mute envelope fully open.
        var warmupL = [Float](repeating: 0, count: 1200)
        var warmupR = [Float](repeating: 0, count: 1200)
        renderBlock(renderer, left: &warmupL, right: &warmupR)

        // Switch to 880 Hz and wait 5τ = 100 ms = 4800 samples for the smoother to settle.
        var updated = EngineParams()
        updated.playing = true
        updated.left.frequencyHz = 880
        updated.right.frequencyHz = 880
        updated.left.waveform = .sine
        updated.right.waveform = .sine
        bridge.update(updated)

        var settleL = [Float](repeating: 0, count: 4800)
        var settleR = [Float](repeating: 0, count: 4800)
        renderBlock(renderer, left: &settleL, right: &settleR)

        // Measure at both old and new frequencies after settling.
        let n = 48000
        var measure = [Float](repeating: 0, count: n)
        var discard = [Float](repeating: 0, count: n)
        renderBlock(renderer, left: &measure, right: &discard)

        let amp440 = goertzel(samples: measure, hz: 440)
        let amp880 = goertzel(samples: measure, hz: 880)
        XCTAssertGreaterThan(
            amp880,
            amp440 * 10,
            "After settling, 880 Hz should dominate 440 Hz by >20 dB"
        )
    }

    // MARK: - Amplitude smoothing (dB domain)

    func testChannelAmplitudeSmoothsInDecibels() {
        // A 10 Hz square is flat at ±gain between edges, so |sample| reads the gain directly.
        var params = squareParams()
        let (renderer, bridge) = settledRenderer(params)

        params.left.amplitudeDbfs = -48
        bridge.update(params)
        let out = render(renderer, frames: 480) // 1τ at 10 ms

        // dB-domain one-pole after 1τ: −12 + (−36)(1 − e⁻¹) ≈ −34.76 dB.
        // Smoothing linear gain instead would sit near −19.8 dB here.
        let expected: Float = -12 + -36 * (1 - expf(-1))
        XCTAssertEqual(gainDb(out, at: 479), expected, accuracy: 0.3)
    }

    func testMasterGainSmoothsInDecibels() {
        var params = squareParams()
        let (renderer, bridge) = settledRenderer(params)

        params.masterGainDbfs = -40
        bridge.update(params)
        let out = render(renderer, frames: 480)

        let expected: Float = -12 + -40 * (1 - expf(-1))
        XCTAssertEqual(gainDb(out, at: 479), expected, accuracy: 0.3)
    }

    func testChannelMuteIsClickFreeAndTrulySilent() {
        // 10 Hz sine: its own largest sample step is ≈ 3e-4 at −12 dBFS, so any
        // larger step would come from the mute gate itself.
        var params = squareParams()
        params.left.waveform = .sine
        params.right.waveform = .sine
        let (renderer, bridge) = settledRenderer(params)
        let before = render(renderer, frames: 1)

        params.left.muted = true
        bridge.update(params)
        let fade = render(renderer, frames: 14400) // 300 ms
        XCTAssertLessThan(maxStep(before + fade), 0.001, "Mute must ramp, not step")

        let silent = render(renderer, frames: 4800)
        XCTAssertTrue(silent.allSatisfy { $0 == 0 }, "Muted channel must be digital silence")

        params.left.muted = false
        bridge.update(params)
        let reopen = render(renderer, frames: 4800)
        XCTAssertLessThan(maxStep(silent + reopen), 0.001, "Unmute must ramp, not step")
        XCTAssertGreaterThan(reopen.map(abs).max() ?? 0, 0.2, "Unmute must restore the level")
    }

    func testLevelBelowFloorIsTrulySilent() {
        var params = squareParams()
        let (renderer, bridge) = settledRenderer(params)

        params.left.amplitudeDbfs = -200
        bridge.update(params)
        _ = render(renderer, frames: 24000)
        let out = render(renderer, frames: 4800)
        XCTAssertTrue(out.allSatisfy { $0 == 0 }, "Levels at the floor must be digital silence")
    }

    // MARK: - Phase offset smoothing

    func testPhaseOffsetTakesShortestPathAcrossWrap() {
        // L and R are identical sines at 0.95. Moving L to 0.05 is a 0.1-cycle move
        // across the wrap: |L − R| must never exceed 2·A·sin(π·0.1). The long way round
        // would pass through 0.5 (anti-phase), where |L − R| reaches 2·A.
        var params = squareParams()
        params.left.waveform = .sine
        params.right.waveform = .sine
        params.left.frequencyHz = 440
        params.right.frequencyHz = 440
        params.left.phaseFraction = 0.95
        params.right.phaseFraction = 0.95
        let (renderer, bridge) = settledRenderer(params)

        params.left.phaseFraction = 0.05
        bridge.update(params)
        var left = [Float](repeating: 0, count: 14400)
        var right = [Float](repeating: 0, count: 14400)
        renderBlock(renderer, left: &left, right: &right)

        let amp: Float = pow(10, Float(-12) / 20)
        let bound = 2 * amp * sinf(.pi * 0.1) * 1.01
        let maxDiff = zip(left, right).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(maxDiff, bound)
        XCTAssertGreaterThan(maxDiff, bound * 0.9, "L should have moved by 0.1 cycle")
    }

    // MARK: - Helpers

    private func squareParams() -> EngineParams {
        var params = EngineParams()
        params.playing = true
        params.left.waveform = .square
        params.right.waveform = .square
        params.left.frequencyHz = 10
        params.right.frequencyHz = 10
        return params
    }

    /// Renderer that has run long enough (0.5 s = 25τ of the slowest smoother) for every
    /// smoother to have settled on `params`.
    private func settledRenderer(_ params: EngineParams) -> (ToneRenderer, ParamsBridge) {
        let bridge = ParamsBridge()
        bridge.update(params)
        let renderer = ToneRenderer(sampleRate: sampleRate, bridge: bridge)
        _ = render(renderer, frames: 24000)
        return (renderer, bridge)
    }

    /// Renders `frames` samples and returns the left channel.
    private func render(_ renderer: ToneRenderer, frames: Int) -> [Float] {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        renderBlock(renderer, left: &left, right: &right)
        return left
    }

    /// Gain in dB at `index`, read as the median |sample| of a 5-sample window so a
    /// square edge landing in the window cannot skew it.
    private func gainDb(_ samples: [Float], at index: Int) -> Float {
        let window = samples[max(0, index - 4) ... index].map(abs).sorted()
        return 20 * log10f(window[window.count / 2])
    }

    private func maxStep(_ samples: [Float]) -> Float {
        zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    private func makeBridge(playing: Bool, waveform: Waveform, freq: Float) -> ParamsBridge {
        let bridge = ParamsBridge()
        var params = EngineParams()
        params.playing = playing
        params.left.waveform = waveform
        params.right.waveform = waveform
        params.left.frequencyHz = freq
        params.right.frequencyHz = freq
        bridge.update(params)
        return bridge
    }

    private func renderBlock(_ renderer: ToneRenderer, left: inout [Float], right: inout [Float]) {
        let frames = left.count
        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                let abl = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(abl.unsafeMutablePointer) }
                abl[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                    mData: lPtr.baseAddress
                )
                abl[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                    mData: rPtr.baseAddress
                )
                var silence: ObjCBool = false
                renderer.render(
                    frames: frames,
                    buffers: abl.unsafeMutablePointer,
                    silence: &silence
                )
            }
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    private func goertzel(samples: [Float], hz: Float) -> Float {
        let omega = 2 * Double.pi * Double(hz) / Double(sampleRate)
        let coeff = Float(2.0 * cos(omega))
        var q1: Float = 0, q2: Float = 0
        for s in samples {
            let q0 = coeff * q1 - q2 + s
            q2 = q1
            q1 = q0
        }
        let power = q1 * q1 + q2 * q2 - q1 * q2 * coeff
        return sqrt(max(power, 0)) / Float(samples.count / 2)
    }
}

private extension Float {
    static func sqrt(_ x: Float) -> Float {
        Foundation.sqrt(x)
    }
}
