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

/// One-pole smoother for a cyclic value in [0, 1), where 1 ≡ 0 (the phase offset).
///
/// A plain `Smoother` treats 0.95 → 0.05 as a 0.9 move and sweeps through 0.5 —
/// audibly passing through anti-phase. This one always moves the short way round
/// the circle and keeps its state wrapped into [0, 1) so it cannot drift unbounded.
struct PhaseSmoother {
    private var current: Float
    /// Target phase. Any real value is accepted; only its fractional position matters.
    var target: Float
    private let alpha: Float

    /// - Parameters:
    ///   - initial: Starting phase (also the initial target).
    ///   - sampleRate: Audio sample rate in Hz.
    ///   - timeConstantMs: Time to cover 63% of the shortest-path distance, in milliseconds.
    init(initial: Float, sampleRate: Float, timeConstantMs: Float) {
        current = Self.wrap(initial)
        target = initial
        alpha = 1 - expf(-1000 / (timeConstantMs * sampleRate))
    }

    /// Returns the next smoothed phase in [0, 1) and advances internal state.
    @inline(__always)
    mutating func next() -> Float {
        // Signed shortest distance on the unit circle, in [-0.5, 0.5].
        var delta = target - current
        delta -= delta.rounded()
        let stepped = current + alpha * delta
        // Snap for the same reason as `Smoother`: land exactly rather than stall.
        if abs(delta) <= Smoother.snapThreshold || stepped == current {
            current = Self.wrap(target)
        } else {
            current = Self.wrap(stepped)
        }
        return current
    }

    var value: Float {
        current
    }

    /// Wraps any value into [0, 1). One step is enough on the per-sample path because a
    /// step moves at most half a cycle; the floor handles arbitrary initial/target values.
    @inline(__always)
    private static func wrap(_ x: Float) -> Float {
        let w = x - x.rounded(.down)
        // x just below an integer can round up to exactly 1 in Float.
        return w < 1 ? w : 0
    }
}
