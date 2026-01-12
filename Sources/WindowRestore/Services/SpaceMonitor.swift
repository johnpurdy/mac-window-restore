import Foundation
import AppKit

public typealias SpaceChangeHandler = @Sendable () -> Void

/// Monitors for macOS Space/desktop changes and notifies via callback.
public final class SpaceMonitor: @unchecked Sendable {
    private let onSpaceChange: SpaceChangeHandler
    private var observer: NSObjectProtocol?
    private let lock = NSLock()

    public init(onSpaceChange: @escaping SpaceChangeHandler) {
        self.onSpaceChange = onSpaceChange
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        // Don't start if already running
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleSpaceChange() {
        onSpaceChange()
    }
}
