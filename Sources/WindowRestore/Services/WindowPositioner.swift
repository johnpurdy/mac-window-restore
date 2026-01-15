import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "restore")

private func log(_ message: String) {
    logger.info("\(message)")

    // Write to log file
    if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let logDir = appSupport.appendingPathComponent("WindowRestore")
        let logFile = logDir.appendingPathComponent("restore.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[RESTORE \(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}

/// Protocol for window positioning operations
public protocol WindowPositioning: Sendable {
    func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult]
}

/// Result of a window restore operation
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

/// Restores windows to saved positions using matching strategies from AppMatchingConfig
public final class WindowPositioner: WindowPositioning, @unchecked Sendable {
    private let config: AppMatchingConfig
    private let tabEnumerator = TabEnumerator()

    public init(config: AppMatchingConfig = AppMatchingConfig.loadOrDefault()) {
        self.config = config
    }

    public func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        let minimizedCount = snapshots.filter { $0.isMinimized }.count
        log("Starting restore: \(snapshots.count) windows (\(minimizedCount) should be minimized)")

        // Get all current windows
        let currentWindows = getCurrentWindows(for: snapshots)
        log("Found \(currentWindows.count) current windows")

        // Use WindowMatcher to find matches
        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: snapshots, current: currentWindows.map { $0.currentWindow })

        log("Matched \(matches.count) windows")

        var results: [WindowRestoreResult] = []
        var windowsNeedingMinimizeRetry: [(element: AXUIElement, snapshot: WindowSnapshot)] = []

        // Position each matched window
        for match in matches {
            // Find the AXUIElement for this current window
            guard let windowInfo = currentWindows.first(where: {
                $0.currentWindow.windowIdentifier == match.current.windowIdentifier ||
                ($0.currentWindow.title == match.current.title && $0.currentWindow.frame == match.current.frame)
            }) else {
                continue
            }

            log("Restoring: \"\(match.saved.windowTitle)\" matched to \"\(match.current.title)\"")

            // Position the window
            let result = positionWindow(window: windowInfo.element, snapshot: match.saved)
            results.append(result)

            // Handle minimize state
            let minimizeSuccess = setMinimizeStateWithVerification(window: windowInfo.element, snapshot: match.saved)
            if !minimizeSuccess {
                windowsNeedingMinimizeRetry.append((element: windowInfo.element, snapshot: match.saved))
            }
        }

        log("Restore complete: \(results.filter { $0.success }.count)/\(results.count) windows positioned")

        // Retry minimize for windows that failed
        if !windowsNeedingMinimizeRetry.isEmpty {
            log("Retrying minimize for \(windowsNeedingMinimizeRetry.count) windows...")
            retryMinimizeWithVerification(windows: windowsNeedingMinimizeRetry)
        }

        return results
    }

    // MARK: - Get Current Windows

    private func getCurrentWindows(for snapshots: [WindowSnapshot]) -> [(element: AXUIElement, currentWindow: CurrentWindow)] {
        var results: [(element: AXUIElement, currentWindow: CurrentWindow)] = []

        // Get unique bundle IDs from snapshots
        let bundleIds = Set(snapshots.map { $0.applicationBundleIdentifier })

        for bundleId in bundleIds {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
                continue
            }

            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            // Get windows
            var windowsRef: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard axResult == .success, let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            // Get CGWindowList for correlating windowIdentifiers
            let cgWindows = getCGWindowsForPid(pid)
            var usedCGWindowIds: Set<Int> = []

            let supportsTabs = config.isTabEnabledApp(bundleId)

            for window in windows {
                // Get title
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""

                // Get position
                var positionRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
                var position = CGPoint.zero
                if let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID() {
                    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                }

                // Get size
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
                var size = CGSize.zero
                if let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                }

                // Skip zero-size windows
                guard size.width > 0 && size.height > 0 else { continue }

                let frame = CGRect(origin: position, size: size)

                // Correlate with CGWindowList to get windowIdentifier
                let windowIdentifier = findCGWindowIdentifier(frame: frame, cgWindows: cgWindows, excludedIds: usedCGWindowIds)
                if let matchedId = windowIdentifier {
                    usedCGWindowIds.insert(matchedId)
                }

                // Extract tabs for browser windows
                let tabs: [String]? = supportsTabs ? tabEnumerator.extractTabs(from: window) : nil

                let currentWindow = CurrentWindow(
                    bundleIdentifier: bundleId,
                    title: title,
                    frame: frame,
                    windowIdentifier: windowIdentifier,
                    tabs: tabs
                )

                results.append((element: window, currentWindow: currentWindow))
            }
        }

        return results
    }

    private func getCGWindowsForPid(_ pid: pid_t) -> [(windowIdentifier: Int, bounds: CGRect)] {
        let options: CGWindowListOption = [.excludeDesktopElements]
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

    private func findCGWindowIdentifier(frame: CGRect, cgWindows: [(windowIdentifier: Int, bounds: CGRect)], excludedIds: Set<Int>) -> Int? {
        let tolerance: CGFloat = 2.0
        for cgWindow in cgWindows {
            if excludedIds.contains(cgWindow.windowIdentifier) { continue }
            if abs(cgWindow.bounds.origin.x - frame.origin.x) <= tolerance &&
               abs(cgWindow.bounds.origin.y - frame.origin.y) <= tolerance &&
               abs(cgWindow.bounds.width - frame.width) <= tolerance &&
               abs(cgWindow.bounds.height - frame.height) <= tolerance {
                return cgWindow.windowIdentifier
            }
        }
        return nil
    }

    // MARK: - Position Window

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

    // MARK: - Minimize State

    private func setMinimizeStateWithVerification(window: AXUIElement, snapshot: WindowSnapshot) -> Bool {
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        let currentMinimized = (minimizedRef as? Bool) ?? false

        if currentMinimized == snapshot.isMinimized {
            return true
        }

        log("  -> Will \(snapshot.isMinimized ? "minimize" : "unminimize"): \"\(snapshot.windowTitle)\"")

        let targetValue: CFBoolean = snapshot.isMinimized ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, targetValue)

        minimizedRef = nil
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        let newMinimized = (minimizedRef as? Bool) ?? false

        return newMinimized == snapshot.isMinimized
    }

    private func retryMinimizeWithVerification(windows: [(element: AXUIElement, snapshot: WindowSnapshot)]) {
        let maxRetries = 10
        let delayBetweenRetries: TimeInterval = 0.5

        var remaining = windows

        for attempt in 1...maxRetries {
            if remaining.isEmpty { break }

            log("Minimize retry attempt \(attempt)/\(maxRetries) for \(remaining.count) windows...")
            Thread.sleep(forTimeInterval: delayBetweenRetries)

            var stillFailing: [(element: AXUIElement, snapshot: WindowSnapshot)] = []

            for (element, snapshot) in remaining {
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
                let currentMinimized = (minimizedRef as? Bool) ?? false

                if currentMinimized == snapshot.isMinimized {
                    continue
                }

                let targetValue: CFBoolean = snapshot.isMinimized ? kCFBooleanTrue : kCFBooleanFalse
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, targetValue)

                minimizedRef = nil
                AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
                let newMinimized = (minimizedRef as? Bool) ?? false

                if newMinimized != snapshot.isMinimized {
                    stillFailing.append((element: element, snapshot: snapshot))
                }
            }

            remaining = stillFailing
        }

        if !remaining.isEmpty {
            log("Minimize FAILED after \(maxRetries) retries for \(remaining.count) windows")
        }
    }
}
