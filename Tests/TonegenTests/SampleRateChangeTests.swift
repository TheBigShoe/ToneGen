// A renderer moved to a new hardware rate must keep generating the requested signal.
import AVFoundation
import XCTest
@testable import Tonegen

final class SampleRateChangeTests: XCTestCase {
    // MARK: - Frequency after a rate change

    func testFrequencyIsCorrectAfterMovingTo44k1() {
        assertFrequencyAfterMove(to: 44100, frequency: 997)
    }

    func testFrequencyIsCorrectAfterMovingTo96k() {
        assertFrequencyAfterMove(to: 96000, frequency: 997)
    }

    func testHighFrequencyIsCorrectAfterMovingTo44k1() {
        assertFrequencyAfterMove(to: 44100, frequency: 15000)
    }

    // MARK: - Carry-over

    func testSmoothedValuesCarryOverRateChange() {
        let (renderer, _) = makeRenderer(
            sampleRate: 48000,
            configure: {
                $0.left.frequencyHz = 1234
                $0.right.frequencyHz = 5678
                $0.left.amplitudeDbfs = -6
                $0.right.amplitudeDbfs = -18
                $0.left.phaseFraction = 0.25
                $0.masterGainDbfs = -3
            }
        )
        _ = render(renderer, frames: 48000)
        let before = renderer.smoothedState

        renderer.setSampleRate(44100)
        let after = renderer.smoothedState

        XCTAssertEqual(after.frequencyHzL, before.frequencyHzL)
        XCTAssertEqual(after.frequencyHzR, before.frequencyHzR)
        XCTAssertEqual(after.amplitudeDbL, before.amplitudeDbL)
        XCTAssertEqual(after.amplitudeDbR, before.amplitudeDbR)
        XCTAssertEqual(after.phaseL, before.phaseL)
        XCTAssertEqual(after.masterDb, before.masterDb)
        XCTAssertEqual(after.accumulatorL, before.accumulatorL)
        XCTAssertEqual(after.accumulatorR, before.accumulatorR)

        // One buffer later the values must still be the user's, not a glide from defaults.
        _ = render(renderer, frames: 256)
        let next = renderer.smoothedState
        XCTAssertEqual(next.frequencyHzL, 1234, accuracy: 0.01)
        XCTAssertEqual(next.frequencyHzR, 5678, accuracy: 0.05)
        XCTAssertEqual(next.amplitudeDbL, -6, accuracy: 1e-4)
        XCTAssertEqual(next.masterDb, -3, accuracy: 1e-4)
        XCTAssertEqual(next.phaseL, 0.25, accuracy: 1e-4)
    }

    /// A glide in progress continues from where it was rather than restarting.
    func testGlideInProgressContinuesAcrossRateChange() {
        let (renderer, bridge) = makeRenderer(sampleRate: 48000) { $0.left.frequencyHz = 100 }
        _ = render(renderer, frames: 48000)

        var params = EngineParams()
        params.playing = true
        params.left.frequencyHz = 1600
        bridge.update(params)
        _ = render(renderer, frames: 480) // 10 ms of a 20 ms glide
        let midGlide = renderer.smoothedState.frequencyHzL
        XCTAssertGreaterThan(midGlide, 100)
        XCTAssertLessThan(midGlide, 1600)

        renderer.setSampleRate(96000)
        XCTAssertEqual(renderer.smoothedState.frequencyHzL, midGlide)
        _ = render(renderer, frames: 1)
        XCTAssertGreaterThanOrEqual(renderer.smoothedState.frequencyHzL, midGlide)
    }

    /// The envelope restarts from silence so the restarted hardware fades in, not clicks.
    func testOutputFadesBackInAfterRateChange() {
        let (renderer, _) = makeRenderer(sampleRate: 48000) { $0.left.frequencyHz = 1000 }
        _ = render(renderer, frames: 48000)
        XCTAssertEqual(renderer.smoothedState.envelope, 1)

        renderer.setSampleRate(44100)
        XCTAssertEqual(renderer.smoothedState.envelope, 0)

        let out = render(renderer, frames: 44)
        XCTAssertLessThan(abs(out[0]), 0.01, "first sample after a rate change must be silent")
    }

    func testSameRateIsANoOp() {
        let (renderer, _) = makeRenderer(sampleRate: 48000) { $0.left.frequencyHz = 1000 }
        _ = render(renderer, frames: 4800)
        let before = renderer.smoothedState
        renderer.setSampleRate(48000)
        XCTAssertEqual(renderer.smoothedState, before)
    }

    func testInvalidRatesAreIgnored() {
        let (renderer, _) = makeRenderer(sampleRate: 48000) { _ in }
        renderer.setSampleRate(0)
        renderer.setSampleRate(-44100)
        renderer.setSampleRate(.nan)
        renderer.setSampleRate(.infinity)
        XCTAssertEqual(renderer.sampleRate, 48000)
    }

    // MARK: - Time constants at the new rate

    func testSmootherTimeConstantFollowsRate() {
        for rate: Float in [44100, 96000] {
            var s = Smoother(initial: 0, sampleRate: 48000, timeConstantMs: 20)
            s.setSampleRate(rate)
            s.target = 1
            let tauSamples = Int((0.020 * rate).rounded())
            for _ in 0 ..< tauSamples {
                _ = s.next()
            }
            XCTAssertEqual(s.value, 1 - expf(-1), accuracy: 0.001, "rate \(rate)")
        }
    }

    func testPhaseSmootherTimeConstantFollowsRate() {
        for rate: Float in [44100, 96000] {
            var s = PhaseSmoother(initial: 0, sampleRate: 48000, timeConstantMs: 30)
            s.setSampleRate(rate)
            s.target = 0.2
            let tauSamples = Int((0.030 * rate).rounded())
            for _ in 0 ..< tauSamples {
                _ = s.next()
            }
            XCTAssertEqual(s.value, 0.2 * (1 - expf(-1)), accuracy: 0.0005, "rate \(rate)")
        }
    }

    /// The renderer's own smoothers are retuned: the 5 ms envelope and the 20 ms
    /// frequency glide take the same time in milliseconds at the new rate.
    func testRendererSmoothersUseNewRate() {
        let (renderer, bridge) = makeRenderer(sampleRate: 48000) { $0.left.frequencyHz = 100 }
        _ = render(renderer, frames: 48000)

        renderer.setSampleRate(96000)
        _ = render(renderer, frames: 480) // 5 ms at 96 kHz
        XCTAssertEqual(renderer.smoothedState.envelope, 1 - expf(-1), accuracy: 0.002)

        var params = EngineParams()
        params.playing = true
        params.left.frequencyHz = 400 // two octaves up
        bridge.update(params)
        _ = render(renderer, frames: 1920) // 20 ms at 96 kHz
        let octaves = log2f(renderer.smoothedState.frequencyHzL / 100)
        XCTAssertEqual(octaves, 2 * (1 - expf(-1)), accuracy: 0.005)
    }

    // MARK: - Crossfade

    func testFadeLengthFollowsRate() {
        XCTAssertEqual(ToneRenderer.fadeLength(sampleRate: 44100), 220)
        XCTAssertEqual(ToneRenderer.fadeLength(sampleRate: 48000), 240)
        XCTAssertEqual(ToneRenderer.fadeLength(sampleRate: 96000), 480)
    }

    func testCrossfadeKeepsBlendPositionWhenLengthChanges() {
        var xf = WaveformCrossfade(initial: .sine, length: 240)
        var weight: Float = 0
        for _ in 0 ..< 120 {
            weight = xf.next(requested: .square)
        }
        XCTAssertEqual(weight, 0.5, accuracy: 0.01)

        xf.setLength(480)
        let resumed = xf.next(requested: .square)
        XCTAssertEqual(resumed, 0.5, accuracy: 0.01)
        XCTAssertEqual(xf.length, 480)

        var steps = 1
        while xf.next(requested: .square) < 1 {
            steps += 1
        }
        XCTAssertEqual(steps, 240, accuracy: 2, "remaining half of a 480-sample fade")
    }

    // MARK: - Helpers

    private func assertFrequencyAfterMove(
        to rate: Float,
        frequency: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (renderer, _) = makeRenderer(sampleRate: 48000) {
            $0.left.frequencyHz = frequency
            $0.right.frequencyHz = frequency
        }
        _ = render(renderer, frames: 24000)
        renderer.setSampleRate(rate)
        XCTAssertEqual(renderer.sampleRate, rate, file: file, line: line)

        let out = render(renderer, frames: Int(rate))
        // Skip the 5 ms fade-in; it changes amplitude, not zero-crossing spacing, but
        // keeping it out leaves only steady-state cycles in the measurement.
        let steady = Array(out[Int(rate * 0.01)...])
        let measured = Self.risingCrossingFrequency(steady, sampleRate: rate)
        XCTAssertEqual(measured, frequency, accuracy: frequency * 1e-4, file: file, line: line)
    }

    /// Frequency from the spacing of the first and last rising zero crossings, each
    /// located to sub-sample accuracy by linear interpolation.
    private static func risingCrossingFrequency(_ x: [Float], sampleRate: Float) -> Float {
        var first: Double?
        var last = 0.0
        var count = 0
        for n in 1 ..< x.count where x[n - 1] < 0 && x[n] >= 0 {
            let frac = Double(-x[n - 1] / (x[n] - x[n - 1]))
            let t = Double(n - 1) + frac
            if first == nil { first = t }
            last = t
            count += 1
        }
        guard let first, count > 1 else { return 0 }
        return Float(Double(count - 1) / (last - first) * Double(sampleRate))
    }

    private func makeRenderer(
        sampleRate: Float,
        configure: (inout EngineParams) -> Void
    ) -> (ToneRenderer, ParamsBridge) {
        let bridge = ParamsBridge()
        var params = EngineParams()
        params.playing = true
        configure(&params)
        bridge.update(params)
        return (ToneRenderer(sampleRate: sampleRate, bridge: bridge), bridge)
    }

    /// Renders `frames` frames in 256-frame buffers, as the hardware would, and returns L.
    private func render(_ renderer: ToneRenderer, frames: Int) -> [Float] {
        let block = 256
        var left = [Float](repeating: 0, count: block)
        var right = [Float](repeating: 0, count: block)
        var out: [Float] = []
        out.reserveCapacity(frames)
        var done = 0
        while done < frames {
            let n = min(block, frames - done)
            left.withUnsafeMutableBufferPointer { lPtr in
                right.withUnsafeMutableBufferPointer { rPtr in
                    let abl = AudioBufferList.allocate(maximumBuffers: 2)
                    defer { free(abl.unsafeMutablePointer) }
                    let bytes = UInt32(n * MemoryLayout<Float>.size)
                    abl[0] = AudioBuffer(
                        mNumberChannels: 1, mDataByteSize: bytes, mData: lPtr.baseAddress
                    )
                    abl[1] = AudioBuffer(
                        mNumberChannels: 1, mDataByteSize: bytes, mData: rPtr.baseAddress
                    )
                    var silence: ObjCBool = false
                    renderer.render(frames: n, buffers: abl.unsafeMutablePointer, silence: &silence)
                }
            }
            out.append(contentsOf: left[0 ..< n])
            done += n
        }
        return out
    }
}
