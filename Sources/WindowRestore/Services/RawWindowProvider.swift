import Foundation
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "accessibility")

/// A window as described by the Accessibility layer, before display assignment and
/// persistence filtering. Pure value type — it never holds an `AXUIElement`, so it stays
/// `Sendable` and the save path can be unit-tested with fakes.
public struct RawWindow: Sendable {
    public let bundleIdentifier: String
    public let applicationName: String
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let windowIdentifier: Int?
    public let tabs: [String]?

    public init(
        bundleIdentifier: String,
        applicationName: String,
        title: String,
        frame: CGRect,
        isMinimized: Bool,
        windowIdentifier: Int?,
        tabs: [String]?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.windowIdentifier = windowIdentifier
        self.tabs = tabs
    }

    public func withWindowIdentifier(_ identifier: Int?) -> RawWindow {
        RawWindow(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            windowIdentifier: identifier,
            tabs: tabs
        )
    }
}

/// Supplies the current windows for the save path. The production implementation is the
/// system glue; tests inject a fake.
public protocol RawWindowProviding: Sendable {
    func rawWindows() -> [RawWindow]
}

/// Production provider: enumerates AX windows for all regular apps, resolves each exact
/// CGWindowID, extracts browser tabs, and normalizes duplicate identifiers. It does not
/// apply the empty-title / zero-size persistence filters — those belong to
/// `WindowEnumerator`.
///
/// `Sendable` is compiler-verified: all stored properties are immutable and `Sendable`.
public final class RawWindowProvider: RawWindowProviding {
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

    public func rawWindows() -> [RawWindow] {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        var raws: [RawWindow] = []

        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier
            let supportsTabs = config.isTabEnabledApp(bundleIdentifier)

            for axWindow in axWindows(pid: pid) {
                let windowIdentifier = resolver.windowIdentifier(for: axWindow.element)
                if let windowIdentifier {
                    logger.debug("Resolved window id \(windowIdentifier) for \(appName): \(axWindow.title)")
                } else {
                    logger.warning("Unresolved window id (resolver failure) for \(appName): \(axWindow.title)")
                }
                let tabs = supportsTabs ? tabEnumerator.extractTabs(from: axWindow.element) : nil

                raws.append(RawWindow(
                    bundleIdentifier: bundleIdentifier,
                    applicationName: appName,
                    title: axWindow.title,
                    frame: axWindow.frame,
                    isMinimized: axWindow.isMinimized,
                    windowIdentifier: windowIdentifier,
                    tabs: tabs
                ))
            }
        }

        let normalized = normalizeDuplicateIdentifiers(raws)
        let nilCount = normalized.filter { $0.windowIdentifier == nil }.count
        logger.info("Save enumeration: \(normalized.count) windows, \(nilCount) without a resolved identifier")
        return normalized
    }

    /// Neutralizes duplicated non-nil identifiers so a resolver malfunction cannot produce
    /// a confident mismatch downstream.
    private func normalizeDuplicateIdentifiers(_ raws: [RawWindow]) -> [RawWindow] {
        let duplicates = WindowIdentifierNormalization.duplicateIdentifiers(raws.map { $0.windowIdentifier })
        if !duplicates.isEmpty {
            let titles = raws
                .filter { $0.windowIdentifier.map(duplicates.contains) ?? false }
                .map { $0.title }
            logger.error("Duplicate window identifiers \(duplicates) (\(titles.count) windows) neutralized on save; affected: \(titles)")
        }
        return WindowIdentifierNormalization.normalizeDuplicates(raws)
    }

    private func axWindows(pid: pid_t) -> [(element: AXUIElement, title: String, frame: CGRect, isMinimized: Bool)] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            if result != .success {
                logger.debug("AX error for PID \(pid): \(result.rawValue)")
            }
            return []
        }

        return windows.map { window in
            (
                element: window,
                title: window.stringAttribute(kAXTitleAttribute as String) ?? "",
                frame: window.windowFrame(),
                isMinimized: window.boolAttribute(kAXMinimizedAttribute as String)
            )
        }
    }
}
