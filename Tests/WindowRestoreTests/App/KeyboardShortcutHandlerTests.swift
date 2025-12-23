import Testing
import KeyboardShortcuts
@testable import WindowRestore

@Suite("KeyboardShortcut Handler Tests")
struct KeyboardShortcutHandlerTests {

    @Test("KeyboardShortcutManager can setup shortcuts")
    func keyboardShortcutManagerCanSetupShortcuts() {
        let manager = KeyboardShortcutManager()

        // Should not throw when setting up
        manager.setupShortcuts(
            onRestore: {},
            onSave: {}
        )
    }
}
