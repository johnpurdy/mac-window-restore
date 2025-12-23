import Testing
import AppKit
@testable import WindowRestore

@Suite("Clear All Tests")
struct ClearAllTests {

    @MainActor
    @Test("AppDelegate has clearAllWindowPositions selector")
    func hasClearAllSelector() {
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.clearAllWindowPositions(_:))
        #expect(appDelegate.responds(to: selector))
    }
}
