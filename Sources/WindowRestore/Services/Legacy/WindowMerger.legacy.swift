import Foundation

public enum WindowMerger {

    /// Merges current visible windows with existing saved windows, filtering out stale entries.
    ///
    /// - Parameters:
    ///   - currentWindows: Windows currently visible on the screen
    ///   - existingWindows: Windows previously saved (may include windows from other desktops)
    ///   - staleThreshold: Maximum age in seconds; windows older than this are removed
    /// - Returns: Merged list with current windows taking precedence and stale windows removed
    public static func merge(
        currentWindows: [WindowSnapshot],
        existingWindows: [WindowSnapshot],
        staleThreshold: TimeInterval
    ) -> [WindowSnapshot] {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-staleThreshold)

        // Create a set of unique identifiers for current windows
        // Primary key: bundleId|id:windowIdentifier when available
        // Fallback key: bundleId|title:windowTitle when no windowIdentifier
        var currentWindowKeys = Set<String>()
        for window in currentWindows {
            let key = generateWindowKey(window)
            currentWindowKeys.insert(key)
        }

        // Start with current windows
        var mergedWindows = currentWindows

        // Add windows from existing config that:
        // 1. Aren't currently visible (they're on other desktops)
        // 2. Are not stale (lastSeenAt is after the cutoff date)
        for existingWindow in existingWindows {
            let key = generateWindowKey(existingWindow)
            if !currentWindowKeys.contains(key) && existingWindow.lastSeenAt > cutoffDate {
                mergedWindows.append(existingWindow)
            }
        }

        return mergedWindows
    }

    /// Generates a unique key for a window.
    /// Uses windowIdentifier as primary key when available, falls back to title.
    private static func generateWindowKey(_ window: WindowSnapshot) -> String {
        if let windowIdentifier = window.windowIdentifier {
            return "\(window.applicationBundleIdentifier)|id:\(windowIdentifier)"
        }
        return "\(window.applicationBundleIdentifier)|title:\(window.windowTitle)"
    }
}
