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

    // MARK: - Helpers

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
