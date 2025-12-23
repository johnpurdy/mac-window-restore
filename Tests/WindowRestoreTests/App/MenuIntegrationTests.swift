import Testing
import AppKit
@testable import WindowRestore

@Suite("Menu Integration Tests")
struct MenuIntegrationTests {

    @Test("AppDelegate has showKeyboardShortcuts selector")
    @MainActor
    func hasShowKeyboardShortcutsSelector() {
        let delegate = AppDelegate()

        // Verify the selector exists (will crash if method doesn't exist)
        let selector = #selector(AppDelegate.showKeyboardShortcuts(_:))
        #expect(delegate.responds(to: selector))
    }
}
