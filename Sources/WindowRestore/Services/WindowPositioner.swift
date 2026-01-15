import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "restore")
private let isDevMode = true  // TODO: Change back to CommandLine.arguments.contains("--dev") before release

private func devLog(_ message: String) {
    logger.info("\(message)")
    if isDevMode {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[RESTORE \(timestamp)] \(message)\n"
        print(logMessage, terminator: "")

        // Also write to log file for when running as app
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let logDir = appSupport.appendingPathComponent("WindowRestore")
            let logFile = logDir.appendingPathComponent("restore.log")
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
}

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
    private let tabEnumerator = TabEnumerator()

    /// Minimum percentage of tabs that must match to consider windows the same
    private let tabMatchThreshold: Double = 0.50

    public init() {}

    public func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        let minimizedCount = snapshots.filter { $0.isMinimized }.count
        devLog("Starting restore: \(snapshots.count) windows (\(minimizedCount) should be minimized)")

        // Group snapshots by application bundle identifier
        var snapshotsByApp: [String: [WindowSnapshot]] = [:]
        for snapshot in snapshots {
            snapshotsByApp[snapshot.applicationBundleIdentifier, default: []].append(snapshot)
        }

        var results: [WindowRestoreResult] = []
        var windowsNeedingMinimizeChange: [(element: AXUIElement, snapshot: WindowSnapshot)] = []

        // Pass 1: Position all windows and set minimize state inline
        for (bundleId, appSnapshots) in snapshotsByApp {
            let (appResults, needsMinimizeRetry) = restoreWindowsForApp(bundleId: bundleId, snapshots: appSnapshots)
            results.append(contentsOf: appResults)
            windowsNeedingMinimizeChange.append(contentsOf: needsMinimizeRetry)
        }

        devLog("Restore complete: \(results.filter { $0.success }.count)/\(results.count) windows positioned")

        // Pass 2: Retry minimize for windows that failed
        if !windowsNeedingMinimizeChange.isEmpty {
            devLog("Retrying minimize for \(windowsNeedingMinimizeChange.count) windows that failed...")
            retryMinimizeWithVerification(windows: windowsNeedingMinimizeChange)
        }

        return results
    }

    private func restoreWindowsForApp(bundleId: String, snapshots: [WindowSnapshot]) -> (results: [WindowRestoreResult], needsMinimizeRetry: [(element: AXUIElement, snapshot: WindowSnapshot)]) {
        // Find the running application
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleId
        ).first else {
            // App not running - don't report as failure, just skip
            return ([], [])
        }

        let pid = app.processIdentifier
        let appName = app.localizedName ?? bundleId
        let minimizedInSnapshots = snapshots.filter { $0.isMinimized }.count
        devLog("Processing \(appName): \(snapshots.count) saved windows (\(minimizedInSnapshots) minimized)")

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
            return ([], [])
        }

        devLog("  AX returned \(windows.count) windows for \(appName)")

        // DIAGNOSTIC: Query CGWindowList with different options to understand what's visible
        let cgWindowsAll = getCGWindowsForPidDiagnostic(pid, appName: appName)
        devLog("  CGWindowList (ALL windows): \(cgWindowsAll.count) for \(appName)")

        // Log expected vs actual windowIds
        let expectedWindowIds = Set(snapshots.compactMap { $0.windowIdentifier })
        let actualWindowIds = Set(cgWindowsAll.map { $0.windowIdentifier })
        let missingIds = expectedWindowIds.subtracting(actualWindowIds)
        if !missingIds.isEmpty {
            devLog("  MISSING windowIds (not in CGWindowList): \(missingIds.sorted())")
        }

        // Get CGWindowList for this app's windows to correlate windowIdentifiers
        let cgWindows = getCGWindowsForPid(pid)

        // Check if this app supports tab enumeration
        let supportsTabs = TabEnumerator.supportsTabEnumeration(bundleIdentifier: bundleId)

        // Get current window info (title, position, size, windowId, tabs) for all windows
        // Track used CGWindowIDs to avoid assigning the same ID to multiple AX windows
        var currentWindows: [(element: AXUIElement, title: String, frame: CGRect, windowIdentifier: Int?, tabs: [String]?)] = []
        var usedCGWindowIds: Set<Int> = []
        devLog("  CGWindowList returned \(cgWindows.count) windows for \(appName)")
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
                // Correlate with CGWindowList to get windowIdentifier (excluding already-used IDs)
                let windowIdentifier = findCGWindowIdentifier(frame: frame, cgWindows: cgWindows, excludedIds: usedCGWindowIds)

                // Track used IDs to prevent duplicate assignment
                if let matchedId = windowIdentifier {
                    usedCGWindowIds.insert(matchedId)
                }

                // Extract tabs for browser windows
                let tabs: [String]? = supportsTabs ? tabEnumerator.extractTabs(from: window) : nil

                // Always log AX window position for debugging correlation
                let titleForLog = title.isEmpty ? "(empty)" : title
                let tabInfo = tabs.map { " [\($0.count) tabs]" } ?? ""
                if let matchedId = windowIdentifier {
                    devLog("  AX: (\(Int(frame.origin.x)),\(Int(frame.origin.y))) \(Int(frame.width))x\(Int(frame.height)) -> CG \(matchedId) \"\(titleForLog)\"\(tabInfo)")
                } else {
                    devLog("  AX: (\(Int(frame.origin.x)),\(Int(frame.origin.y))) \(Int(frame.width))x\(Int(frame.height)) -> NO MATCH \"\(titleForLog)\"\(tabInfo)")
                }
                currentWindows.append((element: window, title: title, frame: frame, windowIdentifier: windowIdentifier, tabs: tabs))
            }
        }

        // Log snapshots with windowIds for debugging
        let snapshotsWithIds = snapshots.filter { $0.windowIdentifier != nil }
        if !snapshotsWithIds.isEmpty {
            devLog("  Snapshots with windowIds: \(snapshotsWithIds.map { "\($0.windowIdentifier!)" }.joined(separator: ", "))")
        }
        let currentWithIds = currentWindows.filter { $0.windowIdentifier != nil }
        if !currentWithIds.isEmpty {
            devLog("  Current windows with windowIds: \(currentWithIds.map { "\($0.windowIdentifier!)" }.joined(separator: ", "))")
        }

        // Iterate over CURRENT windows, find saved snapshot for each
        // This ensures each current window is only moved once
        var results: [WindowRestoreResult] = []
        var needsMinimizeRetry: [(element: AXUIElement, snapshot: WindowSnapshot)] = []
        var usedSnapshotIndices: Set<Int> = []

        for currentWindow in currentWindows {
            let matchResult = findBestMatchingSnapshot(
                currentWindow: (element: currentWindow.element, title: currentWindow.title, frame: currentWindow.frame, windowIdentifier: currentWindow.windowIdentifier, tabs: currentWindow.tabs),
                snapshots: snapshots,
                excludedIndices: usedSnapshotIndices,
                totalCurrentWindows: currentWindows.count
            )

            if let (snapshotIndex, snapshot) = matchResult {
                usedSnapshotIndices.insert(snapshotIndex)
                let matchType = (currentWindow.windowIdentifier != nil && snapshot.windowIdentifier != nil && currentWindow.windowIdentifier == snapshot.windowIdentifier) ? "windowId" : "title"
                devLog("Matched (\(matchType)): \"\(currentWindow.title)\"")

                // Position the window
                let restoreResult = positionWindow(window: currentWindow.element, snapshot: snapshot)
                results.append(restoreResult)

                // Try to set minimize state and check if it worked
                let minimizeSuccess = setMinimizeStateWithVerification(window: currentWindow.element, snapshot: snapshot)
                if !minimizeSuccess {
                    // Add to retry queue
                    needsMinimizeRetry.append((element: currentWindow.element, snapshot: snapshot))
                }
            }
            // If no matching snapshot found, don't report as error - window may be from another desktop
        }

        return (results, needsMinimizeRetry)
    }

    /// Get CGWindowList entries for a specific process
    private func getCGWindowsForPid(_ pid: pid_t) -> [(windowIdentifier: Int, bounds: CGRect)] {
        // Include ALL windows, not just on-screen. Minimized windows and windows
        // temporarily marked off-screen after display changes still have valid
        // positions and CGWindowIDs for correlation.
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

    /// DIAGNOSTIC: Get ALL CGWindowList entries for a process (not just on-screen) with detailed logging
    private func getCGWindowsForPidDiagnostic(_ pid: pid_t, appName: String) -> [(windowIdentifier: Int, bounds: CGRect, layer: Int, isOnScreen: Bool, name: String?)] {
        // Query WITHOUT .optionOnScreenOnly to get ALL windows
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [(windowIdentifier: Int, bounds: CGRect, layer: Int, isOnScreen: Bool, name: String?)] = []

        for windowInfo in windowInfoList {
            guard let windowNumber = windowInfo[kCGWindowNumber as String] as? Int,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else {
                continue
            }

            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? -1
            let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? false
            let name = windowInfo[kCGWindowName as String] as? String

            var bounds = CGRect.zero
            if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let x = boundsDict["X"] as? CGFloat,
               let y = boundsDict["Y"] as? CGFloat,
               let width = boundsDict["Width"] as? CGFloat,
               let height = boundsDict["Height"] as? CGFloat {
                bounds = CGRect(x: x, y: y, width: width, height: height)
            }

            results.append((windowIdentifier: windowNumber, bounds: bounds, layer: layer, isOnScreen: isOnScreen, name: name))

            // Log details for each window
            let onScreenStr = isOnScreen ? "ON-SCREEN" : "OFF-SCREEN"
            let nameStr = name ?? "(no name)"
            devLog("    CGWindow \(windowNumber): \(onScreenStr), layer=\(layer), pos=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y))) \(Int(bounds.width))x\(Int(bounds.height)) \"\(nameStr)\"")
        }

        return results
    }

    /// Find the CGWindowID for a window by matching frame
    private func findCGWindowIdentifier(
        frame: CGRect,
        cgWindows: [(windowIdentifier: Int, bounds: CGRect)],
        excludedIds: Set<Int> = []
    ) -> Int? {
        // Find a window with matching bounds (allowing small tolerance for rounding)
        // Skip IDs that have already been assigned to other AX windows
        let tolerance: CGFloat = 2.0
        for cgWindow in cgWindows {
            if excludedIds.contains(cgWindow.windowIdentifier) {
                continue
            }
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
        currentWindow: (element: AXUIElement, title: String, frame: CGRect, windowIdentifier: Int?, tabs: [String]?),
        snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>,
        totalCurrentWindows: Int = 1
    ) -> (Int, WindowSnapshot)? {
        // Check if this is a single-window app (chat apps, etc.)
        // If there's exactly 1 snapshot and 1 current window, match by bundle ID
        let availableSnapshots = snapshots.enumerated().filter { !excludedIndices.contains($0.offset) }
        if let firstSnapshot = availableSnapshots.first,
           availableSnapshots.count == 1 && totalCurrentWindows == 1,
           TabEnumerator.usesSingleWindowMatching(bundleIdentifier: firstSnapshot.element.applicationBundleIdentifier) {
            devLog("  Single-window app match: \"\(currentWindow.title)\" -> \"\(firstSnapshot.element.windowTitle)\"")
            return (firstSnapshot.offset, firstSnapshot.element)
        }

        // First try: match by tabs (highest priority for browser windows)
        // Uses percentage of matching tabs to identify the same window
        if let currentTabs = currentWindow.tabs, !currentTabs.isEmpty {
            var bestTabMatch: (index: Int, snapshot: WindowSnapshot, matchPercentage: Double)?

            for (index, snapshot) in snapshots.enumerated() {
                if excludedIndices.contains(index) { continue }
                guard let savedTabs = snapshot.tabs, !savedTabs.isEmpty else { continue }

                // Calculate tab overlap percentage
                let matchPercentage = calculateTabMatchPercentage(currentTabs: currentTabs, savedTabs: savedTabs)

                if matchPercentage >= tabMatchThreshold {
                    // Keep the best match (highest percentage)
                    if bestTabMatch == nil || matchPercentage > bestTabMatch!.matchPercentage {
                        bestTabMatch = (index, snapshot, matchPercentage)
                    }
                }
            }

            if let match = bestTabMatch {
                devLog("  Tab match: \(Int(match.matchPercentage * 100))% for \"\(currentWindow.title)\"")
                return (match.index, match.snapshot)
            }
        }

        // Second try: match by windowIdentifier (for non-browser windows or browsers without tab data)
        // When multiple snapshots have the same windowId, pick the most recent one
        if let currentWindowId = currentWindow.windowIdentifier {
            var bestMatch: (index: Int, snapshot: WindowSnapshot, lastSeen: Date)?
            for (index, snapshot) in snapshots.enumerated() {
                if excludedIndices.contains(index) { continue }
                if let snapshotWindowId = snapshot.windowIdentifier,
                   currentWindowId == snapshotWindowId {
                    // Keep the most recently seen snapshot
                    if bestMatch == nil || snapshot.lastSeenAt > bestMatch!.lastSeen {
                        bestMatch = (index, snapshot, snapshot.lastSeenAt)
                    }
                }
            }
            if let match = bestMatch {
                return (match.index, match.snapshot)
            }
        }

        // Third try: match by title (fallback for legacy data or when windowId unavailable)
        // Also pick the most recent if multiple matches
        var bestTitleMatch: (index: Int, snapshot: WindowSnapshot, lastSeen: Date)?
        for (index, snapshot) in snapshots.enumerated() {
            if excludedIndices.contains(index) { continue }
            if !currentWindow.title.isEmpty && currentWindow.title == snapshot.windowTitle {
                if bestTitleMatch == nil || snapshot.lastSeenAt > bestTitleMatch!.lastSeen {
                    bestTitleMatch = (index, snapshot, snapshot.lastSeenAt)
                }
            }
        }
        if let match = bestTitleMatch {
            return (match.index, match.snapshot)
        }

        return nil
    }

    /// Calculate the percentage of tabs that match between two tab lists
    /// Uses the smaller list as the denominator
    private func calculateTabMatchPercentage(currentTabs: [String], savedTabs: [String]) -> Double {
        let currentSet = Set(currentTabs)
        let savedSet = Set(savedTabs)

        let matchingTabs = currentSet.intersection(savedSet)
        let smallerCount = min(currentTabs.count, savedTabs.count)

        guard smallerCount > 0 else { return 0.0 }
        return Double(matchingTabs.count) / Double(smallerCount)
    }

    private func positionWindow(window: AXUIElement, snapshot: WindowSnapshot) -> WindowRestoreResult {
        // Get current position/size BEFORE move
        var beforePos = CGPoint.zero
        var beforeSize = CGSize.zero
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &beforePos)
        }
        if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &beforeSize)
        }

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

        // Get position/size AFTER move
        var afterPos = CGPoint.zero
        var afterSize = CGSize.zero
        posRef = nil
        sizeRef = nil
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &afterPos)
        }
        if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &afterSize)
        }

        let success = positionResult == .success && sizeResult == .success
        let moved = (Int(beforePos.x) != Int(afterPos.x) || Int(beforePos.y) != Int(afterPos.y) ||
                     Int(beforeSize.width) != Int(afterSize.width) || Int(beforeSize.height) != Int(afterSize.height))
        if success {
            let moveStatus = moved ? "MOVED" : "NO CHANGE"
            devLog("[\(moveStatus)] \"\(snapshot.windowTitle)\" BEFORE:(\(Int(beforePos.x)),\(Int(beforePos.y)) \(Int(beforeSize.width))x\(Int(beforeSize.height))) AFTER:(\(Int(afterPos.x)),\(Int(afterPos.y)) \(Int(afterSize.width))x\(Int(afterSize.height))) TARGET:(\(Int(snapshot.frame.origin.x)),\(Int(snapshot.frame.origin.y)) \(Int(snapshot.frame.width))x\(Int(snapshot.frame.height)))")
        } else {
            devLog("FAILED to position: \"\(snapshot.windowTitle)\" posErr=\(positionResult.rawValue) sizeErr=\(sizeResult.rawValue)")
        }
        return WindowRestoreResult(
            snapshot: snapshot,
            success: success,
            error: success ? nil : "Position: \(positionResult.rawValue), Size: \(sizeResult.rawValue)"
        )
    }

    /// Set minimize state and verify it actually changed. Returns true if successful.
    private func setMinimizeStateWithVerification(window: AXUIElement, snapshot: WindowSnapshot) -> Bool {
        // Get current minimized state
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        let currentMinimized = (minimizedRef as? Bool) ?? false

        // Already in correct state
        if currentMinimized == snapshot.isMinimized {
            if snapshot.isMinimized {
                devLog("  -> Already minimized: \"\(snapshot.windowTitle)\"")
            }
            // Don't log "already not minimized" - too noisy
            return true
        }

        devLog("  -> Will \(snapshot.isMinimized ? "minimize" : "unminimize"): \"\(snapshot.windowTitle)\" (current=\(currentMinimized), target=\(snapshot.isMinimized))")

        // Set the minimize state
        let targetValue: CFBoolean = snapshot.isMinimized ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, targetValue)

        // Verify it changed
        minimizedRef = nil
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        let newMinimized = (minimizedRef as? Bool) ?? false

        let action = snapshot.isMinimized ? "Minimize" : "Unminimize"
        if newMinimized == snapshot.isMinimized {
            devLog("  -> \(action)d: \"\(snapshot.windowTitle)\"")
            return true
        } else {
            devLog("  -> \(action) pending: \"\(snapshot.windowTitle)\" (will retry)")
            return false
        }
    }

    /// Retry minimize for windows that failed, with delays between attempts
    private func retryMinimizeWithVerification(windows: [(element: AXUIElement, snapshot: WindowSnapshot)]) {
        let maxRetries = 10
        let delayBetweenRetries: TimeInterval = 0.5  // 500ms between retries

        var remaining = windows

        for attempt in 1...maxRetries {
            if remaining.isEmpty { break }

            devLog("Minimize retry attempt \(attempt)/\(maxRetries) for \(remaining.count) windows...")
            Thread.sleep(forTimeInterval: delayBetweenRetries)

            var stillFailing: [(element: AXUIElement, snapshot: WindowSnapshot)] = []

            for (element, snapshot) in remaining {
                // Get current state
                var minimizedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
                let currentMinimized = (minimizedRef as? Bool) ?? false

                // Already in correct state (maybe changed by another means)
                if currentMinimized == snapshot.isMinimized {
                    let action = snapshot.isMinimized ? "Minimized" : "Unminimized"
                    devLog("  -> \(action) (now OK): \"\(snapshot.windowTitle)\"")
                    continue
                }

                // Try to set it
                let targetValue: CFBoolean = snapshot.isMinimized ? kCFBooleanTrue : kCFBooleanFalse
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, targetValue)

                // Verify
                minimizedRef = nil
                AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
                let newMinimized = (minimizedRef as? Bool) ?? false

                if newMinimized == snapshot.isMinimized {
                    let action = snapshot.isMinimized ? "Minimized" : "Unminimized"
                    devLog("  -> \(action) (retry \(attempt)): \"\(snapshot.windowTitle)\"")
                } else {
                    stillFailing.append((element: element, snapshot: snapshot))
                }
            }

            remaining = stillFailing
        }

        // Log any that still failed after all retries
        if !remaining.isEmpty {
            devLog("Minimize FAILED after \(maxRetries) retries for \(remaining.count) windows:")
            for (_, snapshot) in remaining {
                let action = snapshot.isMinimized ? "minimize" : "unminimize"
                devLog("  -> Could not \(action): \"\(snapshot.windowTitle)\"")
            }
        }
    }
}
