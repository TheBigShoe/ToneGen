// dBFS ↔ linear amplitude conversions.
import Foundation

private let floorDb: Double = -120

/// Converts a dBFS value to a linear amplitude in [0, 1].
/// Values at or below −120 dBFS return 1e-6 (silence floor).
func dbfsToLinear(_ db: Double) -> Double {
    if db <= floorDb { return pow(10, floorDb / 20) }
    return pow(10, db / 20)
}

/// Converts a linear amplitude to dBFS, floored at −120 dBFS.
func linearToDbfs(_ x: Double) -> Double {
    guard x > 0 else { return floorDb }
    return max(20 * log10(x), floorDb)
}
