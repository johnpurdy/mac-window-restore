import Foundation

public final class SnapshotScheduler: @unchecked Sendable {
    private let interval: TimeInterval
    private let onSave: @Sendable () -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.windowrestore.scheduler")
    private let lock = NSLock()

    public init(
        interval: TimeInterval = 30.0,
        onSave: @escaping @Sendable () -> Void
    ) {
        self.interval = interval
        self.onSave = onSave
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        // Stop any existing timer
        timer?.cancel()
        timer = nil

        // Fire immediately on start
        onSave()

        // Create and schedule repeating timer
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(
            deadline: .now() + interval,
            repeating: interval
        )
        newTimer.setEventHandler { [weak self] in
            self?.onSave()
        }
        newTimer.resume()
        timer = newTimer
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }
}
