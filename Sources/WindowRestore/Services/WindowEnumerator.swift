import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "accessibility")

public protocol WindowEnumerating: Sendable {
    func enumerateWindows() -> [WindowSnapshot]
}

/// A window read from the Accessibility layer, before its `CGWindowID` is resolved.
/// The split between reading these (untestable, touches live AX) and assigning ids
/// (pure, uses an injected resolver) is what makes the id logic unit-testable.
struct RawEnumeratedWindow {
    let element: AXUIElement
    let applicationBundleIdentifier: String
    let applicationName: String
    let windowTitle: String
    let displayIdentifier: String
    let frame: CGRect
    let isMinimized: Bool
    let tabs: [String]?
}

public final class WindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let displayInfoProvider: DisplayInfoProviding
    private let resolver: WindowIdentifierResolving
    private let tabEnumerator = TabEnumerator()

    public init(displayInfoProvider: DisplayInfoProviding = DisplayInfoProvider()) {
        self.displayInfoProvider = displayInfoProvider
        self.resolver = ExactWindowIdentifierResolver()
    }

    init(displayInfoProvider: DisplayInfoProviding = DisplayInfoProvider(), resolver: WindowIdentifierResolving) {
        self.displayInfoProvider = displayInfoProvider
        self.resolver = resolver
    }

    public func enumerateWindows() -> [WindowSnapshot] {
        let rawWindows = readRawWindows()
        return Self.assignSnapshots(rawWindows: rawWindows, resolver: resolver)
    }

    /// Pure assignment step: map each raw window to a snapshot, resolving its exact
    /// `CGWindowID` — except minimized windows, which are withheld an id (`nil`) to
    /// reproduce 1.0.4's `.optionOnScreenOnly` exclusion and keep them out of
    /// `CGWindowID`-based matching. The resolver is never consulted for a minimized
    /// window.
    static func assignSnapshots(
        rawWindows: [RawEnumeratedWindow],
        resolver: WindowIdentifierResolving,
        now: Date = Date()
    ) -> [WindowSnapshot] {
        rawWindows.map { raw in
            let windowIdentifier = raw.isMinimized ? nil : resolver.windowIdentifier(for: raw.element)
            return WindowSnapshot(
                applicationBundleIdentifier: raw.applicationBundleIdentifier,
                applicationName: raw.applicationName,
                windowTitle: raw.windowTitle,
                displayIdentifier: raw.displayIdentifier,
                frame: raw.frame,
                lastSeenAt: now,
                isMinimized: raw.isMinimized,
                windowIdentifier: windowIdentifier,
                tabs: raw.tabs
            )
        }
    }

    // MARK: - Accessibility reading layer

    private func readRawWindows() -> [RawEnumeratedWindow] {
        let displays = displayInfoProvider.getDisplays()

        // Get all running applications with regular activation policy (normal apps)
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        var rawWindows: [RawEnumeratedWindow] = []

        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier

            // Get all windows for this app via Accessibility API (includes minimized)
            let axWindows = getAXWindows(pid: pid)

            // Check if this app supports tab enumeration
            let supportsTabs = TabEnumerator.supportsTabEnumeration(bundleIdentifier: bundleIdentifier)

            for axWindow in axWindows {
                // Skip windows with empty titles - can't reliably match them on restore
                if axWindow.title.isEmpty {
                    continue
                }

                // Skip zero-size windows
                if axWindow.frame.width <= 0 || axWindow.frame.height <= 0 {
                    continue
                }

                // Find which display this window is on
                let displayIdentifier = findDisplayForWindow(frame: axWindow.frame, displays: displays)

                // Extract tabs for browser windows
                var tabs: [String]? = nil
                if supportsTabs {
                    tabs = tabEnumerator.extractTabs(from: axWindow.element)
                    if let extractedTabs = tabs {
                        logger.info("Extracted \(extractedTabs.count) tabs for \(appName) window: \(axWindow.title)")
                    } else {
                        logger.warning("Failed to extract tabs for \(appName) window: \(axWindow.title)")
                    }
                }

                rawWindows.append(RawEnumeratedWindow(
                    element: axWindow.element,
                    applicationBundleIdentifier: bundleIdentifier,
                    applicationName: appName,
                    windowTitle: axWindow.title,
                    displayIdentifier: displayIdentifier,
                    frame: axWindow.frame,
                    isMinimized: axWindow.isMinimized,
                    tabs: tabs
                ))
            }
        }

        return rawWindows
    }

    private func getAXWindows(pid: pid_t) -> [(element: AXUIElement, title: String, frame: CGRect, isMinimized: Bool)] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            if result != .success {
                logger.debug("AX error for PID \(pid): \(result.rawValue)")
            }
            return []
        }

        return windows.compactMap { window -> (element: AXUIElement, title: String, frame: CGRect, isMinimized: Bool)? in
            // Get title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            // Get position
            var positionRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
            var position = CGPoint.zero
            if let positionValue = positionRef,
               CFGetTypeID(positionValue) == AXValueGetTypeID() {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            }

            // Get size
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let sizeValue = sizeRef,
               CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }

            // Get minimized state
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            let isMinimized = (minimizedRef as? Bool) ?? false

            let frame = CGRect(origin: position, size: size)

            return (element: window, title: title, frame: frame, isMinimized: isMinimized)
        }
    }

    private func findDisplayForWindow(frame: CGRect, displays: [DisplayInfo]) -> String {
        // Find the display that contains the window's center point
        let windowCenter = CGPoint(
            x: frame.midX,
            y: frame.midY
        )

        for display in displays {
            let displayFrame = CGRect(
                origin: display.position,
                size: display.resolution
            )

            if displayFrame.contains(windowCenter) {
                return display.identifier
            }
        }

        // Fallback: return first display identifier or "unknown"
        return displays.first?.identifier ?? "unknown"
    }
}
