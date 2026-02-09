import Foundation

/// Merges current windows with existing saved windows
public enum WindowMerger {

    /// Merges current windows with existing saved windows using smart matching.
    ///
    /// When `displayConfigChanged` is false (same monitor session):
    /// - Uses CGWindowID as primary key (valid within session)
    /// - Falls back to tabs/title for windows without CGWindowID
    ///
    /// When `displayConfigChanged` is true (monitors connected/disconnected):
    /// - Ignores all existing CGWindowIDs (they're invalid after monitor change)
    /// - Matches by tabs (for browser windows) or title (for others)
    /// - Current windows get fresh CGWindowIDs written to config
    ///
    /// - Parameters:
    ///   - currentWindows: Windows currently visible
    ///   - existingWindows: Windows previously saved
    ///   - staleThreshold: Maximum age in seconds; older windows are pruned
    ///   - displayConfigChanged: True if monitor configuration changed since last save
    /// - Returns: Merged window list
    public static func merge(
        currentWindows: [WindowSnapshot],
        existingWindows: [WindowSnapshot],
        staleThreshold: TimeInterval,
        displayConfigChanged: Bool = false
    ) -> [WindowSnapshot] {
        let config = AppMatchingConfig.loadOrDefault()
        return merge(
            currentWindows: currentWindows,
            existingWindows: existingWindows,
            staleThreshold: staleThreshold,
            displayConfigChanged: displayConfigChanged,
            config: config
        )
    }

    /// Merges with explicit config (for testing)
    public static func merge(
        currentWindows: [WindowSnapshot],
        existingWindows: [WindowSnapshot],
        staleThreshold: TimeInterval,
        displayConfigChanged: Bool,
        config: AppMatchingConfig
    ) -> [WindowSnapshot] {
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-staleThreshold)

        // Track which existing windows have been matched to current windows
        var matchedExistingIndices = Set<Int>()

        // Start with current windows (they have fresh CGWindowIDs, positions, etc.)
        var mergedWindows: [WindowSnapshot] = []

        for currentWindow in currentWindows {
            // Try to find a matching existing window
            let matchIndex = findMatchingExistingWindow(
                current: currentWindow,
                existingWindows: existingWindows,
                excludeIndices: matchedExistingIndices,
                displayConfigChanged: displayConfigChanged,
                config: config
            )

            if let index = matchIndex {
                matchedExistingIndices.insert(index)
            }

            // Add current window (it has fresh data)
            mergedWindows.append(currentWindow)
        }

        // Add unmatched existing windows that aren't stale
        // These are windows on other desktops that we couldn't see
        for (index, existingWindow) in existingWindows.enumerated() {
            if !matchedExistingIndices.contains(index) && existingWindow.lastSeenAt > cutoffDate {
                mergedWindows.append(existingWindow)
            }
        }

        return mergedWindows
    }

    /// Find matching existing window using smart matching
    private static func findMatchingExistingWindow(
        current: WindowSnapshot,
        existingWindows: [WindowSnapshot],
        excludeIndices: Set<Int>,
        displayConfigChanged: Bool,
        config: AppMatchingConfig
    ) -> Int? {
        let bundleId = current.applicationBundleIdentifier

        // Strategy 1: CGWindowID match (only valid if display config hasn't changed)
        if !displayConfigChanged, let currentId = current.windowIdentifier {
            for (index, existing) in existingWindows.enumerated() {
                if excludeIndices.contains(index) { continue }
                if existing.applicationBundleIdentifier != bundleId { continue }

                if let existingId = existing.windowIdentifier, existingId == currentId {
                    return index
                }
            }
        }

        // Strategy 2: Tab match (for tab-enabled apps)
        if config.isTabEnabledApp(bundleId), let currentTabs = current.tabs, !currentTabs.isEmpty {
            var bestMatch: (index: Int, overlap: Double, titleMatches: Bool)? = nil

            for (index, existing) in existingWindows.enumerated() {
                if excludeIndices.contains(index) { continue }
                if existing.applicationBundleIdentifier != bundleId { continue }

                if let existingTabs = existing.tabs, !existingTabs.isEmpty {
                    let overlap = calculateTabOverlap(savedTabs: existingTabs, currentTabs: currentTabs)
                    if overlap >= config.tabMatchThreshold {
                        let titleMatches = existing.windowTitle == current.windowTitle

                        // Prefer higher overlap, then title match as tiebreaker
                        if let best = bestMatch {
                            if overlap > best.overlap || (overlap == best.overlap && titleMatches && !best.titleMatches) {
                                bestMatch = (index, overlap, titleMatches)
                            }
                        } else {
                            bestMatch = (index, overlap, titleMatches)
                        }
                    }
                }
            }

            if let match = bestMatch {
                return match.index
            }
        }

        // Strategy 3: Title match (fallback)
        // Only use title matching if:
        // - Display config changed (all CGWindowIDs are invalid), OR
        // - Current window has no CGWindowID (legacy or couldn't be determined)
        // If current window HAS a CGWindowID that didn't match, don't fall back to title
        // because different CGWindowIDs mean different windows
        let shouldUseTitleFallback = displayConfigChanged || current.windowIdentifier == nil

        if shouldUseTitleFallback {
            for (index, existing) in existingWindows.enumerated() {
                if excludeIndices.contains(index) { continue }
                if existing.applicationBundleIdentifier != bundleId { continue }

                if existing.windowTitle == current.windowTitle {
                    return index
                }
            }
        }

        return nil
    }

    /// Calculate tab overlap as percentage of the smaller tab list
    private static func calculateTabOverlap(savedTabs: [String], currentTabs: [String]) -> Double {
        let savedSet = Set(savedTabs)
        let currentSet = Set(currentTabs)
        let matchingCount = savedSet.intersection(currentSet).count
        let smallerCount = min(savedTabs.count, currentTabs.count)
        guard smallerCount > 0 else { return 0.0 }
        return Double(matchingCount) / Double(smallerCount)
    }
}
