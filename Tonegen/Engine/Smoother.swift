// One-pole lowpass parameter smoother — eliminates clicks on parameter changes.
import Foundation

struct Smoother {
    private var current: Float
    var target: Float
    private let alpha: Float

    /// - Parameters:
    ///   - initial: Starting value (also the initial target).
    ///   - sampleRate: Audio sample rate in Hz.
    ///   - timeConstantMs: Time to reach 63% of a step change, in milliseconds.
    init(initial: Float, sampleRate: Float, timeConstantMs: Float) {
        current = initial
        target = initial
        alpha = 1 - expf(-1000 / (timeConstantMs * sampleRate))
    }

    /// Distance below which the smoother lands exactly on its target.
    ///
    /// A one-pole filter only approaches its target asymptotically, and in Float it can
    /// stall short of it once `alpha * delta` rounds away (at −120 dB one ulp is ≈ 8e-6).
    /// Snapping — on a tiny distance or on a step that no longer moves the value — makes
    /// "settled" mean equal, so a gate or level driven to its floor outputs true digital
    /// silence. The final jump is at most an ulp or 1e-6, far below audibility.
    static let snapThreshold: Float = 1e-6

    /// Returns the next smoothed sample and advances internal state.
    @inline(__always)
    mutating func next() -> Float {
        let delta = target - current
        let stepped = current + alpha * delta
        if abs(delta) <= Self.snapThreshold || stepped == current {
            current = target
        } else {
            current = stepped
        }
        return current
    }

    var value: Float {
        current
    }
}
