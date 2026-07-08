import Foundation
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "restore")

/// A current window bound to the AX element that must be moved to restore it.
/// Not `Sendable`: it holds an `AXUIElement`, so it never crosses into `WindowMatcher`.
public struct CurrentWindowRecord {
    public let element: AXUIElement
    public let currentWindow: CurrentWindow

    public init(element: AXUIElement, currentWindow: CurrentWindow) {
        self.element = element
        self.currentWindow = currentWindow
    }
}

/// Supplies the live windows for the restore path, keeping each AX element bound to its
/// resolved `CurrentWindow`. The production implementation is the system glue; tests inject
/// a fake.
public protocol CurrentWindowProviding {
    func currentWindows(forBundleIdentifiers bundleIdentifiers: Set<String>) -> [CurrentWindowRecord]
}

extension CurrentWindow {
    func withWindowIdentifier(_ identifier: Int?) -> CurrentWindow {
        CurrentWindow(
            bundleIdentifier: bundleIdentifier,
            title: title,
            frame: frame,
            windowIdentifier: identifier,
            tabs: tabs
        )
    }
}

/// Production provider: enumerates AX windows for the requested bundle IDs, resolves each
/// exact CGWindowID, extracts browser tabs, and normalizes duplicate identifiers.
///
/// `Sendable` is compiler-verified: all stored properties are immutable and `Sendable`.
public final class CurrentWindowProvider: CurrentWindowProviding, Sendable {
    private let resolver: WindowIdentifierResolving
    private let config: AppMatchingConfig
    private let tabEnumerator = TabEnumerator()

    public init(
        resolver: WindowIdentifierResolving = AXWindowIdentifierResolver(),
        config: AppMatchingConfig = AppMatchingConfig.loadOrDefault()
    ) {
        self.resolver = resolver
        self.config = config
    }

    public func currentWindows(forBundleIdentifiers bundleIdentifiers: Set<String>) -> [CurrentWindowRecord] {
        var records: [CurrentWindowRecord] = []

        for bundleId in bundleIdentifiers {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
                continue
            }

            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard axResult == .success, let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            let supportsTabs = config.isTabEnabledApp(bundleId)

            for window in windows {
                let title = window.stringAttribute(kAXTitleAttribute as String) ?? ""
                let frame = window.windowFrame()

                // Skip zero-size windows: a zero-size AX element has no restorable geometry
                // and would only waste a match slot. This is a restore-side "not restorable"
                // skip, distinct from the save-side persistence filters owned by
                // WindowEnumerator (empty title / zero size).
                guard frame.width > 0 && frame.height > 0 else { continue }

                let windowIdentifier = resolver.windowIdentifier(for: window)
                if let windowIdentifier {
                    logger.debug("Resolved window id \(windowIdentifier) for \(bundleId): \(title)")
                } else {
                    logger.warning("Unresolved window id (resolver failure) for \(bundleId): \(title)")
                }
                let tabs: [String]? = supportsTabs ? tabEnumerator.extractTabs(from: window) : nil

                let currentWindow = CurrentWindow(
                    bundleIdentifier: bundleId,
                    title: title,
                    frame: frame,
                    windowIdentifier: windowIdentifier,
                    tabs: tabs
                )
                records.append(CurrentWindowRecord(element: window, currentWindow: currentWindow))
            }
        }

        return normalizeDuplicateIdentifiers(records)
    }

    private func normalizeDuplicateIdentifiers(_ records: [CurrentWindowRecord]) -> [CurrentWindowRecord] {
        let duplicates = WindowIdentifierNormalization.duplicateIdentifiers(records.map { $0.currentWindow.windowIdentifier })
        if !duplicates.isEmpty {
            let titles = records
                .filter { $0.currentWindow.windowIdentifier.map(duplicates.contains) ?? false }
                .map { $0.currentWindow.title }
            logger.error("Duplicate window identifiers \(duplicates) (\(titles.count) windows) neutralized on restore; affected: \(titles)")
        }
        return WindowIdentifierNormalization.normalizeDuplicates(records)
    }
}
