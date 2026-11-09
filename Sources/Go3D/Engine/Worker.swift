import Foundation

/// Tells a computation running on another thread to stop.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isSet: Bool { lock.withLock { stopped } }

    func set() {
        lock.withLock { stopped = true }
    }
}

/// Runs a computation on a thread of its own; the game polls for the result every frame. A computation cancelled or
/// replaced by another is told to stop, and whatever it still returns is dropped.
final class Worker<Result: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var running: StopFlag? // the computation in progress
    private var result: Result?

    func start(_ work: @escaping @Sendable (StopFlag) -> Result) {
        cancel()
        let stop = StopFlag()
        lock.withLock { running = stop }
        let thread = Thread { [self] in
            let value = work(stop)
            lock.withLock {
                guard running === stop else { return }
                result = value
                running = nil
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func cancel() {
        lock.withLock {
            running?.set()
            running = nil
            result = nil
        }
    }

    /// Whether the computation still runs, and its result once it is done, taken in the same step, so that a
    /// result can neither be missed nor taken twice.
    func poll() -> (busy: Bool, result: Result?) {
        lock.withLock {
            defer { result = nil }
            return (running != nil, result)
        }
    }
}
