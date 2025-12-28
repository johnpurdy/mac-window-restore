import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

public protocol WindowEnumerating: Sendable {
    func enumerateWindows() -> [WindowSnapshot]
}

public final class WindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let displayInfoProvider: DisplayInfoProviding

    public init(displayInfoProvider: DisplayInfoProviding = DisplayInfoProvider()) {
        self.displayInfoProvider = displayInfoProvider
    }

    public func enumerateWindows() -> [WindowSnapshot] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let displays = displayInfoProvider.getDisplays()

        // Cache AXUIElement windows per PID to avoid repeated lookups
        var axWindowCache: [pid_t: [(title: String, frame: CGRect)]] = [:]

        return windowList.compactMap { windowInfo -> WindowSnapshot? in
            guard let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  windowLayer == 0, // Normal windows only (kCGNormalWindowLevel)
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width > 0, height > 0 // Skip zero-size windows
            else {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)

            // Get app info
            let runningApp = NSRunningApplication(processIdentifier: ownerPID)
            let bundleIdentifier = runningApp?.bundleIdentifier ?? "unknown"
            let appName = runningApp?.localizedName ?? windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"

            // Get window title via Accessibility API
            let windowTitle = getWindowTitle(
                pid: ownerPID,
                frame: frame,
                cache: &axWindowCache
            )

            // Skip windows with empty titles - can't reliably match them on restore
            if windowTitle.isEmpty {
                return nil
            }

            // Find which display this window is on
            let displayIdentifier = findDisplayForWindow(frame: frame, displays: displays)

            return WindowSnapshot(
                applicationBundleIdentifier: bundleIdentifier,
                applicationName: appName,
                windowTitle: windowTitle,
                displayIdentifier: displayIdentifier,
                frame: frame
            )
        }
    }

    private func getWindowTitle(pid: pid_t, frame: CGRect, cache: inout [pid_t: [(title: String, frame: CGRect)]]) -> String {
        // Build cache for this PID if not already done
        if cache[pid] == nil {
            cache[pid] = getAXWindows(pid: pid)
        }

        guard let axWindows = cache[pid] else {
            return ""
        }

        // Find matching window by position (with small tolerance for rounding)
        let tolerance: CGFloat = 5.0
        for axWindow in axWindows {
            if abs(axWindow.frame.origin.x - frame.origin.x) <= tolerance &&
               abs(axWindow.frame.origin.y - frame.origin.y) <= tolerance &&
               abs(axWindow.frame.width - frame.width) <= tolerance &&
               abs(axWindow.frame.height - frame.height) <= tolerance {
                return axWindow.title
            }
        }

        return ""
    }

    private func getAXWindows(pid: pid_t) -> [(title: String, frame: CGRect)] {
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
                FileLogger.shared.log("AX error for PID \(pid): \(result.rawValue)")
            }
            return []
        }

        return windows.compactMap { window -> (title: String, frame: CGRect)? in
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

            let frame = CGRect(origin: position, size: size)

            return (title: title, frame: frame)
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
