import Foundation
import CoreGraphics

/// Represents a current window for matching purposes
public struct CurrentWindow: Sendable {
    public let bundleIdentifier: String
    public let title: String
    public let frame: CGRect
    public let windowIdentifier: Int?
    public let tabs: [String]?

    public init(
        bundleIdentifier: String,
        title: String,
        frame: CGRect,
        windowIdentifier: Int?,
        tabs: [String]?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.frame = frame
        self.windowIdentifier = windowIdentifier
        self.tabs = tabs
    }
}

/// A matched pair of saved snapshot and current window
public struct WindowMatch: Sendable {
    public let saved: WindowSnapshot
    public let current: CurrentWindow

    public init(saved: WindowSnapshot, current: CurrentWindow) {
        self.saved = saved
        self.current = current
    }
}

/// Matches saved window snapshots to current windows using strategies from AppMatchingConfig
public final class WindowMatcher: Sendable {
    private let config: AppMatchingConfig

    public init(config: AppMatchingConfig) {
        self.config = config
    }

    /// Find matches between saved snapshots and current windows
    public func findMatches(saved: [WindowSnapshot], current: [CurrentWindow]) -> [WindowMatch] {
        var matches: [WindowMatch] = []
        var usedSavedIndices = Set<Int>()
        var usedCurrentIndices = Set<Int>()

        // Group by bundle identifier for efficient lookup
        let savedByBundle = Dictionary(grouping: saved.enumerated().map { ($0.offset, $0.element) }) { $0.1.applicationBundleIdentifier }
        let currentByBundle = Dictionary(grouping: current.enumerated().map { ($0.offset, $0.element) }) { $0.1.bundleIdentifier }

        // Process each bundle
        let allBundles = Set(savedByBundle.keys).union(Set(currentByBundle.keys))

        for bundleId in allBundles {
            let savedForBundle = savedByBundle[bundleId] ?? []
            let currentForBundle = currentByBundle[bundleId] ?? []

            // Filter out already-used windows
            var availableSaved = savedForBundle.filter { !usedSavedIndices.contains($0.0) }
            var availableCurrent = currentForBundle.filter { !usedCurrentIndices.contains($0.0) }

            guard !availableSaved.isEmpty && !availableCurrent.isEmpty else { continue }

            // Strategy 1: Single-window matching (for non-multi-window apps only)
            if !config.isMultiWindowApp(bundleId) {
                if availableSaved.count == 1 && availableCurrent.count == 1 {
                    let savedItem = availableSaved[0]
                    let currentItem = availableCurrent[0]

                    matches.append(WindowMatch(saved: savedItem.1, current: currentItem.1))
                    usedSavedIndices.insert(savedItem.0)
                    usedCurrentIndices.insert(currentItem.0)
                    continue
                }
            }

            // Strategy 2: CGWindowID matching (for multi-window apps)
            // Build a map of current windows by their windowIdentifier
            var currentByWindowId: [Int: (Int, CurrentWindow)] = [:]
            for item in availableCurrent {
                if let windowId = item.1.windowIdentifier {
                    currentByWindowId[windowId] = item
                }
            }

            // Match saved windows to current windows by CGWindowID
            for savedItem in availableSaved {
                guard let savedWindowId = savedItem.1.windowIdentifier,
                      let currentItem = currentByWindowId[savedWindowId],
                      !usedCurrentIndices.contains(currentItem.0) else {
                    continue
                }

                matches.append(WindowMatch(saved: savedItem.1, current: currentItem.1))
                usedSavedIndices.insert(savedItem.0)
                usedCurrentIndices.insert(currentItem.0)
            }

            // Refresh available lists for next strategies
            availableSaved = savedForBundle.filter { !usedSavedIndices.contains($0.0) }
            availableCurrent = currentForBundle.filter { !usedCurrentIndices.contains($0.0) }

            // Strategy 3: Tab matching (for tab-enabled apps only)
            if config.isTabEnabledApp(bundleId) {
                // Find best tab matches - pair saved windows with current windows by highest overlap
                var tabMatches: [(savedIndex: Int, currentIndex: Int, saved: WindowSnapshot, current: CurrentWindow, overlap: Double)] = []

                for savedItem in availableSaved {
                    guard let savedTabs = savedItem.1.tabs, !savedTabs.isEmpty else { continue }

                    for currentItem in availableCurrent {
                        guard !usedCurrentIndices.contains(currentItem.0),
                              let currentTabs = currentItem.1.tabs, !currentTabs.isEmpty else { continue }

                        let overlap = calculateTabOverlap(savedTabs: savedTabs, currentTabs: currentTabs)
                        if overlap >= config.tabMatchThreshold {
                            tabMatches.append((
                                savedIndex: savedItem.0,
                                currentIndex: currentItem.0,
                                saved: savedItem.1,
                                current: currentItem.1,
                                overlap: overlap
                            ))
                        }
                    }
                }

                // Sort by overlap descending and greedily assign best matches
                tabMatches.sort { $0.overlap > $1.overlap }

                for tabMatch in tabMatches {
                    guard !usedSavedIndices.contains(tabMatch.savedIndex),
                          !usedCurrentIndices.contains(tabMatch.currentIndex) else { continue }

                    matches.append(WindowMatch(saved: tabMatch.saved, current: tabMatch.current))
                    usedSavedIndices.insert(tabMatch.savedIndex)
                    usedCurrentIndices.insert(tabMatch.currentIndex)
                }

                // Refresh available lists for next strategies
                availableSaved = savedForBundle.filter { !usedSavedIndices.contains($0.0) }
                availableCurrent = currentForBundle.filter { !usedCurrentIndices.contains($0.0) }
            }

            // Strategy 4: Title matching (fallback for multi-window apps)
            // Build a map of current windows by their title
            var currentByTitle: [String: [(Int, CurrentWindow)]] = [:]
            for item in availableCurrent {
                currentByTitle[item.1.title, default: []].append(item)
            }

            // Match saved windows to current windows by exact title
            for savedItem in availableSaved {
                guard let candidates = currentByTitle[savedItem.1.windowTitle],
                      let currentItem = candidates.first(where: { !usedCurrentIndices.contains($0.0) }) else {
                    continue
                }

                matches.append(WindowMatch(saved: savedItem.1, current: currentItem.1))
                usedSavedIndices.insert(savedItem.0)
                usedCurrentIndices.insert(currentItem.0)
            }
        }

        return matches
    }

    /// Calculate tab overlap as percentage of the smaller tab list
    private func calculateTabOverlap(savedTabs: [String], currentTabs: [String]) -> Double {
        let savedSet = Set(savedTabs)
        let currentSet = Set(currentTabs)
        let matchingCount = savedSet.intersection(currentSet).count
        let smallerCount = min(savedTabs.count, currentTabs.count)
        guard smallerCount > 0 else { return 0.0 }
        return Double(matchingCount) / Double(smallerCount)
    }
}
