import Testing
import Foundation
import CoreGraphics
import ApplicationServices
@testable import WindowRestore

@Suite("WindowPositioner restore-side assignment Tests")
struct WindowPositionerAssignmentTests {

    @Test("Two current windows sharing a frame get their own distinct ids from the resolver")
    func distinctIdsForSameFrame() {
        let elementA = AXUIElementCreateApplication(1)
        let elementB = AXUIElementCreateApplication(2)
        let sharedFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let raw = [
            RawCurrentWindow(
                element: elementA,
                bundleIdentifier: "com.microsoft.edgemac",
                title: "A",
                frame: sharedFrame,
                tabs: nil
            ),
            RawCurrentWindow(
                element: elementB,
                bundleIdentifier: "com.microsoft.edgemac",
                title: "B",
                frame: sharedFrame,
                tabs: nil
            )
        ]

        let resolver = MockWindowIdentifierResolver([(elementA, 111), (elementB, 222)])

        let assigned = WindowPositioner.assignCurrentWindows(rawWindows: raw, resolver: resolver)

        let windowA = assigned.first { $0.currentWindow.title == "A" }
        let windowB = assigned.first { $0.currentWindow.title == "B" }
        #expect(windowA?.currentWindow.windowIdentifier == 111)
        #expect(windowB?.currentWindow.windowIdentifier == 222)
        // The element travels through unchanged so the positioner can act on it.
        #expect(windowA.map { CFEqual($0.element, elementA) } == true)
    }

    @Test("Restore side applies no minimized guard — every resolvable window gets its id")
    func noMinimizedGuardOnRestore() {
        // Restore parity with 1.0.4: the restore side resolves ids for all windows and
        // does not withhold ids from would-be-minimized windows (unlike the save side).
        let element = AXUIElementCreateApplication(3)

        let raw = [
            RawCurrentWindow(
                element: element,
                bundleIdentifier: "com.apple.Safari",
                title: "Any",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                tabs: nil
            )
        ]

        let resolver = MockWindowIdentifierResolver([(element, 555)])

        let assigned = WindowPositioner.assignCurrentWindows(rawWindows: raw, resolver: resolver)

        #expect(assigned.first?.currentWindow.windowIdentifier == 555)
    }
}
