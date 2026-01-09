import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("WindowSnapshot Tests")
struct WindowSnapshotTests {

    @Test("WindowSnapshot encodes to JSON and decodes back correctly")
    func encodingDecoding() throws {
        let original = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            windowTitle: "Apple",
            displayIdentifier: "display-abc123",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        #expect(decoded.applicationBundleIdentifier == original.applicationBundleIdentifier)
        #expect(decoded.applicationName == original.applicationName)
        #expect(decoded.windowTitle == original.windowTitle)
        #expect(decoded.displayIdentifier == original.displayIdentifier)
        #expect(decoded.frame == original.frame)
    }

    @Test("WindowSnapshot with empty window title encodes correctly")
    func emptyWindowTitle() throws {
        let original = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.finder",
            applicationName: "Finder",
            windowTitle: "",
            displayIdentifier: "display-xyz",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        #expect(decoded.windowTitle == "")
    }

    @Test("WindowSnapshot with negative frame origin encodes correctly")
    func negativeFrameOrigin() throws {
        let original = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            windowTitle: "bash",
            displayIdentifier: "display-left",
            frame: CGRect(x: -1920, y: 0, width: 800, height: 600)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        #expect(decoded.frame.origin.x == -1920)
    }

    @Test("WindowSnapshot with lastSeenAt encodes and decodes correctly")
    func lastSeenAtEncodingDecoding() throws {
        let now = Date()
        let original = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            windowTitle: "Apple",
            displayIdentifier: "display-abc123",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            lastSeenAt: now
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        #expect(decoded.lastSeenAt == original.lastSeenAt)
    }

    @Test("WindowSnapshot decodes legacy JSON without lastSeenAt")
    func legacyJsonDecoding() throws {
        // JSON saved before lastSeenAt was added
        let legacyJson = """
        {
            "applicationBundleIdentifier": "com.apple.Safari",
            "applicationName": "Safari",
            "windowTitle": "Apple",
            "displayIdentifier": "display-abc123",
            "frame": [[100, 200], [800, 600]]
        }
        """

        let decoder = JSONDecoder()
        let data = legacyJson.data(using: .utf8)!
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        #expect(decoded.applicationBundleIdentifier == "com.apple.Safari")
        #expect(decoded.applicationName == "Safari")
        // lastSeenAt should get a default value (recent date)
        #expect(decoded.lastSeenAt <= Date())
    }

    @Test("WindowSnapshot stores isMinimized state")
    func isMinimizedState() throws {
        let minimized = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            windowTitle: "Apple",
            displayIdentifier: "display-abc123",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            isMinimized: true
        )

        let notMinimized = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            windowTitle: "Google",
            displayIdentifier: "display-abc123",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600),
            isMinimized: false
        )

        #expect(minimized.isMinimized == true)
        #expect(notMinimized.isMinimized == false)

        // Verify encoding/decoding preserves the value
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let minimizedData = try encoder.encode(minimized)
        let decodedMinimized = try decoder.decode(WindowSnapshot.self, from: minimizedData)
        #expect(decodedMinimized.isMinimized == true)

        let notMinimizedData = try encoder.encode(notMinimized)
        let decodedNotMinimized = try decoder.decode(WindowSnapshot.self, from: notMinimizedData)
        #expect(decodedNotMinimized.isMinimized == false)
    }

    @Test("WindowSnapshot decodes legacy JSON without isMinimized as false")
    func legacyJsonWithoutIsMinimized() throws {
        // JSON saved before isMinimized was added (but has lastSeenAt)
        let legacyJson = """
        {
            "applicationBundleIdentifier": "com.apple.Safari",
            "applicationName": "Safari",
            "windowTitle": "Apple",
            "displayIdentifier": "display-abc123",
            "frame": [[100, 200], [800, 600]],
            "lastSeenAt": 0
        }
        """

        let decoder = JSONDecoder()
        let data = legacyJson.data(using: .utf8)!
        let decoded = try decoder.decode(WindowSnapshot.self, from: data)

        // isMinimized should default to false for legacy JSON
        #expect(decoded.isMinimized == false)
    }
}
