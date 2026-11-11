// Per-channel phase accumulator. Phase lives in [0, 1) — all waveforms share this range.
import Foundation

struct PhaseOscillator {
    var phase: Float = 0
    let sampleRate: Float

    /// Advances phase by one sample and returns the new phase in [0, 1).
    @inline(__always)
    mutating func step(frequency: Float) -> Float {
        let inc = frequency / sampleRate
        phase += inc
        // Two-while is exact and branch-predictor friendly in steady state.
        while phase >= 1 {
            phase -= 1
        }
        while phase < 0 {
            phase += 1
        }
        return phase
    }
}
