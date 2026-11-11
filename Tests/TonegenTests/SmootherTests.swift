import XCTest
@testable import Tonegen

final class SmootherTests: XCTestCase {
    /// After 5 × τ samples, value must be within 1% of target.
    func testSettlesAfterFiveTau() {
        let sr: Float = 48000
        let tauMs: Float = 20
        var s = Smoother(initial: 0, sampleRate: sr, timeConstantMs: tauMs)
        s.target = 1

        let samplesFor5Tau = Int(5 * tauMs / 1000 * sr) // 5 × 20 ms × 48 kHz = 4800
        for _ in 0 ..< samplesFor5Tau {
            _ = s.next()
        }
        XCTAssertEqual(s.value, 1, accuracy: 0.01)
    }

    func testStartsAtInitialValue() {
        let s = Smoother(initial: 0.5, sampleRate: 48000, timeConstantMs: 10)
        XCTAssertEqual(s.value, 0.5, accuracy: 1e-6)
    }

    func testTargetEqualsCurrent() {
        var s = Smoother(initial: 1.0, sampleRate: 48000, timeConstantMs: 10)
        s.target = 1.0
        let v = s.next()
        XCTAssertEqual(v, 1.0, accuracy: 1e-6)
    }

    func testMonotonicallyApproachesTarget() {
        let sr: Float = 48000
        var s = Smoother(initial: 0, sampleRate: sr, timeConstantMs: 20)
        s.target = 1
        var prev: Float = 0
        for _ in 0 ..< 5000 {
            let v = s.next()
            XCTAssertGreaterThanOrEqual(v, prev)
            prev = v
        }
    }
}
