import Foundation
import CoreGraphics

/// Protocol representing a current window's identifying properties for matching
public protocol CurrentWindowInfo {
    var title: String { get }
    var frame: CGRect { get }
    var bundleIdentifier: String { get }
}

/// Matches current windows to saved snapshots using title and position-based matching
public struct WindowMatcher: Sendable {
    /// Maximum distance (in pixels) for position-based fallback matching
    public let distanceThreshold: CGFloat

    public init(distanceThreshold: CGFloat = 200) {
        self.distanceThreshold = distanceThreshold
    }

    /// Find the best matching snapshot for a current window
    /// - Parameters:
    ///   - currentWindow: The current window to find a match for
    ///   - snapshots: Available saved snapshots to match against
    ///   - excludedIndices: Indices of snapshots already matched to other windows
    /// - Returns: Tuple of (index, snapshot) if a match is found, nil otherwise
    public func findMatch<T: CurrentWindowInfo>(
        for currentWindow: T,
        in snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        // First, try to find an exact title match
        if let titleMatch = findTitleMatch(
            for: currentWindow,
            in: snapshots,
            excludedIndices: excludedIndices
        ) {
            return titleMatch
        }

        // Fallback: position-based matching within same app
        return findPositionMatch(
            for: currentWindow,
            in: snapshots,
            excludedIndices: excludedIndices
        )
    }

    // MARK: - Private Methods

    private func findTitleMatch<T: CurrentWindowInfo>(
        for currentWindow: T,
        in snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        for (index, snapshot) in snapshots.enumerated() {
            if excludedIndices.contains(index) { continue }

            if !currentWindow.title.isEmpty && currentWindow.title == snapshot.windowTitle {
                return (index, snapshot)
            }
        }
        return nil
    }

    private func findPositionMatch<T: CurrentWindowInfo>(
        for currentWindow: T,
        in snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        var bestMatch: (index: Int, snapshot: WindowSnapshot, distance: CGFloat)?

        for (index, snapshot) in snapshots.enumerated() {
            if excludedIndices.contains(index) { continue }

            // Only match within the same app
            if currentWindow.bundleIdentifier != snapshot.applicationBundleIdentifier {
                continue
            }

            let distance = distanceBetweenFrames(currentWindow.frame, snapshot.frame)

            // Only consider if within threshold
            if distance > distanceThreshold {
                continue
            }

            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (index, snapshot, distance)
            }
        }

        if let match = bestMatch {
            return (match.index, match.snapshot)
        }

        return nil
    }

    private func distanceBetweenFrames(_ frame1: CGRect, _ frame2: CGRect) -> CGFloat {
        // Use center-to-center distance
        let center1 = CGPoint(x: frame1.midX, y: frame1.midY)
        let center2 = CGPoint(x: frame2.midX, y: frame2.midY)

        let deltaX = center1.x - center2.x
        let deltaY = center1.y - center2.y

        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}
