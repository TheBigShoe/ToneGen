// Thread-safe bridge between the main thread and the audio render thread.
import os

final class ParamsBridge {
    private let lock = OSAllocatedUnfairLock<EngineParams>(initialState: EngineParams())

    /// Main thread: atomically replace the current parameter snapshot.
    func update(_ params: EngineParams) {
        lock.withLock { $0 = params }
    }

    /// Render thread: read the current snapshot without blocking.
    /// Returns nil on lock contention — caller should reuse the last snapshot.
    func snapshot() -> EngineParams? {
        lock.withLockIfAvailable { $0 }
    }
}
