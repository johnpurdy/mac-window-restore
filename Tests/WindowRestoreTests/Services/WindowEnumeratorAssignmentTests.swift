import Testing
import Foundation
import CoreGraphics
import ApplicationServices
@testable import WindowRestore

/// Mock resolver keyed by element **reference identity** (`ObjectIdentifier`), so each
/// element maps to its own response and the test proves the id follows the element rather
/// than the frame or call order. It records which elements it was consulted for, so tests
/// can assert the save-side minimized guard short-circuits before the resolver is called.
/// The `consulted` set is guarded by a lock so the `@unchecked Sendable` promise holds.
final class MockWindowIdentifierResolver: WindowIdentifierResolving, @unchecked Sendable {
    private let responses: [ObjectIdentifier: Int?]
    private let lock = NSLock()
    private var consulted: Set<ObjectIdentifier> = []

    init(_ responses: [(AXUIElement, Int?)]) {
        var map: [ObjectIdentifier: Int?] = [:]
        for (element, identifier) in responses {
            map[ObjectIdentifier(element as AnyObject)] = identifier
        }
        self.responses = map
    }

    func windowIdentifier(for element: AXUIElement) -> Int? {
        let key = ObjectIdentifier(element as AnyObject)
        lock.lock()
        consulted.insert(key)
        lock.unlock()
        // Two-level optional: outer nil = element unknown, inner nil = mapped to no id.
        return responses[key] ?? nil
    }

    func wasConsulted(for element: AXUIElement) -> Bool {
        let key = ObjectIdentifier(element as AnyObject)
        lock.lock()
        defer { lock.unlock() }
        return consulted.contains(key)
    }
}

@Suite("WindowEnumerator save-side assignment Tests")
struct WindowEnumeratorAssignmentTests {

    @Test("Two windows sharing a frame get their own distinct ids from the resolver")
    func distinctIdsForSameFrame() {
        // Same frame, distinct elements (different PIDs) — the exact scenario frame
        // correlation gets wrong.
        let elementA = AXUIElementCreateApplication(1)
        let elementB = AXUIElementCreateApplication(2)
        let sharedFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let raw = [
            RawEnumeratedWindow(
                element: elementA,
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "A",
                displayIdentifier: "display-1",
                frame: sharedFrame,
                isMinimized: false,
                tabs: nil
            ),
            RawEnumeratedWindow(
                element: elementB,
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: "B",
                displayIdentifier: "display-1",
                frame: sharedFrame,
                isMinimized: false,
                tabs: nil
            )
        ]

        let resolver = MockWindowIdentifierResolver([(elementA, 111), (elementB, 222)])

        let snapshots = WindowEnumerator.assignSnapshots(rawWindows: raw, resolver: resolver)

        let snapshotA = snapshots.first { $0.windowTitle == "A" }
        let snapshotB = snapshots.first { $0.windowTitle == "B" }
        #expect(snapshotA?.windowIdentifier == 111)
        #expect(snapshotB?.windowIdentifier == 222)
    }

    @Test("Minimized window gets a nil id and the resolver is not consulted for it")
    func minimizedGetsNilWithoutConsultingResolver() {
        let visibleElement = AXUIElementCreateApplication(1)
        let minimizedElement = AXUIElementCreateApplication(2)

        let raw = [
            RawEnumeratedWindow(
                element: visibleElement,
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Visible",
                displayIdentifier: "display-1",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                isMinimized: false,
                tabs: nil
            ),
            RawEnumeratedWindow(
                element: minimizedElement,
                applicationBundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                windowTitle: "Minimized",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: true,
                tabs: nil
            )
        ]

        // Backend would hand back an id for the minimized element if asked — the guard
        // must prevent that call entirely.
        let resolver = MockWindowIdentifierResolver([(visibleElement, 111), (minimizedElement, 999)])

        let snapshots = WindowEnumerator.assignSnapshots(rawWindows: raw, resolver: resolver)

        let minimizedSnapshot = snapshots.first { $0.windowTitle == "Minimized" }
        #expect(minimizedSnapshot?.windowIdentifier == nil)
        #expect(!resolver.wasConsulted(for: minimizedElement))
        // Sanity: the visible window still resolves normally.
        #expect(snapshots.first { $0.windowTitle == "Visible" }?.windowIdentifier == 111)
    }
}
