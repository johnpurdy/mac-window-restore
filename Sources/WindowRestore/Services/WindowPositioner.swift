import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

public struct WindowRestoreResult: Sendable {
    public let snapshot: WindowSnapshot
    public let success: Bool
    public let error: String?

    public init(snapshot: WindowSnapshot, success: Bool, error: String?) {
        self.snapshot = snapshot
        self.success = success
        self.error = error
    }
}

public protocol WindowPositioning: Sendable {
    func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult]
}

public final class WindowPositioner: WindowPositioning, @unchecked Sendable {

    public init() {}

    public func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        return snapshots.map { snapshot in
            restoreWindow(snapshot: snapshot)
        }
    }

    private func restoreWindow(snapshot: WindowSnapshot) -> WindowRestoreResult {
        // Find the running application
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: snapshot.applicationBundleIdentifier
        ).first else {
            return WindowRestoreResult(
                snapshot: snapshot,
                success: false,
                error: "Application not running"
            )
        }

        // Get AXUIElement for the application
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return WindowRestoreResult(
                snapshot: snapshot,
                success: false,
                error: "Could not get windows: \(result.rawValue)"
            )
        }

        // Find matching window by title
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            // Match by title (or take first window if title is empty in snapshot)
            if title == snapshot.windowTitle || snapshot.windowTitle.isEmpty {
                // Set position
                var position = CGPoint(x: snapshot.frame.origin.x, y: snapshot.frame.origin.y)
                var positionResult: AXError = .failure
                if let positionValue = AXValueCreate(.cgPoint, &position) {
                    positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
                }

                // Set size
                var size = CGSize(width: snapshot.frame.width, height: snapshot.frame.height)
                var sizeResult: AXError = .failure
                if let sizeValue = AXValueCreate(.cgSize, &size) {
                    sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                }

                let success = positionResult == .success && sizeResult == .success
                return WindowRestoreResult(
                    snapshot: snapshot,
                    success: success,
                    error: success ? nil : "Position: \(positionResult.rawValue), Size: \(sizeResult.rawValue)"
                )
            }
        }

        return WindowRestoreResult(
            snapshot: snapshot,
            success: false,
            error: "Window not found: \(snapshot.windowTitle)"
        )
    }
}
