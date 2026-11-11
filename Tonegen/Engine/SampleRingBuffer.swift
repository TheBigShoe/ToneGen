// SPSC ring buffer for audio → scope visualization.
// Writer: audio render thread. Reader: display thread (TimelineView at 60 Hz).
import os

// @unchecked: `buf` and `writeCount` are mutated without a lock. Safe because only the
// render thread calls `write` (sole owner of `writeCount`), and the reader only touches
// slots behind the index it acquires through `idxLock` — the SPSC invariant above.
/// Single-producer / single-consumer sample ring fed one render block at a time.
final class SampleRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    /// Raw buffer — the writer fills slots ahead of the published index while the
    /// reader copies slots behind it. Safe per SPSC invariant: the writer needs
    /// `capacity` more samples (≈85 ms at 48 kHz for 4096) to wrap around and reach
    /// slots the reader just observed.
    private let buf: UnsafeMutablePointer<Float>
    /// Writer-private running sample count. Touched only by the render thread, so it
    /// needs no lock; it is what lets a missed publish catch up on the next block.
    private var writeCount: UInt64 = 0
    /// Lock protects only the published write index. Its release/acquire pair makes the
    /// buffer writes that precede a publish visible to the reader thread.
    private let idxLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    init(capacity: Int = 4096) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be power of 2")
        self.capacity = capacity
        mask = capacity - 1
        buf = .allocate(capacity: capacity)
        buf.initialize(repeating: 0, count: capacity)
    }

    deinit { buf.deallocate() }

    /// Writer (audio thread): append a whole render block, then publish it with a
    /// single try-lock.
    ///
    /// Samples are always stored; only the index publish can be skipped. If the reader
    /// holds the lock, this block stays unpublished and becomes visible together with
    /// the next block whose publish succeeds, so contention delays the scope rather
    /// than punching holes in it. No allocation, no blocking.
    func write(_ samples: UnsafeBufferPointer<Float>) {
        guard let src = samples.baseAddress, !samples.isEmpty else { return }
        let count = samples.count
        // Only the newest `capacity` samples can survive a block larger than the ring.
        let kept = min(count, capacity)
        let skipped = count - kept
        var slot = Int((writeCount &+ UInt64(skipped)) & UInt64(mask))
        var copied = 0
        while copied < kept {
            // At most two contiguous runs: up to the end of the ring, then from slot 0.
            let run = min(kept - copied, capacity - slot)
            (buf + slot).update(from: src + skipped + copied, count: run)
            copied += run
            slot = 0
        }
        writeCount &+= UInt64(count)
        let published = writeCount
        idxLock.withLockIfAvailable { $0 = published }
    }

    /// Reader (display thread): copy up to `count` most-recent samples into `out`.
    /// Returns the number actually copied (may be less if fewer samples are buffered).
    func readLatest(_ count: Int, into out: inout [Float]) -> Int {
        // Acquire the published write index. The lock's acquire barrier ensures
        // all preceding buffer writes are visible to this thread.
        let w: UInt64 = idxLock.withLock { idx in idx }
        let n = min(count, out.count, Int(min(w, UInt64(capacity))))
        guard n > 0 else { return 0 }
        let start = w &- UInt64(n)
        for k in 0 ..< n {
            out[k] = buf[Int(start &+ UInt64(k)) & mask]
        }
        return n
    }
}
