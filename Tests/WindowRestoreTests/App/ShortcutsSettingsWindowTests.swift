import Testing
@testable import WindowRestore

@Suite("ShortcutsSettingsWindow Tests")
struct ShortcutsSettingsWindowTests {

    @Test("ShortcutsSettingsWindow can be instantiated")
    func canBeInstantiated() {
        let window = ShortcutsSettingsWindow()
        #expect(window != nil)
    }

    @Test("ShortcutsSettingsWindow has show method")
    func hasShowMethod() {
        let window = ShortcutsSettingsWindow()
        // Verify the method exists (compilation test)
        _ = window.show
    }
}
