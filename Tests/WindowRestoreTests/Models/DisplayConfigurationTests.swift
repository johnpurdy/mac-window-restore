import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("DisplayConfiguration Tests")
struct DisplayConfigurationTests {

    @Test("DisplayConfiguration encodes to JSON and decodes back correctly")
    func encodingDecoding() throws {
        let display1 = DisplayInfo(
            identifier: "serial-123",
            name: "Main Monitor",
            resolution: CGSize(width: 3840, height: 2160),
            position: CGPoint(x: 0, y: 0)
        )

        let display2 = DisplayInfo(
            identifier: "serial-456",
            name: "Secondary Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 3840, y: 0)
        )

        let window1 = WindowSnapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            windowTitle: "Apple",
            displayIdentifier: "serial-123",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let captureDate = Date()
        let original = DisplayConfiguration(
            identifier: "config-abc",
            displays: [display1, display2],
            windows: [window1],
            capturedAt: captureDate
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayConfiguration.self, from: data)

        #expect(decoded.identifier == original.identifier)
        #expect(decoded.displays.count == 2)
        #expect(decoded.windows.count == 1)
        #expect(decoded.displays[0].identifier == "serial-123")
        #expect(decoded.windows[0].applicationBundleIdentifier == "com.apple.Safari")
    }

    @Test("DisplayConfiguration with empty windows array encodes correctly")
    func emptyWindows() throws {
        let display = DisplayInfo(
            identifier: "serial-only",
            name: "Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let original = DisplayConfiguration(
            identifier: "config-empty",
            displays: [display],
            windows: [],
            capturedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayConfiguration.self, from: data)

        #expect(decoded.windows.isEmpty)
        #expect(decoded.displays.count == 1)
    }

    @Test("DisplayConfiguration equality works correctly")
    func equality() throws {
        let display = DisplayInfo(
            identifier: "serial-abc",
            name: "Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let captureDate = Date()

        let config1 = DisplayConfiguration(
            identifier: "config-1",
            displays: [display],
            windows: [],
            capturedAt: captureDate
        )

        let config2 = DisplayConfiguration(
            identifier: "config-1",
            displays: [display],
            windows: [],
            capturedAt: captureDate
        )

        let config3 = DisplayConfiguration(
            identifier: "config-2",
            displays: [display],
            windows: [],
            capturedAt: captureDate
        )

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}
