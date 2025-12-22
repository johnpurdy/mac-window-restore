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
}
