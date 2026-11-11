// SPSC ring buffer for audio → scope visualization.
// Writer: audio render thread. Reader: display thread (TimelineView at 60 Hz).
import os

final class SampleRingBuffer {
    private let capacity: Int
    private let mask: Int
    // Raw buffer — both threads access different index ranges without locking.
    // Safe per SPSC invariant: writer needs 4096 more pushes (≈85 ms at 48 kHz)
    // to wrap around and reach slots the reader just observed.
    private let buf: UnsafeMutableBufferPointer<Float>
    // Lock protects only writeIdx. Its release/acquire pair publishes buffer writes
    // to the reader thread, satisfying the Swift memory model.
    private let idxLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    init(capacity: Int = 4096) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be power of 2")
        self.capacity = capacity
        self.mask = capacity - 1
        buf = .allocate(capacity: capacity)
        buf.initialize(repeating: 0)
    }

    deinit { buf.deallocate() }

    /// Writer (audio thread): push one sample. Skips silently on lock contention.
    @inline(__always)
    func push(_ sample: Float) {
        idxLock.withLockIfAvailable { w in
            buf[Int(w) & mask] = sample
            w &+= 1
        }
    }

    /// Reader (display thread): copy up to `count` most-recent samples into `out`.
    /// Returns the number actually copied (may be less if fewer samples are buffered).
    func readLatest(_ count: Int, into out: inout [Float]) -> Int {
        // Acquire the published write index. The lock's acquire barrier ensures
        // all preceding buffer writes are visible to this thread.
        let w: UInt64 = idxLock.withLock { idx in idx }
        let n = min(count, min(Int(w), capacity))
        guard n > 0 else { return 0 }
        let start = w &- UInt64(n)
        for k in 0 ..< n {
            out[k] = buf[Int(start &+ UInt64(k)) & mask]
        }
        return n
    }
}
