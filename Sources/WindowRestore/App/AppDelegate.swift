import AppKit
import ServiceManagement

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var snapshotScheduler: SnapshotScheduler?
    private var displayMonitor: DisplayMonitor?

    private let persistenceService = PersistenceService()
    private let displayInfoProvider = DisplayInfoProvider()
    private let windowEnumerator: WindowEnumerator
    private let windowPositioner = WindowPositioner()

    override public init() {
        self.windowEnumerator = WindowEnumerator(displayInfoProvider: displayInfoProvider)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Set up menu bar
        setupStatusItem()

        // Start the snapshot scheduler (30 seconds)
        startScheduler()

        // Start display monitor
        startDisplayMonitor()
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
            keyEquivalent: "s"
        )
        saveItem.target = self
        menu.addItem(saveItem)

        let restoreItem = NSMenuItem(
            title: "Restore Window Positions",
            action: #selector(restoreNow),
            keyEquivalent: "r"
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

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
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Scheduler & Monitor

    private func startScheduler() {
        snapshotScheduler = SnapshotScheduler(
            interval: 30.0,
            onSave: { [weak self] in
                Task { @MainActor in
                    self?.saveWindowPositions()
                }
            }
        )
        snapshotScheduler?.start()
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
        let windows = windowEnumerator.enumerateWindows()
        let displays = displayInfoProvider.getDisplays()
        let configId = displayInfoProvider.getCurrentConfigurationIdentifier()

        let configuration = DisplayConfiguration(
            identifier: configId,
            displays: displays,
            windows: windows,
            capturedAt: Date()
        )

        do {
            try persistenceService.save(configuration: configuration)
        } catch {
            print("Failed to save window positions: \(error)")
        }
    }

    private func restoreWindowPositions() {
        let coordinator = RestoreCoordinator(
            persistenceService: persistenceService,
            displayInfoProvider: displayInfoProvider,
            windowPositioner: windowPositioner
        )

        let results = coordinator.restoreWindows()

        let successCount = results.filter { $0.success }.count
        let failCount = results.filter { !$0.success }.count

        if failCount > 0 {
            print("Restored \(successCount) windows, failed \(failCount)")
        }
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        // Use the string value directly to avoid Swift 6 concurrency issues with the C global
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
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
        saveWindowPositions()
    }

    @objc private func restoreNow(_ sender: Any?) {
        restoreWindowPositions()
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Window Restore"
        alert.informativeText = "Automatically saves and restores window positions when external monitors are connected or disconnected.\n\nWindow positions are saved every 30 seconds."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}
