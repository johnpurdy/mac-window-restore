import AppKit
import KeyboardShortcuts
import ServiceManagement
import os

// Check for --dev flag
let devMode = CommandLine.arguments.contains("--dev")

// Unified logging using os_log (viewable in Console.app)
enum AppLogger {
    static let subsystem = "com.windowrestore.app"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let save = Logger(subsystem: subsystem, category: "save")
    static let restore = Logger(subsystem: subsystem, category: "restore")
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")

    static func log(_ message: String, category: Logger = general, level: OSLogType = .info) {
        category.log(level: level, "\(message)")

        // Also print to stdout in dev mode for convenience
        if devMode {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("[\(timestamp)] \(message)")
        }
    }
}

private func log(_ message: String) {
    AppLogger.log(message)
}

// UserDefaults key for save interval
private let saveIntervalKey = "SaveIntervalSeconds"
private let defaultSaveInterval: TimeInterval = 30.0

// Available save intervals (in seconds)
private let saveIntervalOptions: [(label: String, seconds: TimeInterval)] = [
    ("15 seconds", 15),
    ("30 seconds", 30),
    ("1 minute", 60),
    ("2 minutes", 120),
    ("5 minutes", 300),
]

// UserDefaults key for stale window threshold
private let staleThresholdKey = "StaleWindowThresholdDays"
private let defaultStaleThresholdDays: Int = 7

// UserDefaults keys for auto-restore on monitor change
private let restoreOnConnectKey = "RestoreOnConnectEnabled"
private let restoreOnDisconnectKey = "RestoreOnDisconnectEnabled"

// Available stale window thresholds (in days)
private let staleThresholdOptions: [(label: String, days: Int)] = [
    ("1 day", 1),
    ("3 days", 3),
    ("7 days", 7),
    ("14 days", 14),
    ("30 days", 30),
]

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var snapshotScheduler: SnapshotScheduler?
    private var displayMonitor: DisplayMonitor?
    private let keyboardShortcutManager = KeyboardShortcutManager()
    private let shortcutsSettingsWindow = ShortcutsSettingsWindow()

    private let persistenceService = PersistenceService()
    private let displayInfoProvider = DisplayInfoProvider()
    private let windowEnumerator: WindowEnumerator
    private let windowPositioner = WindowPositioner()

    private var isSavingPaused: Bool = false

    private var currentSaveInterval: TimeInterval {
        get {
            let saved = UserDefaults.standard.double(forKey: saveIntervalKey)
            return saved > 0 ? saved : defaultSaveInterval
        }
        set {
            UserDefaults.standard.set(newValue, forKey: saveIntervalKey)
        }
    }

    private var currentStaleThresholdDays: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: staleThresholdKey)
            return saved > 0 ? saved : defaultStaleThresholdDays
        }
        set {
            UserDefaults.standard.set(newValue, forKey: staleThresholdKey)
        }
    }

    private var currentStaleThreshold: TimeInterval {
        TimeInterval(currentStaleThresholdDays) * 24 * 3600
    }

    private var isRestoreOnConnectEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: restoreOnConnectKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: restoreOnConnectKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: restoreOnConnectKey)
        }
    }

    private var isRestoreOnDisconnectEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: restoreOnDisconnectKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: restoreOnDisconnectKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: restoreOnDisconnectKey)
        }
    }

    override public init() {
        self.windowEnumerator = WindowEnumerator(displayInfoProvider: displayInfoProvider)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log("Window Restore starting...")

        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Set up keyboard shortcuts (before menu so shortcuts appear in menu)
        setupKeyboardShortcuts()

        // Set up menu bar
        setupStatusItem()
        log("Menu bar setup complete")

        // Start the snapshot scheduler
        startScheduler()
        log("Scheduler started (\(Int(currentSaveInterval)) second interval)")

        // Start display monitor
        startDisplayMonitor()
        log("Display monitor started")

        log("Window Restore ready")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        snapshotScheduler?.stop()
        displayMonitor?.stop()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = createStatusIcon()
            button.image?.isTemplate = true
        }

        statusItem?.menu = createMenu()
    }

    private func setupKeyboardShortcuts() {
        // Set defaults first (only applies if user hasn't configured custom shortcuts)
        keyboardShortcutManager.setDefaultShortcuts()

        keyboardShortcutManager.setupShortcuts(
            onRestore: { [weak self] in
                log("Keyboard shortcut triggered: restore")
                Task { @MainActor in
                    self?.restoreWindowPositions()
                }
            },
            onSave: { [weak self] in
                log("Keyboard shortcut triggered: save")
                Task { @MainActor in
                    self?.saveWindowPositions()
                }
            }
        )
        log("Keyboard shortcuts registered")
    }

    private func createStatusIcon() -> NSImage {
        // Use SF Symbol for a clear, system-standard icon
        if let image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Restore") {
            return image
        }
        // Fallback to a different symbol if the first isn't available
        if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Window Restore") {
            return image
        }
        // Last resort fallback
        return NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Window Restore") ?? NSImage()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Window Restore", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let saveShortcutLabel = shortcutLabel(for: .saveWindows)
        let saveItem = NSMenuItem(
            title: "Save Window Positions Now\(saveShortcutLabel)",
            action: #selector(saveNow),
            keyEquivalent: ""
        )
        saveItem.target = self
        menu.addItem(saveItem)

        let pauseSavingItem = NSMenuItem(
            title: "Pause Saving",
            action: #selector(togglePauseSaving),
            keyEquivalent: ""
        )
        pauseSavingItem.target = self
        pauseSavingItem.state = isSavingPaused ? .on : .off
        menu.addItem(pauseSavingItem)

        menu.addItem(NSMenuItem.separator())

        let restoreShortcutLabel = shortcutLabel(for: .restoreWindows)
        let restoreItem = NSMenuItem(
            title: "Restore Window Positions\(restoreShortcutLabel)",
            action: #selector(restoreNow),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        let autoRestoreItem = NSMenuItem(title: "Auto-restore on Monitor Change", action: nil, keyEquivalent: "")
        let autoRestoreSubmenu = NSMenu()

        let onConnectItem = NSMenuItem(
            title: "On Connect",
            action: #selector(toggleRestoreOnConnect),
            keyEquivalent: ""
        )
        onConnectItem.target = self
        onConnectItem.state = isRestoreOnConnectEnabled ? .on : .off
        autoRestoreSubmenu.addItem(onConnectItem)

        let onDisconnectItem = NSMenuItem(
            title: "On Disconnect",
            action: #selector(toggleRestoreOnDisconnect),
            keyEquivalent: ""
        )
        onDisconnectItem.target = self
        onDisconnectItem.state = isRestoreOnDisconnectEnabled ? .on : .off
        autoRestoreSubmenu.addItem(onDisconnectItem)

        autoRestoreItem.submenu = autoRestoreSubmenu
        menu.addItem(autoRestoreItem)

        menu.addItem(NSMenuItem.separator())

        // Keyboard shortcuts settings
        let shortcutsItem = NSMenuItem(
            title: "Keyboard Shortcuts…",
            action: #selector(showKeyboardShortcuts),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        // Save frequency submenu
        let saveFrequencyItem = NSMenuItem(title: "Save Frequency", action: nil, keyEquivalent: "")
        let saveFrequencySubmenu = NSMenu()
        for option in saveIntervalOptions {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(changeSaveInterval),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(option.seconds)
            item.state = (currentSaveInterval == option.seconds) ? .on : .off
            saveFrequencySubmenu.addItem(item)
        }
        saveFrequencyItem.submenu = saveFrequencySubmenu
        menu.addItem(saveFrequencyItem)

        // Keep windows for submenu (stale window threshold)
        let keepWindowsItem = NSMenuItem(title: "Keep Windows For", action: nil, keyEquivalent: "")
        let keepWindowsSubmenu = NSMenu()
        for option in staleThresholdOptions {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(changeStaleThreshold),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.days
            item.state = (currentStaleThresholdDays == option.days) ? .on : .off
            keepWindowsSubmenu.addItem(item)
        }
        keepWindowsItem.submenu = keepWindowsSubmenu
        menu.addItem(keepWindowsItem)

        menu.addItem(NSMenuItem.separator())

        let clearAllItem = NSMenuItem(
            title: "Clear All Window Positions…",
            action: #selector(clearAllWindowPositions),
            keyEquivalent: ""
        )
        clearAllItem.target = self
        menu.addItem(clearAllItem)

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let howItWorksItem = NSMenuItem(
            title: "How It Works…",
            action: #selector(showHowItWorks),
            keyEquivalent: ""
        )
        howItWorksItem.target = self
        menu.addItem(howItWorksItem)

        let aboutItem = NSMenuItem(
            title: "About Window Restore",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Scheduler & Monitor

    private func startScheduler() {
        snapshotScheduler?.stop()
        snapshotScheduler = SnapshotScheduler(
            interval: currentSaveInterval,
            onSave: { [weak self] in
                Task { @MainActor in
                    self?.saveWindowPositions()
                }
            }
        )
        snapshotScheduler?.start()
    }

    private func restartSchedulerWithInterval(_ interval: TimeInterval) {
        currentSaveInterval = interval
        startScheduler()
        // Rebuild the menu to update checkmarks
        statusItem?.menu = createMenu()
        log("Save interval changed to \(Int(interval)) seconds")
    }

    private func startDisplayMonitor() {
        displayMonitor = DisplayMonitor(
            onDisplayChange: { [weak self] oldCount, newCount in
                Task { @MainActor in
                    guard let self = self else { return }

                    // Restore on monitor connect
                    if newCount > oldCount && self.isRestoreOnConnectEnabled {
                        try? await Task.sleep(for: .seconds(1))
                        self.restoreWindowPositions()
                    }

                    // Restore on monitor disconnect
                    if newCount < oldCount && self.isRestoreOnDisconnectEnabled {
                        try? await Task.sleep(for: .seconds(1))
                        self.restoreWindowPositions()
                    }
                }
            }
        )
        displayMonitor?.start()
    }

    // MARK: - Save & Restore

    private func saveWindowPositions() {
        log("Starting save...")
        let currentWindows = windowEnumerator.enumerateWindows()
        log("Enumerated \(currentWindows.count) windows")

        let displays = displayInfoProvider.getDisplays()
        let configId = displayInfoProvider.getCurrentConfigurationIdentifier()
        log("Config ID: \(configId)")

        // Merge with existing saved windows (preserves windows from other desktops)
        let mergedWindows = mergeWindows(
            currentWindows: currentWindows,
            configId: configId
        )
        log("Merged to \(mergedWindows.count) total windows")

        let configuration = DisplayConfiguration(
            identifier: configId,
            displays: displays,
            windows: mergedWindows,
            capturedAt: Date()
        )

        do {
            try persistenceService.save(configuration: configuration)
            log("Save successful")
        } catch {
            log("Failed to save: \(error.localizedDescription)")
        }
    }

    private func mergeWindows(currentWindows: [WindowSnapshot], configId: String) -> [WindowSnapshot] {
        // Load existing saved windows
        guard let existingConfig = try? persistenceService.load(identifier: configId) else {
            // No existing config, just use current windows
            return currentWindows
        }

        return WindowMerger.merge(
            currentWindows: currentWindows,
            existingWindows: existingConfig.windows,
            staleThreshold: currentStaleThreshold
        )
    }

    private func restoreWindowPositions() {
        log("Starting restore...")

        let coordinator = RestoreCoordinator(
            persistenceService: persistenceService,
            displayInfoProvider: displayInfoProvider,
            windowPositioner: windowPositioner
        )

        let results = coordinator.restoreWindows()

        let successCount = results.filter { $0.success }.count
        let failCount = results.filter { !$0.success }.count

        log("Restore complete: \(successCount) succeeded, \(failCount) failed")

        for result in results where !result.success {
            log("Failed to restore \(result.snapshot.applicationName): \(result.error ?? "unknown")")
        }
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        // First check without prompting
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Only prompt if not already trusted
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            print("Accessibility permissions not granted. Window positioning will not work.")
        }
    }

    // MARK: - Launch at Login

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    sender.state = .off
                } else {
                    try SMAppService.mainApp.register()
                    sender.state = .on
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func saveNow(_ sender: Any?) {
        log("Save menu item clicked")
        saveWindowPositions()
    }

    @objc private func restoreNow(_ sender: Any?) {
        log("Restore menu item clicked")
        restoreWindowPositions()
    }

    @objc private func changeSaveInterval(_ sender: NSMenuItem) {
        let newInterval = TimeInterval(sender.tag)
        restartSchedulerWithInterval(newInterval)
    }

    @objc private func changeStaleThreshold(_ sender: NSMenuItem) {
        currentStaleThresholdDays = sender.tag
        // Rebuild the menu to update checkmarks
        statusItem?.menu = createMenu()
        log("Stale threshold changed to \(sender.tag) days")
    }

    @objc func togglePauseSaving(_ sender: NSMenuItem) {
        isSavingPaused.toggle()
        if isSavingPaused {
            snapshotScheduler?.stop()
            sender.state = .on
            log("Saving paused")
        } else {
            snapshotScheduler?.start()
            sender.state = .off
            log("Saving resumed")
        }
    }

    @objc func toggleRestoreOnConnect(_ sender: NSMenuItem) {
        isRestoreOnConnectEnabled.toggle()
        sender.state = isRestoreOnConnectEnabled ? .on : .off
        log("Restore on monitor connect: \(isRestoreOnConnectEnabled ? "enabled" : "disabled")")
    }

    @objc func toggleRestoreOnDisconnect(_ sender: NSMenuItem) {
        isRestoreOnDisconnectEnabled.toggle()
        sender.state = isRestoreOnDisconnectEnabled ? .on : .off
        log("Restore on monitor disconnect: \(isRestoreOnDisconnectEnabled ? "enabled" : "disabled")")
    }

    @objc func clearAllWindowPositions(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear All Window Positions?"
        alert.informativeText = "This will delete all saved window positions for all monitor configurations. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try persistenceService.deleteAllConfigurations()
                log("All window positions cleared")
            } catch {
                log("Failed to clear window positions: \(error.localizedDescription)")
            }
        }
    }

    @objc private func showHowItWorks(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "How Window Restore Works"
        alert.informativeText = """
        Saving:
        • Window positions are automatically saved at your chosen interval
        • Use "Pause Saving" to temporarily stop auto-saving
        • Each save captures windows visible on the current desktop
        • Windows from other desktops are preserved from previous saves
        • Windows are identified by app + window title

        Restoring:
        • Use the keyboard shortcut or menu to restore
        • Only moves windows visible on your current desktop
        • Each window is matched to its saved position by title
        • Switch to another desktop and restore again to fix those windows
        • Customize shortcuts via Keyboard Shortcuts… in the menu

        Multiple Desktops:
        • The app remembers windows across all your desktops
        • Visit each desktop periodically so windows get saved
        • Restore works per-desktop — switch desktops and restore as needed

        Monitor Changes:
        • Restore triggers automatically when monitors connect or disconnect
        • Toggle each via "Auto-restore on Monitor Change" submenu
        • Different monitor configurations are saved separately

        Cleanup:
        • Windows not seen within the "Keep Windows For" period are removed
        • This prevents the saved data from growing indefinitely
        • Adjust the threshold via the menu (default: 7 days)
        • Use "Clear All Window Positions…" to start fresh
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func showAbout(_ sender: Any?) {
        let intervalLabel = saveIntervalOptions.first { $0.seconds == currentSaveInterval }?.label ?? "\(Int(currentSaveInterval)) seconds"
        let alert = NSAlert()
        alert.messageText = "Window Restore"
        alert.informativeText = "Automatically saves and restores window positions when external monitors are connected or disconnected.\n\nWindow positions are saved every \(intervalLabel)."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        shortcutsSettingsWindow.show()
    }

    private func shortcutLabel(for name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return ""
        }
        return " (\(shortcut.description))"
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}
