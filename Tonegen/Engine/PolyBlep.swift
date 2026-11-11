// Band-limited step correction (PolyBLEP) — eliminates aliasing on square and saw above ~3 kHz.
import Foundation

/// Subtracts a band-limited correction at a discontinuity.
/// - Parameters:
///   - t: Current phase in [0, 1).
///   - dt: Phase increment (freq / sampleRate).
/// - Returns: Correction value in approximately [-1, 1].
@inline(__always)
func polyBlep(_ t: Float, dt: Float) -> Float {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    } else {
        return 0
    }
}

/// Saw wave with PolyBLEP correction applied at the wrap-around discontinuity.
@inline(__always)
func sawBLEP(_ t: Float, dt: Float) -> Float {
    (2 * t - 1) - polyBlep(t, dt: dt)
}

/// Square wave with PolyBLEP applied at both discontinuities (t=0 and t=0.5).
@inline(__always)
func squareBLEP(_ t: Float, dt: Float) -> Float {
    let raw: Float = t < 0.5 ? 1 : -1
    let t2: Float = t + 0.5 < 1 ? t + 0.5 : t - 0.5
    return raw + polyBlep(t, dt: dt) - polyBlep(t2, dt: dt)
}
