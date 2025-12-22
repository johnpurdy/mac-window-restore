import Testing
import Foundation
@testable import WindowRestore

// Thread-safe counter for tests
final class AtomicCounter: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("SnapshotScheduler Tests")
struct SnapshotSchedulerTests {

    @Test("SnapshotScheduler calls save callback on start")
    func callsSaveOnStart() async throws {
        let counter = AtomicCounter()

        let scheduler = SnapshotScheduler(
            interval: 0.1,
            onSave: { counter.increment() }
        )

        scheduler.start()

        // Wait a bit for initial save
        try await Task.sleep(for: .milliseconds(50))

        scheduler.stop()

        #expect(counter.get() >= 1)
    }

    @Test("SnapshotScheduler calls save callback repeatedly at interval")
    func callsSaveRepeatedly() async throws {
        let counter = AtomicCounter()

        let scheduler = SnapshotScheduler(
            interval: 0.05,
            onSave: { counter.increment() }
        )

        scheduler.start()

        // Wait for multiple intervals
        try await Task.sleep(for: .milliseconds(200))

        scheduler.stop()

        // Should have been called multiple times
        #expect(counter.get() >= 3)
    }

    @Test("SnapshotScheduler stops calling after stop")
    func stopsAfterStop() async throws {
        let counter = AtomicCounter()

        let scheduler = SnapshotScheduler(
            interval: 0.05,
            onSave: { counter.increment() }
        )

        scheduler.start()
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        let countAfterStop = counter.get()

        // Wait more time
        try await Task.sleep(for: .milliseconds(150))

        // Count should not have increased significantly
        #expect(counter.get() <= countAfterStop + 1)
    }

    @Test("SnapshotScheduler can be restarted")
    func canBeRestarted() async throws {
        let counter = AtomicCounter()

        let scheduler = SnapshotScheduler(
            interval: 0.05,
            onSave: { counter.increment() }
        )

        scheduler.start()
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        let countAfterFirstStop = counter.get()

        scheduler.start()
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        // Should have more saves after restart
        #expect(counter.get() > countAfterFirstStop)
    }
}
