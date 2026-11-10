import Foundation
import CoreGraphics

public typealias DisplayReconfigurationHandler = @Sendable (DisplayReconfigurationEvent) -> Void

public enum DisplayMonitorError: Error, Equatable {
    case registrationFailed(CGError)
}

/// Listens to Core Graphics display reconfiguration and reports one event per display per change.
///
/// This replaces counting `NSScreen.screens` on `didChangeScreenParametersNotification`. A count
/// cannot see a storm in which the same displays leave and return, and it cannot see a display that
/// only moved or changed mode. The reconfiguration callback reports each display's flags directly,
/// uncoalesced, so the `RestoreScheduler` can restart its countdown on every one of them.
public final class DisplayMonitor: @unchecked Sendable {
    private let onDisplayReconfiguration: DisplayReconfigurationHandler
    private var registered = false
    private let lock = NSLock()

    public init(onDisplayReconfiguration: @escaping DisplayReconfigurationHandler) {
        self.onDisplayReconfiguration = onDisplayReconfiguration
    }

    deinit {
        stop()
    }

    /// Whether the callback is currently registered with Core Graphics.
    public var isRegistered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return registered
    }

    /// Registers the callback. Calling it again while registered does nothing.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !registered else { return }

        let error = CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard error == .success else {
            throw DisplayMonitorError.registrationFailed(error)
        }
        registered = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard registered else { return }

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        registered = false
    }

    /// Turns one callback invocation into events and delivers each one. Internal so tests can drive it
    /// without a real display change.
    func handleReconfiguration(displayIdentifier: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        for event in DisplayReconfigurationEvent.events(displayIdentifier: displayIdentifier, flags: flags) {
            onDisplayReconfiguration(event)
        }
    }
}

/// The C entry point Core Graphics calls. `userInfo` is the unretained `DisplayMonitor` that registered it.
private func displayReconfigurationCallback(
    _ displayIdentifier: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else {
        preconditionFailure("Display reconfiguration callback arrived without the monitor it was registered with")
    }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleReconfiguration(displayIdentifier: displayIdentifier, flags: flags)
}
