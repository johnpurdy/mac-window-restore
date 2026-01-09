import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "accessibility")

public protocol WindowEnumerating: Sendable {
    func enumerateWindows() -> [WindowSnapshot]
}

public final class WindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let displayInfoProvider: DisplayInfoProviding

    public init(displayInfoProvider: DisplayInfoProviding = DisplayInfoProvider()) {
        self.displayInfoProvider = displayInfoProvider
    }

    public func enumerateWindows() -> [WindowSnapshot] {
        let displays = displayInfoProvider.getDisplays()

        // Get all running applications with regular activation policy (normal apps)
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        var snapshots: [WindowSnapshot] = []

        for app in runningApps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier

            // Get all windows for this app via Accessibility API (includes minimized)
            let axWindows = getAXWindows(pid: pid)

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

                let snapshot = WindowSnapshot(
                    applicationBundleIdentifier: bundleIdentifier,
                    applicationName: appName,
                    windowTitle: axWindow.title,
                    displayIdentifier: displayIdentifier,
                    frame: axWindow.frame,
                    isMinimized: axWindow.isMinimized
                )

                snapshots.append(snapshot)
            }
        }

        return snapshots
    }

    private func getAXWindows(pid: pid_t) -> [(title: String, frame: CGRect, isMinimized: Bool)] {
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

        return windows.compactMap { window -> (title: String, frame: CGRect, isMinimized: Bool)? in
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

            return (title: title, frame: frame, isMinimized: isMinimized)
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
