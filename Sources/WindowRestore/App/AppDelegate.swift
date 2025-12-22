import AppKit
import ServiceManagement

// Check for --dev flag
let devMode = CommandLine.arguments.contains("--dev")

// Simple file logger (only active in dev mode)
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()
    private let logURL: URL?
    private let lock = NSLock()

    private init() {
        guard devMode else {
            logURL = nil
            return
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("WindowRestore")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logURL = logDir.appendingPathComponent("app.log")

        // Clear old log on startup
        if let url = logURL {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func log(_ message: String) {
        guard devMode, let logURL = logURL else { return }

        lock.lock()
        defer { lock.unlock() }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(line, terminator: "")

        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: logURL, atomically: false, encoding: .utf8)
        }
    }
}

private func log(_ message: String) {
    FileLogger.shared.log(message)
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
    private var globalHotkeyMonitor: Any?

    private let persistenceService = PersistenceService()
    private let displayInfoProvider = DisplayInfoProvider()
    private let windowEnumerator: WindowEnumerator
    private let windowPositioner = WindowPositioner()

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

    override public init() {
        self.windowEnumerator = WindowEnumerator(displayInfoProvider: displayInfoProvider)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log("Window Restore starting...")

        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Set up menu bar
        setupStatusItem()
        log("Menu bar setup complete")

        // Set up global hotkey (Ctrl+Cmd+Z for restore)
        setupGlobalHotkey()

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
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
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

    private func setupGlobalHotkey() {
        // Listen for Ctrl+Cmd+Z globally
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Ctrl+Cmd+Z
            let requiredFlags: NSEvent.ModifierFlags = [.control, .command]
            let pressedFlags = event.modifierFlags.intersection([.control, .command, .option, .shift])

            if pressedFlags == requiredFlags && event.keyCode == 6 { // keyCode 6 = 'z'
                log("Global hotkey triggered (Ctrl+Cmd+z)")
                Task { @MainActor in
                    self?.restoreWindowPositions()
                }
            }
        }
        log("Global hotkey registered")
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

        let saveItem = NSMenuItem(
            title: "Save Window Positions Now",
            action: #selector(saveNow),
            keyEquivalent: ""
        )
        saveItem.target = self
        menu.addItem(saveItem)

        let restoreItem = NSMenuItem(
            title: "Restore Window Positions (⌃⌘z)",
            action: #selector(restoreNow),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(NSMenuItem.separator())

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

                    // If monitors were added (newCount > oldCount), restore windows
                    if newCount > oldCount {
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

    @objc private func showHowItWorks(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "How Window Restore Works"
        alert.informativeText = """
        Saving:
        • Window positions are automatically saved at your chosen interval
        • Each save captures windows visible on the current desktop
        • Windows from other desktops are preserved from previous saves
        • Windows are identified by app + window title

        Restoring (⌃⌘z):
        • Only moves windows visible on your current desktop
        • Each window is matched to its saved position by title
        • Switch to another desktop and restore again to fix those windows

        Multiple Desktops:
        • The app remembers windows across all your desktops
        • Visit each desktop periodically so windows get saved
        • Restore works per-desktop — switch desktops and restore as needed

        Monitor Changes:
        • When you reconnect external monitors, restore triggers automatically
        • Different monitor configurations are saved separately

        Cleanup:
        • Windows not seen within the "Keep Windows For" period are removed
        • This prevents the saved data from growing indefinitely
        • Adjust the threshold via the menu (default: 7 days)
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

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}
