import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

// Thread-safe event store for tests
final class RecordedDisplayEvents: @unchecked Sendable {
    private var events: [DisplayReconfigurationEvent] = []
    private let lock = NSLock()

    func append(_ event: DisplayReconfigurationEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func all() -> [DisplayReconfigurationEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

@Suite("DisplayMonitor Tests")
struct DisplayMonitorTests {

    @Test("DisplayMonitor delivers one callback per event in a reconfiguration")
    func deliversOneCallbackPerEvent() {
        let recorded = RecordedDisplayEvents()
        let monitor = DisplayMonitor(onDisplayReconfiguration: { recorded.append($0) })

        monitor.handleReconfiguration(displayIdentifier: 5, flags: [.addFlag, .movedFlag])

        #expect(recorded.all() == [
            DisplayReconfigurationEvent(displayIdentifier: 5, kind: .added),
            DisplayReconfigurationEvent(displayIdentifier: 5, kind: .moved),
        ])
    }

    @Test("DisplayMonitor delivers nothing for the begin-configuration notice")
    func deliversNothingForBeginConfiguration() {
        let recorded = RecordedDisplayEvents()
        let monitor = DisplayMonitor(onDisplayReconfiguration: { recorded.append($0) })

        monitor.handleReconfiguration(displayIdentifier: 5, flags: .beginConfigurationFlag)

        #expect(recorded.all().isEmpty)
    }

    @Test("DisplayMonitor registers once and can be stopped")
    func registersOnceAndStops() throws {
        let monitor = DisplayMonitor(onDisplayReconfiguration: { _ in })

        try monitor.start()
        try monitor.start()
        #expect(monitor.isRegistered)

        monitor.stop()
        #expect(!monitor.isRegistered)

        monitor.stop()
        #expect(!monitor.isRegistered)
    }
}
