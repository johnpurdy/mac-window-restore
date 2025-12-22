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
