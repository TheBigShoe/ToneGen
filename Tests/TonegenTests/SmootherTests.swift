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

    /// A gate driven to 0 must reach exactly 0, not hover at a denormal.
    func testLandsExactlyOnZero() {
        var s = Smoother(initial: 1, sampleRate: 48000, timeConstantMs: 10)
        s.target = 0
        for _ in 0 ..< 48000 {
            _ = s.next()
        }
        XCTAssertEqual(s.value, 0)
    }

    /// Far from zero one ulp exceeds the snap distance; the smoother must not stall short.
    func testLandsExactlyOnLargeMagnitudeTarget() {
        var s = Smoother(initial: -12, sampleRate: 48000, timeConstantMs: 10)
        s.target = -120
        for _ in 0 ..< 48000 {
            _ = s.next()
        }
        XCTAssertEqual(s.value, -120)
    }

    // MARK: - PhaseSmoother

    func testPhaseWrapsForwardTheShortWay() {
        // 0.95 → 0.05 is +0.1 across the wrap, not −0.9 through 0.5.
        let path = phasePath(from: 0.95, to: 0.05)
        for v in path {
            XCTAssertTrue(v >= 0.95 - 1e-6 || v <= 0.05 + 1e-6, "Left the short arc: \(v)")
        }
        XCTAssertEqual(path.last ?? -1, 0.05, accuracy: 1e-6)
    }

    func testPhaseWrapsBackwardTheShortWay() {
        let path = phasePath(from: 0.05, to: 0.95)
        for v in path {
            XCTAssertTrue(v >= 0.95 - 1e-6 || v <= 0.05 + 1e-6, "Left the short arc: \(v)")
        }
        XCTAssertEqual(path.last ?? -1, 0.95, accuracy: 1e-6)
    }

    func testPhaseNonWrappingMoveIsMonotonic() {
        // 0.2 → 0.6 is shorter going up (0.4) than down (0.6).
        let path = phasePath(from: 0.2, to: 0.6)
        var prev: Float = 0.2
        for v in path {
            XCTAssertGreaterThanOrEqual(v, prev)
            XCTAssertLessThanOrEqual(v, 0.6 + 1e-6)
            prev = v
        }
        XCTAssertEqual(path.last ?? -1, 0.6, accuracy: 1e-6)
    }

    func testPhaseStateStaysWrappedUnderRepeatedWraps() {
        // Keep pushing the target forward by 0.3 — the unwrapped phase would grow without
        // bound; the smoothed state must stay in [0, 1).
        var s = PhaseSmoother(initial: 0, sampleRate: 48000, timeConstantMs: 1)
        var target: Float = 0
        for _ in 0 ..< 1000 {
            target += 0.3
            if target >= 1 { target -= 1 }
            s.target = target
            for _ in 0 ..< 100 {
                let v = s.next()
                XCTAssertGreaterThanOrEqual(v, 0)
                XCTAssertLessThan(v, 1)
            }
        }
    }

    private func phasePath(from start: Float, to end: Float) -> [Float] {
        var s = PhaseSmoother(initial: start, sampleRate: 48000, timeConstantMs: 30)
        s.target = end
        return (0 ..< 48000).map { _ in s.next() }
    }
}
