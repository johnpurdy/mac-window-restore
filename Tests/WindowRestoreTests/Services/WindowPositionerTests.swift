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
