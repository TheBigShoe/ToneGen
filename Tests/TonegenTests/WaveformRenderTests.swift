// Verifies harmonic structure of each waveform using the Goertzel algorithm.
// Goertzel computes exact magnitude at any specific frequency — no leakage, no bin-alignment
// issues.
import AVFoundation
import XCTest
@testable import Tonegen

final class WaveformRenderTests: XCTestCase {
    private let sampleRate: Float = 48000
    private let frameCount = 48000
    private let fundamental: Float = 440

    // MARK: - Sine: single dominant bin, harmonics at least 40 dB below fundamental

    func testSineIsSingleBin() {
        let f0 = magnitude(waveform: .sine, hz: fundamental)
        let f2 = magnitude(waveform: .sine, hz: fundamental * 2)
        let f3 = magnitude(waveform: .sine, hz: fundamental * 3)
        XCTAssertGreaterThan(f0, 0.1, "Sine should have energy at fundamental")
        XCTAssertLessThan(f2 / f0, 0.01, "Sine 2nd harmonic should be < -40 dB")
        XCTAssertLessThan(f3 / f0, 0.01, "Sine 3rd harmonic should be < -40 dB")
    }

    // MARK: - Saw: harmonics at n × f₀ with amplitude ∝ 1/n

    func testSawHarmonicDecay() {
        let f1 = magnitude(waveform: .saw, hz: fundamental)
        let f2 = magnitude(waveform: .saw, hz: fundamental * 2)
        let f3 = magnitude(waveform: .saw, hz: fundamental * 3)

        XCTAssertEqual(f2 / f1, 1.0 / 2, accuracy: 0.05, "Saw |H2|/|H1| should be 1/2")
        XCTAssertEqual(f3 / f1, 1.0 / 3, accuracy: 0.05, "Saw |H3|/|H1| should be 1/3")
    }

    // MARK: - Square: odd harmonics only, amplitude ∝ 1/(2n+1)

    func testSquareOddHarmonicsOnly() {
        let f3 = magnitude(waveform: .square, hz: fundamental * 3)
        let f2 = magnitude(waveform: .square, hz: fundamental * 2)

        XCTAssertLessThan(f2 / f3, 0.05, "Square even harmonics should be negligible vs odd")
    }

    func testSquareHarmonicDecay() {
        let f1 = magnitude(waveform: .square, hz: fundamental)
        let f3 = magnitude(waveform: .square, hz: fundamental * 3)
        let f5 = magnitude(waveform: .square, hz: fundamental * 5)

        XCTAssertEqual(f3 / f1, 1.0 / 3, accuracy: 0.05, "Square |H3|/|H1| should be 1/3")
        XCTAssertEqual(f5 / f1, 1.0 / 5, accuracy: 0.05, "Square |H5|/|H1| should be 1/5")
    }

    // MARK: - Triangle: odd harmonics, amplitude ∝ 1/(2n+1)²

    func testTriangleHarmonicDecay() {
        let f1 = magnitude(waveform: .triangle, hz: fundamental)
        let f3 = magnitude(waveform: .triangle, hz: fundamental * 3)
        let f5 = magnitude(waveform: .triangle, hz: fundamental * 5)

        XCTAssertEqual(f3 / f1, 1.0 / 9, accuracy: 0.02, "Triangle |H3|/|H1| should be 1/9")
        XCTAssertEqual(f5 / f1, 1.0 / 25, accuracy: 0.01, "Triangle |H5|/|H1| should be 1/25")
    }

    // MARK: - Waveform switching

    func testWaveformChangeCrossfadesInsteadOfStepping() {
        // 2400 samples of 440 Hz is exactly 22 cycles, so the switch lands at t ≈ 0 where
        // the sine is ≈ 0 and the triangle is ≈ −1: a hard cut would step by ≈ the full
        // −12 dBFS peak.
        let switchAt = 2400
        let total = 4800
        let switching = makeRenderer(waveform: .sine)
        var out = renderChunked(switching.renderer, frames: switchAt)
        switching.params.left.waveform = .triangle
        switching.params.right.waveform = .triangle
        switching.bridge.update(switching.params)
        out += renderChunked(switching.renderer, frames: total - switchAt)

        // Same parameters throughout, triangle from the start: what follows the cut.
        let reference = makeRenderer(waveform: .triangle)
        let triangle = renderChunked(reference.renderer, frames: total)
        let hard = Array(out[0 ..< switchAt]) + Array(triangle[switchAt...])

        let hardStep = maxStep(hard, around: switchAt)
        let fadedStep = maxStep(out, around: switchAt)
        XCTAssertGreaterThan(hardStep, 0.15, "Test setup should produce a large hard-cut step")
        XCTAssertLessThan(fadedStep, 0.03, "Crossfade step should be near the waveforms' own slope")
        XCTAssertLessThan(fadedStep, hardStep / 5)

        // Once the 5 ms fade is over the output is exactly the new waveform.
        let fadeEnd = switchAt + Int(sampleRate * ToneRenderer.waveformFadeSeconds)
        for n in fadeEnd ..< total {
            XCTAssertEqual(out[n], triangle[n], accuracy: 1e-6)
        }
    }

    func testWaveformChangeDuringFadeStaysSmooth() {
        // Requests arriving faster than the fade (every 64 samples) must not restart it
        // from a different weight — the blend may never jump.
        let rig = makeRenderer(waveform: .sine)
        var out = renderChunked(rig.renderer, frames: 2400)
        for wave in [Waveform.triangle, .sine, .triangle, .sine, .triangle] {
            rig.params.left.waveform = wave
            rig.params.right.waveform = wave
            rig.bridge.update(rig.params)
            out += renderChunked(rig.renderer, frames: 64)
        }
        out += renderChunked(rig.renderer, frames: 2400)
        XCTAssertLessThan(maxStep(out, around: 2400, radius: 2000), 0.03)
    }

    // MARK: - Helpers

    private final class Rig {
        let bridge: ParamsBridge
        let renderer: ToneRenderer
        var params: EngineParams

        init(bridge: ParamsBridge, renderer: ToneRenderer, params: EngineParams) {
            self.bridge = bridge
            self.renderer = renderer
            self.params = params
        }
    }

    private func makeRenderer(waveform: Waveform) -> Rig {
        let bridge = ParamsBridge()
        var params = EngineParams()
        params.playing = true
        params.left.waveform = waveform
        params.right.waveform = waveform
        params.left.frequencyHz = fundamental
        params.right.frequencyHz = fundamental
        bridge.update(params)
        return Rig(
            bridge: bridge,
            renderer: ToneRenderer(sampleRate: sampleRate, bridge: bridge),
            params: params
        )
    }

    /// Renders the left channel in device-sized 256-frame buffers.
    private func renderChunked(_ renderer: ToneRenderer, frames: Int) -> [Float] {
        var result: [Float] = []
        var done = 0
        while done < frames {
            let n = min(256, frames - done)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            renderBlock(renderer, left: &left, right: &right)
            result += left
            done += n
        }
        return result
    }

    private func maxStep(_ samples: [Float], around index: Int, radius: Int = 400) -> Float {
        let lo = max(1, index - radius)
        let hi = min(samples.count, index + radius)
        return (lo ..< hi).map { abs(samples[$0] - samples[$0 - 1]) }.max() ?? 0
    }

    private func magnitude(waveform: Waveform, hz: Float) -> Float {
        let bridge = ParamsBridge()
        var params = EngineParams()
        params.playing = true
        params.left.waveform = waveform
        params.right.waveform = waveform
        params.left.frequencyHz = fundamental
        params.right.frequencyHz = fundamental
        bridge.update(params)
        let renderer = ToneRenderer(sampleRate: sampleRate, bridge: bridge)

        // Pre-roll to let the mute envelope fully open (5 × 5 ms = 25 ms = 1200 samples).
        var warmupL = [Float](repeating: 0, count: 2048)
        var warmupR = [Float](repeating: 0, count: 2048)
        renderBlock(renderer, left: &warmupL, right: &warmupR)

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        renderBlock(renderer, left: &left, right: &right)

        return goertzel(samples: left, hz: hz)
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

    private func goertzel(samples: [Float], hz: Float) -> Float {
        let omega = 2 * Double.pi * Double(hz) / Double(sampleRate)
        let coeff = Float(2.0 * cos(omega))
        var q1: Float = 0, q2: Float = 0
        for sample in samples {
            let q0 = coeff * q1 - q2 + sample
            q2 = q1
            q1 = q0
        }
        let power = q1 * q1 + q2 * q2 - q1 * q2 * coeff
        return sqrt(max(power, 0)) / Float(samples.count / 2)
    }
}
