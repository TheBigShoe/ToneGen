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

    // MARK: - Helpers

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
