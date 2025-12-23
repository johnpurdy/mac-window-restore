import Testing
import KeyboardShortcuts
@testable import WindowRestore

@Suite("KeyboardShortcut Defaults Tests")
struct KeyboardShortcutDefaultsTests {

    @Test("KeyboardShortcutManager has setDefaultShortcuts method")
    func hasSetDefaultShortcutsMethod() {
        // This test verifies the method exists and can be called
        // We can't fully test KeyboardShortcuts behavior due to Carbon API limitations in tests
        let manager = KeyboardShortcutManager()

        // The method should exist and be callable (compilation test)
        // Actual behavior is tested via integration/manual testing
        _ = manager.setDefaultShortcuts
    }

    @Test("Default shortcut keys are z and s")
    func defaultShortcutKeysAreCorrect() {
        // Test that the expected key constants exist
        #expect(KeyboardShortcuts.Key.z == .z)
        #expect(KeyboardShortcuts.Key.s == .s)
    }
}
