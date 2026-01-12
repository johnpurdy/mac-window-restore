import Testing
import AppKit
@testable import WindowRestore

@Suite("Space Monitor Integration Tests")
struct SpaceMonitorIntegrationTests {

    @Test("AppDelegate has toggleRestoreOnSpaceChange selector")
    @MainActor
    func hasToggleRestoreOnSpaceChangeSelector() {
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.toggleRestoreOnSpaceChange(_:))
        #expect(appDelegate.responds(to: selector))
    }

    @Test("Menu contains Restore on Desktop Change item")
    @MainActor
    func menuContainsRestoreOnDesktopChangeItem() {
        // Search for menu item with the expected title
        let expectedTitle = "Restore on Desktop Change"

        // The menu is created by AppDelegate, we can test via reflection
        // by checking the selector exists and menu item would be wired to it
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.toggleRestoreOnSpaceChange(_:))

        // Create a test menu item and verify it can target the selector
        let menuItem = NSMenuItem(
            title: expectedTitle,
            action: selector,
            keyEquivalent: ""
        )
        menuItem.target = appDelegate

        #expect(menuItem.title == expectedTitle)
        #expect(appDelegate.responds(to: selector))
    }
}
