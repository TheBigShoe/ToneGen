// Band-limited step (PolyBLEP) and ramp (PolyBLAMP) corrections — suppress aliasing on
// square, saw and triangle.
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

/// Saw wave with PolyBLEP correction applied at the wrap-around discontinuity and the
/// fundamental level held flat across 20 Hz – 20 kHz.
///
/// The peak stays under ±1 at every frequency: the rounded step loses more peak than
/// the level compensation restores.
@inline(__always)
func sawBLEP(_ t: Float, dt: Float) -> Float {
    ((2 * t - 1) - polyBlep(t, dt: dt)) * blepDroopCompensation(dt: dt)
}

/// Square wave with PolyBLEP applied at both discontinuities (t=0 and t=0.5).
///
/// Unlike saw and triangle, the square cannot be made level-flat inside ±1: an ideal
/// square's fundamental is 4/π (+2.1 dB) above its peak, so once the upper harmonics
/// pass Nyquist a level-true square would exceed full scale and clip at 0 dBFS.
/// The droop is therefore only made up as far as the peak allows — the fundamental
/// is never left below a full-scale sine. The result is at most 2.1 dB under an ideal
/// square, instead of 5.3 dB at 20 kHz.
@inline(__always)
func squareBLEP(_ t: Float, dt: Float) -> Float {
    let raw: Float = t < 0.5 ? 1 : -1
    let t2: Float = t + 0.5 < 1 ? t + 0.5 : t - 0.5
    let gain = max(1, squareHeadroom * blepDroopCompensation(dt: dt))
    return (raw + polyBlep(t, dt: dt) - polyBlep(t2, dt: dt)) * gain
}

/// π/4 — the gain at which an ideal square's fundamental peaks at exactly ±1.
private let squareHeadroom: Float = .pi / 4

// MARK: - Triangle (PolyBLAMP)

/// Band-limited ramp correction (2-point PolyBLAMP) for a unit change of slope per sample.
///
/// This is the integral of the PolyBLEP residual above (same 2-sample triangular kernel),
/// so the triangle is band-limited the same way square and saw are. The residual is
/// symmetric about the corner, which makes the correction zero-phase: the corrected
/// triangle has exactly the naive triangle's phase.
/// - Parameters:
///   - t: Phase relative to the corner, in [0, 1).
///   - dt: Phase increment (freq / sampleRate).
/// - Returns: Correction in samples × slope change, in [0, 1/6].
@inline(__always)
func polyBlamp(_ t: Float, dt: Float) -> Float {
    if t < dt {
        let x = 1 - t / dt
        return x * x * x / 6
    } else if t > 1 - dt {
        let x = 1 + (t - 1) / dt
        return x * x * x / 6
    } else {
        return 0
    }
}

/// Gain that undoes the 2-sample kernel's sinc² droop at the fundamental.
///
/// PolyBLEP/BLAMP behave like convolving the ideal waveform with a 2-sample triangular
/// kernel, whose response is sinc²(f/fs): −1.3 dB at 10 kHz and −5.3 dB at 20 kHz
/// (48 kHz). For a test-tone generator the fundamental level must not depend on
/// frequency, so the waveform is scaled back up. Upper harmonics stay slightly
/// attenuated, which only rounds the corners further.
@inline(__always)
func blepDroopCompensation(dt: Float) -> Float {
    let x = Float.pi * dt
    // Below this the droop is < 1e-8 and sinf(x)/x loses precision.
    guard x > 1e-4 else { return 1 }
    let sinc = sinf(x) / x
    return 1 / (sinc * sinc)
}

/// Triangle wave with PolyBLAMP applied at both corners (t=0 and t=0.5) and the
/// fundamental level held flat across 20 Hz – 20 kHz.
///
/// Same phase convention as the naive triangle: −1 at t=0, +1 at t=0.5 (so its
/// fundamental lags the sine by a quarter cycle, as before). The corrections are
/// symmetric, so there is no DC offset and no added phase shift.
@inline(__always)
func triangleBLAMP(_ t: Float, dt: Float) -> Float {
    let naive: Float = t < 0.5 ? 4 * t - 1 : 3 - 4 * t
    let t2: Float = t + 0.5 < 1 ? t + 0.5 : t - 0.5
    // Slope flips by ±8 per cycle at each corner, i.e. ±8·dt per sample.
    let corrected = naive + 8 * dt * (polyBlamp(t, dt: dt) - polyBlamp(t2, dt: dt))
    return corrected * blepDroopCompensation(dt: dt)
}
