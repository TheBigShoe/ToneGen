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

    // MARK: - Triangle (PolyBLAMP)

    func testTriangleBLAMPReducesAliasingVsNaive() {
        // (fundamental, alias): 5 kHz H9 = 45 kHz folds to 3 kHz; 5 kHz H11 = 55 kHz folds
        // to 7 kHz; 7 kHz H7 = 49 kHz folds to 1 kHz. None is an odd multiple of the
        // fundamental, so all energy there is aliasing.
        let cases: [(hz: Float, alias: Float, minDb: Float)] = [
            (5000, 3000, 30),
            (5000, 7000, 25),
            (7000, 1000, 40)
        ]
        for test in cases {
            let naive = aliasAmplitude(waveform: .triangle, hz: test.hz, aliasHz: test.alias)
            let blamp = aliasAmplitude(
                waveform: .triangle,
                hz: test.hz,
                aliasHz: test.alias,
                useBLEP: true
            )
            let suppressionDb = 20 * log10(naive / max(blamp, 1e-10))
            XCTAssertGreaterThan(
                suppressionDb,
                test.minDb,
                "Alias at \(test.alias) Hz from \(test.hz) Hz: only \(suppressionDb) dB"
            )
        }
    }

    func testTriangleBLAMPMatchesIdealTriangleAt100Hz() {
        // At 100 Hz the naive triangle's aliasing is negligible, so it is the reference shape.
        let dt: Float = 100 / sampleRate
        let ideal = render(waveform: .triangle, useBLEP: false, hz: 100)
        let blamp = render(waveform: .triangle, useBLEP: true, hz: 100)
        let maxDiff = zip(ideal, blamp).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(maxDiff, 0.005, "Corner rounding at 100 Hz should be tiny")
        // Same phase: corners (−1 at t=0, +1 at t=0.5) sit where the naive ones do.
        XCTAssertEqual(triangleBLAMP(0.25, dt: dt), 0, accuracy: 1e-5)
        XCTAssertEqual(triangleBLAMP(0.75, dt: dt), 0, accuracy: 1e-5)
    }

    func testTriangleBLAMPLevelFlatWithoutDCAcrossBand() {
        // Fundamental of an ideal ±1 triangle is 8/π².
        let idealFundamental: Float = 8 / (.pi * .pi)
        for rate: Float in [48000, 44100] {
            for hz: Float in [20, 100, 1000, 5000, 10000, 15000, 20000] {
                let x = render(waveform: .triangle, useBLEP: true, hz: hz, rate: rate)
                let fundamental = goertzel(x, hz: hz, rate: rate)
                let levelDb = 20 * log10(fundamental / idealFundamental)
                let mean = x.reduce(0, +) / Float(x.count)
                let peak = x.map(abs).max() ?? 0
                let label = "\(hz) Hz @ \(rate)"
                XCTAssertEqual(levelDb, 0, accuracy: 0.1, "Fundamental level off at \(label)")
                XCTAssertEqual(mean, 0, accuracy: 1e-4, "DC offset at \(label)")
                XCTAssertLessThanOrEqual(peak, 1.0001, "Overshoot at \(label)")
                // Above ~7 kHz only the fundamental is in band, whose peak is 8/π² ≈ 0.81.
                XCTAssertGreaterThan(peak, 0.78, "Peak collapsed at \(label)")
            }
        }
    }

    func testSawBLEPLevelFlatAcrossBand() {
        // Fundamental of an ideal ±1 saw is 2/π.
        let ideal: Float = 2 / .pi
        // 12 kHz is skipped at 48 kHz: it is fs/4, where aliased harmonics land on the
        // fundamental and make the reading meaningless.
        for hz: Float in [20, 100, 1000, 5000, 10000, 15000, 20000] {
            let x = render(waveform: .saw, useBLEP: true, hz: hz)
            let levelDb = 20 * log10(goertzel(x, hz: hz) / ideal)
            let peak = x.map(abs).max() ?? 0
            XCTAssertEqual(levelDb, 0, accuracy: 0.1, "Saw fundamental level off at \(hz) Hz")
            XCTAssertLessThanOrEqual(peak, 1.0001, "Saw overshoot at \(hz) Hz")
        }
    }

    func testSquareBLEPLevelLimitedByFullScale() {
        // Fundamental of an ideal ±1 square is 4/π; a full-scale sine is 2.1 dB below it.
        let ideal: Float = 4 / .pi
        for hz: Float in [20, 100, 1000, 5000, 10000, 15000, 18000, 20000] {
            let x = render(waveform: .square, useBLEP: true, hz: hz)
            let levelDb = 20 * log10(goertzel(x, hz: hz) / ideal)
            let peak = x.map(abs).max() ?? 0
            XCTAssertLessThanOrEqual(levelDb, 0.05, "Square above ideal at \(hz) Hz")
            XCTAssertGreaterThan(levelDb, -2.2, "Square droops past a full-scale sine at \(hz) Hz")
            // Aliased partials ride on the fundamental, hence the 1% allowance.
            XCTAssertLessThanOrEqual(peak, 1.01, "Square overshoot at \(hz) Hz")
        }
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
    /// Accumulates in Double: at 20 Hz the coefficient is within 1e-6 of 2 and a Float
    /// recursion over a second of samples drifts by a tenth of a dB.
    private func goertzel(_ samples: [Float], hz: Float, rate: Float? = nil) -> Float {
        let omega = 2 * Double.pi * Double(hz) / Double(rate ?? sampleRate)
        let coeff = 2.0 * cos(omega)
        var q1 = 0.0, q2 = 0.0
        for s in samples {
            let q0 = coeff * q1 - q2 + Double(s)
            q2 = q1
            q1 = q0
        }
        let power = q1 * q1 + q2 * q2 - q1 * q2 * coeff
        return Float(sqrt(max(power, 0)) / Double(samples.count / 2))
    }

    /// Renders one second at `rate` (default `sampleRate`).
    private func render(
        waveform: Waveform,
        useBLEP: Bool,
        hz: Float,
        rate: Float? = nil
    ) -> [Float] {
        let sr = rate ?? sampleRate
        let n = Int(sr)
        let dt = hz / sr
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
            case .triangle:
                out[i] = useBLEP ? triangleBLAMP(phase, dt: dt) :
                    (phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase)
            default: break
            }
        }
        return out
    }
}
