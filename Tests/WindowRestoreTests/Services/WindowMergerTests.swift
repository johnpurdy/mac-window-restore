import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("WindowMerger Tests")
struct WindowMergerTests {

    @Test("mergeWindows removes windows older than threshold")
    func pruneStaleWindows() {
        let now = Date()
        let eightDaysAgo = now.addingTimeInterval(-8 * 24 * 3600)
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        let sevenDayThreshold: TimeInterval = 7 * 24 * 3600

        let currentWindows = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Current Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                lastSeenAt: now
            )
        ]

        let existingWindows = [
            // This should be kept (2 days old, within threshold)
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                windowTitle: "Recent Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: twoDaysAgo
            ),
            // This should be pruned (8 days old, older than 7 day threshold)
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                windowTitle: "Old Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                lastSeenAt: eightDaysAgo
            )
        ]

        let merged = WindowMerger.merge(
            currentWindows: currentWindows,
            existingWindows: existingWindows,
            staleThreshold: sevenDayThreshold
        )

        // Should have: current Safari + recent Finder = 2 windows
        // Old Terminal should be pruned
        #expect(merged.count == 2)
        #expect(merged.contains { $0.windowTitle == "Current Window" })
        #expect(merged.contains { $0.windowTitle == "Recent Window" })
        #expect(!merged.contains { $0.windowTitle == "Old Window" })
    }

    @Test("mergeWindows updates lastSeenAt for matching windows")
    func updatesLastSeenAt() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        let sevenDayThreshold: TimeInterval = 7 * 24 * 3600

        let currentWindows = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Apple",
                displayIdentifier: "display-1",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                lastSeenAt: now
            )
        ]

        let existingWindows = [
            // Same window with old timestamp - should use current window's timestamp
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Apple",
                displayIdentifier: "display-1",
                frame: CGRect(x: 50, y: 50, width: 800, height: 600),
                lastSeenAt: twoDaysAgo
            )
        ]

        let merged = WindowMerger.merge(
            currentWindows: currentWindows,
            existingWindows: existingWindows,
            staleThreshold: sevenDayThreshold
        )

        #expect(merged.count == 1)
        #expect(merged[0].lastSeenAt == now)
    }

    @Test("mergeWindows keeps windows from other desktops within threshold")
    func keepsOtherDesktopWindows() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 3600)
        let sevenDayThreshold: TimeInterval = 7 * 24 * 3600

        let currentWindows = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Current Desktop",
                displayIdentifier: "display-1",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                lastSeenAt: now
            )
        ]

        let existingWindows = [
            // Different window (other desktop) - should be kept
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                windowTitle: "Other Desktop",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: oneDayAgo
            )
        ]

        let merged = WindowMerger.merge(
            currentWindows: currentWindows,
            existingWindows: existingWindows,
            staleThreshold: sevenDayThreshold
        )

        #expect(merged.count == 2)
    }
}
