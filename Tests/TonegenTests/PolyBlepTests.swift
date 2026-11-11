// Verifies PolyBLEP correction reduces aliasing on saw and square at high frequencies.
import Accelerate
import XCTest
@testable import Tonegen

final class PolyBlepTests: XCTestCase {
    private let sampleRate: Float = 48000

    // MARK: - polyBlep function

    func testPolyBlepZeroAwayFromDiscontinuity() {
        // For dt = 0.01, correction should be zero when t is far from 0 and 1.
        let dt: Float = 0.01
        XCTAssertEqual(polyBlep(0.5, dt: dt), 0, accuracy: 1e-6)
        XCTAssertEqual(polyBlep(0.3, dt: dt), 0, accuracy: 1e-6)
    }

    func testPolyBlepNonZeroAtDiscontinuity() {
        let dt: Float = 0.01
        XCTAssertNotEqual(polyBlep(0.001, dt: dt), 0)
        XCTAssertNotEqual(polyBlep(0.999, dt: dt), 0)
    }

    func testSawBLEPMatchesNaiveAtLowFreq() {
        // At very low dt the correction is near-zero, so BLEP ≈ naive saw.
        let dt: Float = 1e-5
        for tInt in 0 ..< 10 {
            let t = Float(tInt) / 10 + 0.05
            let naive = 2 * t - 1
            let blep = sawBLEP(t, dt: dt)
            XCTAssertEqual(
                blep,
                naive,
                accuracy: 0.001,
                "BLEP saw should ≈ naive at low freq, t=\(t)"
            )
        }
    }

    // MARK: - Aliasing suppression at 5 kHz

    func testSawBLEPReducesHighFreqAliasingVsNaive() {
        // At 5 kHz / 48 kHz the 9th harmonic (45 kHz) folds to 3 kHz (48 − 45 = 3).
        // 3 kHz has no legitimate saw harmonic (3/5 is not an integer), so all energy
        // there is aliasing. n/T = 9/9.6 = 0.9375 → sinc²(0.9375) ≈ 0.004 ≈ 47 dB
        // theoretical suppression, well above the 40 dB threshold.
        let naive = aliasAmplitude(waveform: .saw, hz: 5000, aliasHz: 3000)
        let blep = aliasAmplitude(waveform: .saw, hz: 5000, aliasHz: 3000, useBLEP: true)
        let suppressionDb = 20 * log10(naive / max(blep, 1e-10))
        XCTAssertGreaterThan(
            suppressionDb,
            40,
            "Saw BLEP should suppress alias at 3 kHz by > 40 dB, got \(suppressionDb) dB"
        )
    }

    func testSquareBLEPReducesHighFreqAliasingVsNaive() {
        // Square at 5 kHz: 9th harmonic (45 kHz) folds to 3 kHz; same alias math as saw.
        // Square has only odd harmonics, so n = 9 is present and 3 kHz is clean of
        // legitimate content.
        let naive = aliasAmplitude(waveform: .square, hz: 5000, aliasHz: 3000)
        let blep = aliasAmplitude(waveform: .square, hz: 5000, aliasHz: 3000, useBLEP: true)
        let suppressionDb = 20 * log10(naive / max(blep, 1e-10))
        XCTAssertGreaterThan(
            suppressionDb,
            40,
            "Square BLEP should suppress alias at 3 kHz by > 40 dB, got \(suppressionDb) dB"
        )
    }

    func testBLEPSoundsSameAtLowFreq() {
        // At 100 Hz, BLEP and naive should have nearly identical fundamental amplitude.
        let naiveSaw = goertzel(render(waveform: .saw, useBLEP: false, hz: 100), hz: 100)
        let blepSaw = goertzel(render(waveform: .saw, useBLEP: true, hz: 100), hz: 100)
        let naiveSq = goertzel(render(waveform: .square, useBLEP: false, hz: 100), hz: 100)
        let blepSq = goertzel(render(waveform: .square, useBLEP: true, hz: 100), hz: 100)

        XCTAssertEqual(
            blepSaw / naiveSaw,
            1.0,
            accuracy: 0.01,
            "Saw BLEP should not change fundamental amplitude at 100 Hz"
        )
        XCTAssertEqual(
            blepSq / naiveSq,
            1.0,
            accuracy: 0.01,
            "Square BLEP should not change fundamental amplitude at 100 Hz"
        )
    }

    // MARK: - Helpers

    /// Goertzel amplitude at a specific alias frequency (a frequency with no legitimate harmonic).
    private func aliasAmplitude(
        waveform: Waveform,
        hz: Float,
        aliasHz: Float,
        useBLEP: Bool = false
    ) -> Float {
        let samples = render(waveform: waveform, useBLEP: useBLEP, hz: hz)
        return goertzel(samples, hz: aliasHz)
    }

    /// Goertzel amplitude at `hz` Hz.
    private func goertzel(_ samples: [Float], hz: Float) -> Float {
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

    private func render(waveform: Waveform, useBLEP: Bool, hz: Float) -> [Float] {
        let n = 48000 // 1 s at 48 kHz
        let dt = hz / sampleRate
        var phase: Float = 0
        var out = [Float](repeating: 0, count: n)
        for i in 0 ..< n {
            phase += dt
            while phase >= 1 {
                phase -= 1
            }
            switch waveform {
            case .saw: out[i] = useBLEP ? sawBLEP(phase, dt: dt) : (2 * phase - 1)
            case .square: out[i] = useBLEP ? squareBLEP(phase, dt: dt) : (phase < 0.5 ? 1 : -1)
            default: break
            }
        }
        return out
    }
}
