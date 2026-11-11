import XCTest
@testable import Tonegen

final class PhaseOscillatorTests: XCTestCase {
    func testPhaseAlwaysInRange() {
        var osc = PhaseOscillator(sampleRate: 48000)
        for _ in 0 ..< 1_000_000 {
            let p = osc.step(frequency: 440)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThan(p, 1)
        }
    }

    func testExactCycleReturn() {
        // 750 Hz at 48 kHz: increment = 750/48000 = 0.015625, which is exact in Float32.
        // After 64 samples (one full cycle), phase must return to exactly 0.
        let sr: Float = 48000
        let freq: Float = 750 // 48000/750 = 64 samples per cycle
        var osc = PhaseOscillator(sampleRate: sr)
        for _ in 0 ..< 64 {
            _ = osc.step(frequency: freq)
        }
        XCTAssertEqual(osc.phase, 0, accuracy: 1e-6)
    }

    func testHighFrequencyEdge() {
        var osc = PhaseOscillator(sampleRate: 48000)
        for _ in 0 ..< 100_000 {
            let p = osc.step(frequency: 20000)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThan(p, 1)
        }
    }
}
