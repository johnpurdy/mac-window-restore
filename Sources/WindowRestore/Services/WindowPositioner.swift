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
/// A current window read from the Accessibility layer, before its `CGWindowID` is
/// resolved. Mirrors `RawEnumeratedWindow` on the save side. Note: the restore side
/// reads no minimized state — it resolves an id for every window (parity with 1.0.4).
struct RawCurrentWindow {
    let element: AXUIElement
    let bundleIdentifier: String
    let title: String
    let frame: CGRect
    let tabs: [String]?
}

public final class WindowPositioner: WindowPositioning, @unchecked Sendable {
    private let config: AppMatchingConfig
    private let resolver: WindowIdentifierResolving
    private let tabEnumerator = TabEnumerator()

    public init(config: AppMatchingConfig = AppMatchingConfig.loadOrDefault()) {
        self.config = config
        self.resolver = ExactWindowIdentifierResolver()
    }

    init(config: AppMatchingConfig = AppMatchingConfig.loadOrDefault(), resolver: WindowIdentifierResolving) {
        self.config = config
        self.resolver = resolver
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

            let savedIdentifier = match.saved.windowIdentifier.map(String.init) ?? "nil"
            let currentIdentifier = match.current.windowIdentifier.map(String.init) ?? "nil"
            let matchBasis: String
            if let saved = match.saved.windowIdentifier,
               let current = match.current.windowIdentifier,
               saved == current {
                matchBasis = "identifier"
            } else {
                matchBasis = "title-or-tab"
            }
            log("Restoring: \"\(match.saved.windowTitle)\" [savedIdentifier=\(savedIdentifier)] -> \"\(match.current.title)\" [currentIdentifier=\(currentIdentifier)] via \(matchBasis)")

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
        let rawWindows = readRawCurrentWindows(for: snapshots)
        return Self.assignCurrentWindows(rawWindows: rawWindows, resolver: resolver)
    }

    /// Pure assignment step: resolve the exact `CGWindowID` for every current window.
    /// The restore side applies no minimized guard — parity with 1.0.4, which included
    /// minimized windows in the current-window id pool.
    static func assignCurrentWindows(
        rawWindows: [RawCurrentWindow],
        resolver: WindowIdentifierResolving
    ) -> [(element: AXUIElement, currentWindow: CurrentWindow)] {
        rawWindows.map { raw in
            let currentWindow = CurrentWindow(
                bundleIdentifier: raw.bundleIdentifier,
                title: raw.title,
                frame: raw.frame,
                windowIdentifier: resolver.windowIdentifier(for: raw.element),
                tabs: raw.tabs
            )
            return (element: raw.element, currentWindow: currentWindow)
        }
    }

    // MARK: - Accessibility reading layer

    private func readRawCurrentWindows(for snapshots: [WindowSnapshot]) -> [RawCurrentWindow] {
        var rawWindows: [RawCurrentWindow] = []

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

                // Extract tabs for browser windows
                let tabs: [String]? = supportsTabs ? tabEnumerator.extractTabs(from: window) : nil

                rawWindows.append(RawCurrentWindow(
                    element: window,
                    bundleIdentifier: bundleId,
                    title: title,
                    frame: frame,
                    tabs: tabs
                ))
            }
        }

        return rawWindows
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
