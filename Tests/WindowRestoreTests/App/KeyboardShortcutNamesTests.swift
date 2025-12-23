import Testing
import KeyboardShortcuts
@testable import WindowRestore

@Suite("KeyboardShortcutNames Tests")
struct KeyboardShortcutNamesTests {

    @Test("restoreWindows shortcut name is defined")
    func restoreWindowsNameExists() {
        let name = KeyboardShortcuts.Name.restoreWindows
        #expect(name.rawValue == "restoreWindows")
    }

    @Test("saveWindows shortcut name is defined")
    func saveWindowsNameExists() {
        let name = KeyboardShortcuts.Name.saveWindows
        #expect(name.rawValue == "saveWindows")
    }
}
