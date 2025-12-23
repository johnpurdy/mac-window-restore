import KeyboardShortcuts

final class KeyboardShortcutManager: @unchecked Sendable {

    func setupShortcuts(onRestore: @escaping @Sendable () -> Void, onSave: @escaping @Sendable () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .restoreWindows) {
            onRestore()
        }
        KeyboardShortcuts.onKeyDown(for: .saveWindows) {
            onSave()
        }
    }

    func setDefaultShortcuts() {
        if KeyboardShortcuts.getShortcut(for: .restoreWindows) == nil {
            KeyboardShortcuts.setShortcut(.init(.z, modifiers: [.control, .command]), for: .restoreWindows)
        }
        if KeyboardShortcuts.getShortcut(for: .saveWindows) == nil {
            KeyboardShortcuts.setShortcut(.init(.s, modifiers: [.control, .command]), for: .saveWindows)
        }
    }
}
