import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "restore")

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

        let pid = app.processIdentifier

        // Get AXUIElement for the application
        let appElement = AXUIElementCreateApplication(pid)

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

        // Get CGWindowList for this app's windows to correlate windowIdentifiers
        let cgWindows = getCGWindowsForPid(pid)

        // Get current window info (title, position, size, windowId) for all windows
        var currentWindows: [(element: AXUIElement, title: String, frame: CGRect, windowIdentifier: Int?)] = []
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
                // Correlate with CGWindowList to get windowIdentifier
                let windowIdentifier = findCGWindowIdentifier(frame: frame, cgWindows: cgWindows)
                currentWindows.append((element: window, title: title, frame: frame, windowIdentifier: windowIdentifier))
            }
        }

        // Iterate over CURRENT windows, find saved snapshot for each
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
                let matchType = (currentWindow.windowIdentifier != nil && snapshot.windowIdentifier != nil && currentWindow.windowIdentifier == snapshot.windowIdentifier) ? "windowId" : "title"
                logger.info("Matched (\(matchType)): \"\(currentWindow.title)\" current=(\(Int(currentWindow.frame.origin.x)),\(Int(currentWindow.frame.origin.y)) \(Int(currentWindow.frame.width))x\(Int(currentWindow.frame.height))) -> target=(\(Int(snapshot.frame.origin.x)),\(Int(snapshot.frame.origin.y)) \(Int(snapshot.frame.width))x\(Int(snapshot.frame.height)))")
                let restoreResult = positionWindow(window: currentWindow.element, snapshot: snapshot)
                results.append(restoreResult)
            }
            // If no matching snapshot found, don't report as error - window may be from another desktop
        }

        return results
    }

    /// Get CGWindowList entries for a specific process
    private func getCGWindowsForPid(_ pid: pid_t) -> [(windowIdentifier: Int, bounds: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.compactMap { windowInfo -> (windowIdentifier: Int, bounds: CGRect)? in
            guard let windowNumber = windowInfo[kCGWindowNumber as String] as? Int,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                return nil
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)
            return (windowIdentifier: windowNumber, bounds: bounds)
        }
    }

    /// Find the CGWindowID for a window by matching frame
    private func findCGWindowIdentifier(
        frame: CGRect,
        cgWindows: [(windowIdentifier: Int, bounds: CGRect)]
    ) -> Int? {
        // Find a window with matching bounds (allowing small tolerance for rounding)
        let tolerance: CGFloat = 2.0
        for cgWindow in cgWindows {
            if abs(cgWindow.bounds.origin.x - frame.origin.x) <= tolerance &&
               abs(cgWindow.bounds.origin.y - frame.origin.y) <= tolerance &&
               abs(cgWindow.bounds.width - frame.width) <= tolerance &&
               abs(cgWindow.bounds.height - frame.height) <= tolerance {
                return cgWindow.windowIdentifier
            }
        }
        return nil
    }

    private func findBestMatchingSnapshot(
        currentWindow: (element: AXUIElement, title: String, frame: CGRect, windowIdentifier: Int?),
        snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        // First try: match by windowIdentifier (highest priority)
        if let currentWindowId = currentWindow.windowIdentifier {
            for (index, snapshot) in snapshots.enumerated() {
                if excludedIndices.contains(index) { continue }
                if let snapshotWindowId = snapshot.windowIdentifier,
                   currentWindowId == snapshotWindowId {
                    return (index, snapshot)
                }
            }
        }

        // Second try: match by title (fallback for legacy data or when windowId unavailable)
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

        // Set minimized state (after positioning so window goes to correct spot)
        let minimizedValue: CFBoolean = snapshot.isMinimized ? kCFBooleanTrue : kCFBooleanFalse
        let minimizedResult = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            minimizedValue
        )

        let success = positionResult == .success && sizeResult == .success
        if success {
            let minimizedStatus = snapshot.isMinimized ? " (minimized)" : ""
            logger.info("Positioned: \"\(snapshot.windowTitle)\" to (\(Int(snapshot.frame.origin.x)),\(Int(snapshot.frame.origin.y)) \(Int(snapshot.frame.width))x\(Int(snapshot.frame.height)))\(minimizedStatus)")
            if minimizedResult != .success {
                logger.warning("Failed to set minimized state for: \"\(snapshot.windowTitle)\" err=\(minimizedResult.rawValue)")
            }
        } else {
            logger.error("Failed to position: \"\(snapshot.windowTitle)\" posErr=\(positionResult.rawValue) sizeErr=\(sizeResult.rawValue)")
        }
        return WindowRestoreResult(
            snapshot: snapshot,
            success: success,
            error: success ? nil : "Position: \(positionResult.rawValue), Size: \(sizeResult.rawValue)"
        )
    }
}
