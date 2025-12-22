import Testing
import Foundation
import AppKit
@testable import WindowRestore

// Thread-safe counts storage for tests
final class AtomicCounts: @unchecked Sendable {
    private var oldCount: Int?
    private var newCount: Int?
    private let lock = NSLock()

    func set(oldCount: Int, newCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.oldCount = oldCount
        self.newCount = newCount
    }

    func getOldCount() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return oldCount
    }

    func getNewCount() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return newCount
    }
}

@Suite("DisplayMonitor Tests")
struct DisplayMonitorTests {

    @Test("DisplayMonitor calls callback when display count changes")
    func callsCallbackOnDisplayChange() async throws {
        let counter = AtomicCounter()

        let monitor = DisplayMonitor(
            onDisplayChange: { _, _ in
                counter.increment()
            }
        )

        monitor.start()

        // Simulate a display change notification
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Give time for notification to be processed
        try await Task.sleep(for: .milliseconds(100))

        monitor.stop()

        #expect(counter.get() >= 1)
    }

    @Test("DisplayMonitor provides old and new display counts")
    func providesDisplayCounts() async throws {
        let capturedCounts = AtomicCounts()

        let monitor = DisplayMonitor(
            onDisplayChange: { oldCount, newCount in
                capturedCounts.set(oldCount: oldCount, newCount: newCount)
            }
        )

        monitor.start()

        // Simulate a display change notification
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        try await Task.sleep(for: .milliseconds(100))

        monitor.stop()

        // Should have captured some values
        #expect(capturedCounts.getNewCount() != nil)
    }

    @Test("DisplayMonitor does not call callback after stop")
    func doesNotCallAfterStop() async throws {
        let counter = AtomicCounter()

        let monitor = DisplayMonitor(
            onDisplayChange: { _, _ in
                counter.increment()
            }
        )

        monitor.start()
        monitor.stop()

        let countAfterStop = counter.get()

        // Simulate a display change notification
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        try await Task.sleep(for: .milliseconds(100))

        // Count should not have increased
        #expect(counter.get() == countAfterStop)
    }
}
