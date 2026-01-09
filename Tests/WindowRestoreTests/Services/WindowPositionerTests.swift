import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("WindowPositioner Tests")
struct WindowPositionerTests {

    @Test("WindowPositioner protocol can restore windows")
    func protocolRestoresWindows() {
        let mockPositioner = MockWindowPositioner()

        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Apple",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600)
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                windowTitle: "Documents",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 600, height: 400)
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })
    }

    @Test("WindowPositioner reports failures for apps not running")
    func reportsFailuresForMissingApps() {
        let mockPositioner = MockWindowPositioner()
        mockPositioner.failForBundleIds = ["com.missing.app"]

        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Apple",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600)
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.missing.app",
                applicationName: "Missing",
                windowTitle: "Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 600, height: 400)
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        #expect(results.count == 2)
        #expect(results[0].success)
        #expect(!results[1].success)
    }

    @Test("WindowPositioner restores minimized state from snapshot")
    func restoresMinimizedState() {
        // This test documents the expected behavior:
        // When restoring, windows should be minimized/unminimized based on saved state
        let mockPositioner = MockWindowPositioner()

        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Visible Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: false
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Minimized Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                isMinimized: true
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })
        // Verify the snapshots retain their isMinimized state
        #expect(results[0].snapshot.isMinimized == false)
        #expect(results[1].snapshot.isMinimized == true)
    }

    @Test("WindowPositioner handles mixed minimized and visible windows")
    func handlesMixedMinimizedAndVisible() {
        let mockPositioner = MockWindowPositioner()

        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "GitHub",
                displayIdentifier: "display-external",
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isMinimized: false
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "Reddit",
                displayIdentifier: "display-laptop",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: true  // Should be minimized on restore
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Visual Studio Code",
                windowTitle: "project",
                displayIdentifier: "display-external",
                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                isMinimized: false
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.success })

        // Check minimized states are preserved
        let minimizedResults = results.filter { $0.snapshot.isMinimized }
        #expect(minimizedResults.count == 1)
        #expect(minimizedResults[0].snapshot.windowTitle == "Reddit")
    }

    @Test("WindowPositioner matches by windowIdentifier when available")
    func matchesByWindowIdentifier() {
        let mockPositioner = MockWindowPositionerWithWindowId()

        // Saved snapshots with windowIdentifiers
        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Old Tab Title",  // Title when saved
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                windowIdentifier: 12345
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Another Tab",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 67890
            )
        ]

        // Mock current windows - same windowIds but different titles due to tab switches
        mockPositioner.mockCurrentWindows = [
            MockCurrentWindow(
                title: "New Tab Title",  // Title changed!
                frame: CGRect(x: 50, y: 50, width: 800, height: 600),
                windowIdentifier: 12345  // Same window
            ),
            MockCurrentWindow(
                title: "Different Tab",  // Title also changed
                frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                windowIdentifier: 67890  // Same window
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        // Both windows should be matched and restored by windowIdentifier
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })
    }

    @Test("WindowPositioner falls back to title match when windowIdentifier is nil")
    func fallsBackToTitleMatch() {
        let mockPositioner = MockWindowPositionerWithWindowId()

        // Saved snapshot without windowIdentifier (legacy data)
        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Apple",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                windowIdentifier: nil  // No windowId
            )
        ]

        // Mock current window - has windowId but snapshot doesn't, so use title
        mockPositioner.mockCurrentWindows = [
            MockCurrentWindow(
                title: "Apple",  // Same title
                frame: CGRect(x: 50, y: 50, width: 800, height: 600),
                windowIdentifier: 99999  // Has windowId but can't match
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        // Should match by title fallback
        #expect(results.count == 1)
        #expect(results[0].success)
    }

    @Test("WindowPositioner prefers windowIdentifier over title")
    func prefersWindowIdentifierOverTitle() {
        let mockPositioner = MockWindowPositionerWithWindowId()

        // Two saved snapshots: one has matching windowId, other has matching title
        let snapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Wrong Title",  // Title doesn't match
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                windowIdentifier: 12345  // But windowId matches
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Current Title",  // Title matches
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999  // But windowId doesn't match
            )
        ]

        // Current window with specific windowId and title
        mockPositioner.mockCurrentWindows = [
            MockCurrentWindow(
                title: "Current Title",  // Matches second snapshot's title
                frame: CGRect(x: 50, y: 50, width: 800, height: 600),
                windowIdentifier: 12345  // But matches first snapshot's windowId
            )
        ]

        let results = mockPositioner.restoreWindows(snapshots: snapshots)

        // Should match first snapshot (by windowId), not second (by title)
        #expect(results.count == 1)
        #expect(results[0].success)
        #expect(results[0].snapshot.windowIdentifier == 12345)  // Matched by windowId
        #expect(results[0].snapshot.frame.origin.x == 100)  // Position from first snapshot
    }
}

// Mock implementation for testing
final class MockWindowPositioner: WindowPositioning, @unchecked Sendable {
    var failForBundleIds: Set<String> = []

    func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        return snapshots.map { snapshot in
            if failForBundleIds.contains(snapshot.applicationBundleIdentifier) {
                return WindowRestoreResult(
                    snapshot: snapshot,
                    success: false,
                    error: "App not running"
                )
            }
            return WindowRestoreResult(
                snapshot: snapshot,
                success: true,
                error: nil
            )
        }
    }
}

// Mock current window for windowId-based tests
struct MockCurrentWindow {
    let title: String
    let frame: CGRect
    let windowIdentifier: Int?
}

// Mock implementation that simulates windowId-based matching
final class MockWindowPositionerWithWindowId: WindowPositioning, @unchecked Sendable {
    var mockCurrentWindows: [MockCurrentWindow] = []

    func restoreWindows(snapshots: [WindowSnapshot]) -> [WindowRestoreResult] {
        var results: [WindowRestoreResult] = []
        var usedSnapshotIndices: Set<Int> = []

        // Iterate over current windows, find best matching snapshot
        for currentWindow in mockCurrentWindows {
            if let (snapshotIndex, snapshot) = findBestMatchingSnapshot(
                currentWindow: currentWindow,
                snapshots: snapshots,
                excludedIndices: usedSnapshotIndices
            ) {
                usedSnapshotIndices.insert(snapshotIndex)
                results.append(WindowRestoreResult(
                    snapshot: snapshot,
                    success: true,
                    error: nil
                ))
            }
        }

        return results
    }

    private func findBestMatchingSnapshot(
        currentWindow: MockCurrentWindow,
        snapshots: [WindowSnapshot],
        excludedIndices: Set<Int>
    ) -> (Int, WindowSnapshot)? {
        // First try: match by windowIdentifier (highest priority)
        if let currentWindowId = currentWindow.windowIdentifier {
            for (index, snapshot) in snapshots.enumerated() {
                if excludedIndices.contains(index) { continue }
                if let snapshotWindowId = snapshot.windowIdentifier,
                   currentWindowId == snapshotWindowId {
                    return (index, snapshot)
                }
            }
        }

        // Second try: match by title (fallback)
        for (index, snapshot) in snapshots.enumerated() {
            if excludedIndices.contains(index) { continue }
            if !currentWindow.title.isEmpty && currentWindow.title == snapshot.windowTitle {
                return (index, snapshot)
            }
        }

        return nil
    }
}
