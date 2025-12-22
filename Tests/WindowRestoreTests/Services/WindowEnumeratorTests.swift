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
}

// Mock implementation for testing
final class MockWindowEnumerator: WindowEnumerating, @unchecked Sendable {
    var mockWindows: [WindowSnapshot] = []

    func enumerateWindows() -> [WindowSnapshot] {
        return mockWindows
    }
}
