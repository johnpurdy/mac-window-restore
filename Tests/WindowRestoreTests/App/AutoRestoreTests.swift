import Testing
import AppKit
@testable import WindowRestore

@Suite("Auto-Restore Tests")
struct AutoRestoreTests {

    @MainActor
    @Test("AppDelegate has toggleRestoreOnConnect selector")
    func hasToggleRestoreOnConnectSelector() {
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.toggleRestoreOnConnect(_:))
        #expect(appDelegate.responds(to: selector))
    }

    @MainActor
    @Test("AppDelegate has toggleRestoreOnDisconnect selector")
    func hasToggleRestoreOnDisconnectSelector() {
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.toggleRestoreOnDisconnect(_:))
        #expect(appDelegate.responds(to: selector))
    }
}
