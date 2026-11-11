// White (xorshift32) and pink (Kellet) noise generators.
// Both are value types with no heap allocation — safe in the render path.
import Foundation

// MARK: - White Noise

struct WhiteNoise {
    var state: UInt32 = 0x1234_5678

    /// Returns the next sample in [-1, 1).
    @inline(__always)
    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

// MARK: - Pink Noise (Paul Kellet economy filter)

struct PinkNoise {
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    private var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var white = WhiteNoise()

    init(seed: UInt32 = 0x1234_5678) {
        white.state = seed
    }

    /// Returns the next sample, approximately normalized to [-1, 1].
    @inline(__always)
    mutating func next() -> Float {
        let w = white.next()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.11
    }
}
