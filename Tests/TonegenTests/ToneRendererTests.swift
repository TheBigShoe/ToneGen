// Verifies render output is a clean 440 Hz sine using a minimal DFT peak finder.
import Accelerate
import AVFoundation
import XCTest
@testable import Tonegen

final class ToneRendererTests: XCTestCase {
    private let sampleRate: Float = 48000
    /// 2^17 = 131072 frames → 0.366 Hz/bin, sufficient for 0.1% accuracy at 440 Hz.
    private let frameCount = 131_072

    func testSineFrequencyAccuracy() {
        let renderer = makeRenderer(playing: true, waveform: .sine, freq: 440)

        var leftBuf = [Float](repeating: 0, count: frameCount)
        var rightBuf = [Float](repeating: 0, count: frameCount)
        renderInto(renderer: renderer, left: &leftBuf, right: &rightBuf)

        let peakBin = dominantFrequencyBin(samples: leftBuf, sampleRate: sampleRate)
        let measuredHz = Float(peakBin) * sampleRate / Float(frameCount)

        // 0.1% accuracy as per WP-04 acceptance criterion.
        XCTAssertEqual(measuredHz, 440, accuracy: 440 * 0.001)
    }

    func testBothChannelsActive() {
        let renderer = makeRenderer(playing: true, waveform: .sine, freq: 440)

        var leftBuf = [Float](repeating: 0, count: frameCount)
        var rightBuf = [Float](repeating: 0, count: frameCount)
        renderInto(renderer: renderer, left: &leftBuf, right: &rightBuf)

        let rmsL = rms(leftBuf)
        let rmsR = rms(rightBuf)
        XCTAssertGreaterThan(rmsL, 0.01, "Left channel should have signal")
        XCTAssertGreaterThan(rmsR, 0.01, "Right channel should have signal")
    }

    func testMutedOutputIsNearSilence() {
        // playing = false means mute envelope stays at 0.
        let renderer = makeRenderer(playing: false, waveform: .sine, freq: 440)

        var leftBuf = [Float](repeating: 0, count: frameCount)
        var rightBuf = [Float](repeating: 0, count: frameCount)
        renderInto(renderer: renderer, left: &leftBuf, right: &rightBuf)

        XCTAssertEqual(rms(leftBuf), 0, accuracy: 1e-6)
        XCTAssertEqual(rms(rightBuf), 0, accuracy: 1e-6)
    }

    // MARK: - Helpers

    /// Builds a ToneRenderer with a pre-populated bridge snapshot.
    private func makeRenderer(playing: Bool, waveform: Waveform, freq: Float) -> ToneRenderer {
        let bridge = ParamsBridge()
        var params = EngineParams()
        params.playing = playing
        params.left.waveform = waveform
        params.right.waveform = waveform
        params.left.frequencyHz = freq
        params.right.frequencyHz = freq
        bridge.update(params)
        return ToneRenderer(sampleRate: sampleRate, bridge: bridge)
    }

    private func renderInto(
        renderer: ToneRenderer,
        left: inout [Float],
        right: inout [Float]
    ) {
        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                let abl = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(abl.unsafeMutablePointer) }
                abl[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameCount * MemoryLayout<Float>.size),
                    mData: lPtr.baseAddress
                )
                abl[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frameCount * MemoryLayout<Float>.size),
                    mData: rPtr.baseAddress
                )
                var silenceFlag: ObjCBool = false
                renderer.render(
                    frames: frameCount,
                    buffers: abl.unsafeMutablePointer,
                    silence: &silenceFlag
                )
            }
        }
    }

    /// Returns the frequency bin index with the highest magnitude (ignoring DC).
    private func dominantFrequencyBin(samples: [Float], sampleRate _: Float) -> Int {
        let n = samples.count
        let halfN = n / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        samples.withUnsafeBufferPointer { sPtr in
            realPart.withUnsafeMutableBufferPointer { rBuf in
                imagPart.withUnsafeMutableBufferPointer { iBuf in
                    var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                    sPtr.baseAddress!
                        .withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                        }
                    let log2n = vDSP_Length(log2(Double(n)))
                    let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
                    defer { vDSP_destroy_fftsetup(setup) }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
                }
            }
        }

        magnitudes[0] = 0 // ignore DC
        var peakVal: Float = 0
        var peakBin: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &peakVal, &peakBin, vDSP_Length(halfN))
        return Int(peakBin)
    }

    private func rms(_ samples: [Float]) -> Float {
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }
}
