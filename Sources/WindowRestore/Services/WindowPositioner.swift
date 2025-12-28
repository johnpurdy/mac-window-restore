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
        // Group snapshots by application bundle identifier
        var snapshotsByApp: [String: [WindowSnapshot]] = [:]
        for snapshot in snapshots {
            snapshotsByApp[snapshot.applicationBundleIdentifier, default: []].append(snapshot)
        }

        var results: [WindowRestoreResult] = []

        // Process each application's windows together
        for (bundleId, appSnapshots) in snapshotsByApp {
            let appResults = restoreWindowsForApp(bundleId: bundleId, snapshots: appSnapshots)
            results.append(contentsOf: appResults)
        }

        return results
    }

    private func restoreWindowsForApp(bundleId: String, snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        // Find the running application
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleId
        ).first else {
            // App not running - don't report as failure, just skip
            return []
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
            // Can't get windows - skip silently
            return []
        }

        // Get current window info (title, position, size) for all windows
        var currentWindows: [(element: AXUIElement, title: String, frame: CGRect)] = []
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            var positionRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
            var position = CGPoint.zero
            if let positionValue = positionRef,
               CFGetTypeID(positionValue) == AXValueGetTypeID() {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            }

            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let sizeValue = sizeRef,
               CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }

            // Skip zero-size windows
            if size.width > 0 && size.height > 0 {
                let frame = CGRect(origin: position, size: size)
                currentWindows.append((element: window, title: title, frame: frame))
            }
        }

        // KEY CHANGE: Iterate over CURRENT windows, find saved snapshot for each
        // This ensures each current window is only moved once
        var results: [WindowRestoreResult] = []
        var usedSnapshotIndices: Set<Int> = []

        for currentWindow in currentWindows {
            let matchResult = findBestMatchingSnapshot(
                currentWindow: currentWindow,
                snapshots: snapshots,
                excludedIndices: usedSnapshotIndices
            )

            if let (snapshotIndex, snapshot) = matchResult {
                usedSnapshotIndices.insert(snapshotIndex)
                let restoreResult = positionWindow(window: currentWindow.element, snapshot: snapshot)
                results.append(restoreResult)
            }
            // If no matching snapshot found, don't report as error - window may be from another desktop
        }

        return results
    }

    private func findBestMatchingSnapshot(
        currentWindow: (element: AXUIElement, title: String, frame: CGRect),
        snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        // Match by exact title only - windows without titles are not saved
        for (index, snapshot) in snapshots.enumerated() {
            if excludedIndices.contains(index) { continue }

            if !currentWindow.title.isEmpty && currentWindow.title == snapshot.windowTitle {
                return (index, snapshot)
            }
        }

        return nil
    }

    private func positionWindow(window: AXUIElement, snapshot: WindowSnapshot) -> WindowRestoreResult {
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
