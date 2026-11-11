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

    /// Returns the next smoothed sample and advances internal state.
    @inline(__always)
    mutating func next() -> Float {
        current += alpha * (target - current)
        return current
    }

    var value: Float {
        current
    }
}
