import Foundation
import AppKit

public final class DisplayMonitor: @unchecked Sendable {
    public typealias DisplayChangeHandler = @Sendable (Int, Int) -> Void

    private let onDisplayChange: DisplayChangeHandler
    private var currentDisplayCount: Int
    private var observer: NSObjectProtocol?
    private let lock = NSLock()

    public init(onDisplayChange: @escaping DisplayChangeHandler) {
        self.onDisplayChange = onDisplayChange
        self.currentDisplayCount = NSScreen.screens.count
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        // Remove any existing observer
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }

        // Listen for screen parameter changes
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayChange()
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

    private func handleDisplayChange() {
        let newDisplayCount = NSScreen.screens.count
        let oldDisplayCount = currentDisplayCount

        currentDisplayCount = newDisplayCount

        // Notify of the change
        onDisplayChange(oldDisplayCount, newDisplayCount)
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
