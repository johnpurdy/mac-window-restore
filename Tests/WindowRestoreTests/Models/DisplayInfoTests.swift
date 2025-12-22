import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("DisplayInfo Tests")
struct DisplayInfoTests {

    @Test("DisplayInfo encodes to JSON and decodes back correctly")
    func encodingDecoding() throws {
        let original = DisplayInfo(
            identifier: "serial-12345",
            name: "LG UltraFine 5K",
            resolution: CGSize(width: 5120, height: 2880),
            position: CGPoint(x: 0, y: 0)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayInfo.self, from: data)

        #expect(decoded.identifier == original.identifier)
        #expect(decoded.name == original.name)
        #expect(decoded.resolution == original.resolution)
        #expect(decoded.position == original.position)
    }

    @Test("DisplayInfo with negative position encodes correctly")
    func negativePosition() throws {
        let original = DisplayInfo(
            identifier: "serial-left-monitor",
            name: "Dell U2720Q",
            resolution: CGSize(width: 3840, height: 2160),
            position: CGPoint(x: -3840, y: 0)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DisplayInfo.self, from: data)

        #expect(decoded.position.x == -3840)
    }

    @Test("DisplayInfo equality works correctly")
    func equality() throws {
        let display1 = DisplayInfo(
            identifier: "serial-abc",
            name: "Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let display2 = DisplayInfo(
            identifier: "serial-abc",
            name: "Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let display3 = DisplayInfo(
            identifier: "serial-xyz",
            name: "Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        #expect(display1 == display2)
        #expect(display1 != display3)
    }
}
