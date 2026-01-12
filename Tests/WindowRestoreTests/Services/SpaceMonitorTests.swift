import Testing
import Foundation
import AppKit
@testable import WindowRestore

// Thread-safe counter for tests
final class SpaceMonitorAtomicCounter: @unchecked Sendable {
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

@Suite("SpaceMonitor Tests")
struct SpaceMonitorTests {

    @Test("SpaceMonitor can be instantiated with callback")
    func canBeInstantiatedWithCallback() {
        let monitor = SpaceMonitor(onSpaceChange: {
            // Callback placeholder
        })
        _ = monitor  // Silence unused variable warning
    }

    @Test("SpaceMonitor calls callback after start when space changes")
    func callsCallbackOnSpaceChange() async throws {
        let counter = SpaceMonitorAtomicCounter()

        let monitor = SpaceMonitor(onSpaceChange: {
            counter.increment()
        })

        monitor.start()

        // Simulate a space change notification
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        // Give time for notification to be processed
        try await Task.sleep(for: .milliseconds(100))

        monitor.stop()

        #expect(counter.get() >= 1)
    }

    @Test("SpaceMonitor does not call callback after stop")
    func doesNotCallAfterStop() async throws {
        let counter = SpaceMonitorAtomicCounter()

        let monitor = SpaceMonitor(onSpaceChange: {
            counter.increment()
        })

        monitor.start()
        monitor.stop()

        let countAfterStop = counter.get()

        // Simulate a space change notification
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        try await Task.sleep(for: .milliseconds(100))

        // Count should not have increased
        #expect(counter.get() == countAfterStop)
    }
}
