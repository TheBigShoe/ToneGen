import Accelerate
import XCTest
@testable import Tonegen

final class NoiseGeneratorTests: XCTestCase {
    private let sampleCount = 100_000

    // MARK: - White noise

    func testWhiteHistogramIsApproximatelyUniform() {
        var gen = WhiteNoise()
        let bins = 10
        var counts = [Int](repeating: 0, count: bins)

        for _ in 0 ..< sampleCount {
            let s = gen.next()
            XCTAssertGreaterThanOrEqual(s, -1)
            XCTAssertLessThan(s, 1)
            let bin = min(Int((s + 1) / 2 * Float(bins)), bins - 1)
            counts[bin] += 1
        }

        // Each bin should be within ±20% of the expected uniform count.
        let expected = sampleCount / bins
        for count in counts {
            XCTAssertEqual(Double(count), Double(expected), accuracy: Double(expected) * 0.20)
        }
    }

    func testWhiteMeanNearZero() {
        var gen = WhiteNoise()
        var sum: Float = 0
        for _ in 0 ..< sampleCount {
            sum += gen.next()
        }
        XCTAssertEqual(sum / Float(sampleCount), 0, accuracy: 0.01)
    }

    // MARK: - Pink noise (1/f spectrum)

    func testPinkSpectralSlope() {
        // Render enough pink noise to measure the PSD in each octave band.
        // A 1/f process should have ~3 dB/octave roll-off (energy halves per octave).
        let sr: Float = 48000
        var gen = PinkNoise()
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0 ..< sampleCount {
            samples[i] = gen.next()
        }

        // Measure energy in three octave bands using Goertzel at center frequencies.
        let f1 = bandEnergy(samples: samples, centerHz: 200, sampleRate: sr)
        let f2 = bandEnergy(samples: samples, centerHz: 400, sampleRate: sr)
        let f3 = bandEnergy(samples: samples, centerHz: 800, sampleRate: sr)

        // Each octave should be ~3 dB lower (amplitude × 0.707). Allow ±40% tolerance
        // since pink noise is stochastic and 100 k samples is a short window.
        let ratio12 = f2 / f1
        let ratio23 = f3 / f2
        XCTAssertLessThan(ratio12, 1.0, "Pink noise should roll off each octave")
        XCTAssertLessThan(ratio23, 1.0, "Pink noise should roll off each octave")
        XCTAssertGreaterThan(ratio12, 0.3, "Pink noise roll-off should not be excessive")
        XCTAssertGreaterThan(ratio23, 0.3, "Pink noise roll-off should not be excessive")
    }

    // MARK: - L/R uncorrelated

    func testWhiteLRUncorrelated() {
        var genL = WhiteNoise(state: 0x1234_5678)
        var genR = WhiteNoise(state: 0x8765_4321)
        var samplesL = [Float](repeating: 0, count: sampleCount)
        var samplesR = [Float](repeating: 0, count: sampleCount)
        for i in 0 ..< sampleCount {
            samplesL[i] = genL.next()
            samplesR[i] = genR.next()
        }
        XCTAssertLessThan(crossCorrelation(samplesL, samplesR), 0.05)
    }

    func testPinkLRUncorrelated() {
        var genL = PinkNoise(seed: 0x1234_5678)
        var genR = PinkNoise(seed: 0x8765_4321)
        var samplesL = [Float](repeating: 0, count: sampleCount)
        var samplesR = [Float](repeating: 0, count: sampleCount)
        for i in 0 ..< sampleCount {
            samplesL[i] = genL.next()
            samplesR[i] = genR.next()
        }
        XCTAssertLessThan(crossCorrelation(samplesL, samplesR), 0.05)
    }

    // MARK: - Helpers

    /// Goertzel amplitude at a single frequency — used as a proxy for octave-band energy.
    private func bandEnergy(samples: [Float], centerHz: Float, sampleRate: Float) -> Float {
        let omega = 2 * Double.pi * Double(centerHz) / Double(sampleRate)
        let coeff = Float(2.0 * cos(omega))
        var q1: Float = 0, q2: Float = 0
        for s in samples {
            let q0 = coeff * q1 - q2 + s
            q2 = q1
            q1 = q0
        }
        let power = q1 * q1 + q2 * q2 - q1 * q2 * coeff
        return sqrt(max(power, 0))
    }

    /// Normalized cross-correlation at lag 0: Σ(xᵢ·yᵢ) / √(Σxᵢ² · Σyᵢ²).
    private func crossCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let n = vDSP_Length(x.count)
        var dotXY: Float = 0, dotXX: Float = 0, dotYY: Float = 0
        vDSP_dotpr(x, 1, y, 1, &dotXY, n)
        vDSP_dotpr(x, 1, x, 1, &dotXX, n)
        vDSP_dotpr(y, 1, y, 1, &dotYY, n)
        let denom = sqrt(dotXX * dotYY)
        guard denom > 0 else { return 0 }
        return abs(dotXY / denom)
    }
}
