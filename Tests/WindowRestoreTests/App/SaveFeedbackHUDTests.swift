import Testing
import AppKit
@testable import WindowRestore

@Suite("SaveFeedbackHUD Tests")
struct SaveFeedbackHUDTests {

    @Test("SaveFeedbackHUD can be instantiated")
    @MainActor
    func canBeInstantiated() {
        let hud = SaveFeedbackHUD()
        #expect(hud != nil)
    }

    @Test("SaveFeedbackHUD has show method")
    @MainActor
    func hasShowMethod() {
        let hud = SaveFeedbackHUD()
        // Should compile and not crash
        hud.show()
    }

    @Test("SaveFeedbackHUD displays correct message")
    @MainActor
    func displaysCorrectMessage() {
        let hud = SaveFeedbackHUD()
        #expect(hud.message == "Window Positions Saved")
    }
}
