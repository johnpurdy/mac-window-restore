import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("WindowEnumerator Tests")
struct WindowEnumeratorTests {

    @Test("WindowEnumerator protocol returns window snapshots")
    func protocolReturnsSnapshots() {
        let mockEnumerator = MockWindowEnumerator()
        mockEnumerator.mockWindows = [
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

        let windows = mockEnumerator.enumerateWindows()

        #expect(windows.count == 2)
        #expect(windows[0].applicationBundleIdentifier == "com.apple.Safari")
        #expect(windows[1].applicationBundleIdentifier == "com.apple.finder")
    }

    @Test("WindowEnumerator protocol returns empty array when no windows")
    func protocolReturnsEmptyArray() {
        let mockEnumerator = MockWindowEnumerator()
        mockEnumerator.mockWindows = []

        let windows = mockEnumerator.enumerateWindows()

        #expect(windows.isEmpty)
    }

    @Test("WindowEnumerator captures minimized state for windows")
    func capturesMinimizedState() {
        let mockEnumerator = MockWindowEnumerator()
        mockEnumerator.mockWindows = [
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

        let windows = mockEnumerator.enumerateWindows()

        #expect(windows.count == 2)
        #expect(windows[0].isMinimized == false)
        #expect(windows[1].isMinimized == true)
    }

    @Test("WindowEnumerator includes both visible and minimized windows")
    func includesMinimizedWindows() {
        // This test documents the expected behavior:
        // The enumerator should include minimized windows (isMinimized: true)
        // along with visible windows (isMinimized: false)
        let mockEnumerator = MockWindowEnumerator()
        mockEnumerator.mockWindows = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "GitHub - Edge",
                displayIdentifier: "display-external",
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isMinimized: false
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "Reddit - Edge",
                displayIdentifier: "display-laptop",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: true  // This window is in the Dock
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                applicationName: "Visual Studio Code",
                windowTitle: "project - VSCode",
                displayIdentifier: "display-external",
                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                isMinimized: false
            )
        ]

        let windows = mockEnumerator.enumerateWindows()

        // All 3 windows should be returned (2 visible + 1 minimized)
        #expect(windows.count == 3)

        // Verify minimized window is included
        let minimizedWindows = windows.filter { $0.isMinimized }
        #expect(minimizedWindows.count == 1)
        #expect(minimizedWindows[0].windowTitle == "Reddit - Edge")

        // Verify visible windows are included
        let visibleWindows = windows.filter { !$0.isMinimized }
        #expect(visibleWindows.count == 2)
    }
}

// Mock implementation for testing
final class MockWindowEnumerator: WindowEnumerating, @unchecked Sendable {
    var mockWindows: [WindowSnapshot] = []

    func enumerateWindows() -> [WindowSnapshot] {
        return mockWindows
    }
}
