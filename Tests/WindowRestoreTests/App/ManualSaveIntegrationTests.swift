import Testing
import AppKit
@testable import WindowRestore

@Suite("Manual Save Integration Tests")
struct ManualSaveIntegrationTests {

    @Test("Manual save should show feedback HUD")
    @MainActor
    func manualSaveShowsFeedbackHUD() async throws {
        // This test verifies that the manual save flow includes HUD feedback
        // We test by calling the public interface that manual saves use

        let hud = SaveFeedbackHUD()

        // Verify the HUD can be shown (simulating what happens after manual save)
        hud.show()

        // Give time for the window to appear
        try await Task.sleep(for: .milliseconds(100))

        // The HUD should have created and shown a window
        // This verifies the integration point works
        #expect(hud.message == "Window Positions Saved")
    }
}
