import Foundation
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices
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

/// A single restore action: move `record.element` to `snapshot`'s frame/minimized state.
private struct RestoreStep {
    let snapshot: WindowSnapshot
    let record: CurrentWindowRecord
    let reason: WindowMatchReason
}

/// Restores windows to saved positions.
///
/// Identity comes from the exact CGWindowID resolved by `CurrentWindowProvider`; the
/// matcher returns the index of the chosen current record, so the element that is moved is
/// exactly the one the matcher selected — there is no post-match re-lookup that could pick
/// the wrong window when identifiers are nil.
public final class WindowPositioner: WindowPositioning, @unchecked Sendable {
    private let config: AppMatchingConfig
    private let currentWindowProvider: CurrentWindowProviding
    private let elementPositioning: WindowElementPositioning

    public init(
        config: AppMatchingConfig = AppMatchingConfig.loadOrDefault(),
        currentWindowProvider: CurrentWindowProviding = CurrentWindowProvider(),
        elementPositioning: WindowElementPositioning = AXWindowElementPositioner()
    ) {
        self.config = config
        self.currentWindowProvider = currentWindowProvider
        self.elementPositioning = elementPositioning
    }

    public func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        let minimizedCount = snapshots.filter { $0.isMinimized }.count
        log("Starting restore: \(snapshots.count) windows (\(minimizedCount) should be minimized)")

        // Gather live windows, keeping each AX element bound to its resolved identity.
        let bundleIdentifiers = Set(snapshots.map { $0.applicationBundleIdentifier })
        let records = currentWindowProvider.currentWindows(forBundleIdentifiers: bundleIdentifiers)
        log("Found \(records.count) current windows")

        // Match, then build a plan that carries the exact selected record through.
        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: snapshots, current: records.map { $0.currentWindow })
        let plan = matches.map { match in
            RestoreStep(snapshot: match.saved, record: records[match.currentIndex], reason: match.reason)
        }

        logMatchSummary(plan: plan, savedCount: snapshots.count, currentCount: records.count)

        var results: [WindowRestoreResult] = []
        var windowsNeedingMinimizeRetry: [(element: AXUIElement, snapshot: WindowSnapshot)] = []

        for step in plan {
            let savedId = step.snapshot.windowIdentifier.map(String.init) ?? "nil"
            let currentId = step.record.currentWindow.windowIdentifier.map(String.init) ?? "nil"
            log("Restoring: \"\(step.snapshot.windowTitle)\" [id \(savedId)] matched to "
                + "\"\(step.record.currentWindow.title)\" [id \(currentId)] via \(step.reason.rawValue)")

            let positionResult = elementPositioning.position(step.record.element, to: step.snapshot.frame)
            results.append(WindowRestoreResult(
                snapshot: step.snapshot,
                success: positionResult.positioned,
                error: positionResult.positioned ? nil : positionErrorText(positionResult)
            ))

            if !elementPositioning.setMinimized(step.record.element, step.snapshot.isMinimized) {
                windowsNeedingMinimizeRetry.append((element: step.record.element, snapshot: step.snapshot))
            }
        }

        log("Restore complete: \(results.filter { $0.success }.count)/\(results.count) windows positioned")

        if !windowsNeedingMinimizeRetry.isEmpty {
            log("Retrying minimize for \(windowsNeedingMinimizeRetry.count) windows...")
            retryMinimize(windows: windowsNeedingMinimizeRetry)
        }

        return results
    }

    private func positionErrorText(_ result: ElementPositionResult) -> String {
        let position = result.positionError?.rawValue ?? Int32(AXError.success.rawValue)
        let size = result.sizeError?.rawValue ?? Int32(AXError.success.rawValue)
        return "Position: \(position), Size: \(size)"
    }

    private func logMatchSummary(plan: [RestoreStep], savedCount: Int, currentCount: Int) {
        var byReason: [WindowMatchReason: Int] = [:]
        for step in plan {
            byReason[step.reason, default: 0] += 1
        }
        let unmatchedSaved = savedCount - plan.count
        let unmatchedCurrent = currentCount - plan.count
        log("Matched \(plan.count) windows"
            + " (id: \(byReason[.windowIdentifier, default: 0]),"
            + " singleWindow: \(byReason[.singleWindow, default: 0]),"
            + " tabs: \(byReason[.tabs, default: 0]),"
            + " title: \(byReason[.title, default: 0]));"
            + " unmatched saved: \(unmatchedSaved), unmatched current: \(unmatchedCurrent)")
    }

    // MARK: - Minimize Retry

    private func retryMinimize(windows: [(element: AXUIElement, snapshot: WindowSnapshot)]) {
        let maxRetries = 10
        let delayBetweenRetries: TimeInterval = 0.5

        var remaining = windows

        for attempt in 1...maxRetries {
            if remaining.isEmpty { break }

            log("Minimize retry attempt \(attempt)/\(maxRetries) for \(remaining.count) windows...")
            Thread.sleep(forTimeInterval: delayBetweenRetries)

            remaining = remaining.filter { element, snapshot in
                !elementPositioning.setMinimized(element, snapshot.isMinimized)
            }
        }

        if !remaining.isEmpty {
            log("Minimize FAILED after \(maxRetries) retries for \(remaining.count) windows")
        }
    }
}
