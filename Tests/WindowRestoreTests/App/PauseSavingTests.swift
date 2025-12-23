import Testing
import AppKit
@testable import WindowRestore

@Suite("Pause Saving Tests")
struct PauseSavingTests {

    @MainActor
    @Test("AppDelegate has togglePauseSaving selector")
    func hasTogglePauseSavingSelector() {
        let appDelegate = AppDelegate()
        let selector = #selector(AppDelegate.togglePauseSaving(_:))
        #expect(appDelegate.responds(to: selector))
    }
}
