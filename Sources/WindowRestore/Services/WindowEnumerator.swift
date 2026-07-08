import Foundation
import CoreGraphics

public protocol WindowEnumerating: Sendable {
    func enumerateWindows() -> [WindowSnapshot]
}

/// Builds `WindowSnapshot`s from the raw windows supplied by a `RawWindowProviding`.
///
/// Owns the persistence-boundary filters (empty title, zero size) and display assignment.
/// It no longer touches Accessibility or CGWindowList — that glue lives in
/// `RawWindowProvider`, which also resolves exact window identifiers.
public final class WindowEnumerator: WindowEnumerating, @unchecked Sendable {
    private let displayInfoProvider: DisplayInfoProviding
    private let rawWindowProvider: RawWindowProviding

    public init(
        displayInfoProvider: DisplayInfoProviding = DisplayInfoProvider(),
        rawWindowProvider: RawWindowProviding = RawWindowProvider()
    ) {
        self.displayInfoProvider = displayInfoProvider
        self.rawWindowProvider = rawWindowProvider
    }

    public func enumerateWindows() -> [WindowSnapshot] {
        let displays = displayInfoProvider.getDisplays()

        return rawWindowProvider.rawWindows().compactMap { raw in
            // Skip windows we can't reliably match on restore.
            if raw.title.isEmpty { return nil }
            // Skip zero-size windows.
            if raw.frame.width <= 0 || raw.frame.height <= 0 { return nil }

            let displayIdentifier = findDisplayForWindow(frame: raw.frame, displays: displays)

            return WindowSnapshot(
                applicationBundleIdentifier: raw.bundleIdentifier,
                applicationName: raw.applicationName,
                windowTitle: raw.title,
                displayIdentifier: displayIdentifier,
                frame: raw.frame,
                isMinimized: raw.isMinimized,
                windowIdentifier: raw.windowIdentifier,
                tabs: raw.tabs
            )
        }
    }

    private func findDisplayForWindow(frame: CGRect, displays: [DisplayInfo]) -> String {
        let windowCenter = CGPoint(x: frame.midX, y: frame.midY)

        for display in displays {
            let displayFrame = CGRect(origin: display.position, size: display.resolution)
            if displayFrame.contains(windowCenter) {
                return display.identifier
            }
        }

        return displays.first?.identifier ?? "unknown"
    }
}
