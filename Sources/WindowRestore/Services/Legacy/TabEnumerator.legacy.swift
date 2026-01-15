import Foundation
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "tab-enumerator")

/// Extracts tab information from browser windows via Accessibility API
public final class TabEnumerator {

    /// Browser bundle identifiers that support tab enumeration
    public static let supportedBrowsers: Set<String> = [
        "com.microsoft.edgemac",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium"
    ]

    /// Apps that typically have one main window with dynamic titles (chat apps, etc.)
    /// These should be matched by bundle ID when there's only one window
    public static let singleWindowApps: Set<String> = [
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.MobileSMS",
        "com.facebook.archon",          // Messenger
        "com.tinyspeck.slackmacgap",    // Slack
        "com.hnc.Discord",              // Discord
        "com.skype.skype",
        "com.whatsapp.WhatsApp",
        "com.telegram.desktop",
        "us.zoom.xos"
    ]

    /// Check if an app supports tab enumeration
    public static func supportsTabEnumeration(bundleIdentifier: String) -> Bool {
        supportedBrowsers.contains(bundleIdentifier)
    }

    /// Check if an app should use single-window matching (match by bundle ID when only one window)
    public static func usesSingleWindowMatching(bundleIdentifier: String) -> Bool {
        singleWindowApps.contains(bundleIdentifier)
    }

    /// Extract tab titles from a browser window
    /// Returns nil if tabs cannot be extracted
    public func extractTabs(from window: AXUIElement) -> [String]? {
        // Get window title for logging
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let windowTitle = (titleRef as? String) ?? "(unknown)"

        debugLog("extractTabs called for window: \(windowTitle)")

        // Find the AXTabGroup element
        guard let tabGroup = findTabGroup(in: window, depth: 0) else {
            debugLog("No AXTabGroup found for window: \(windowTitle)")
            return nil
        }

        debugLog("Found AXTabGroup for window: \(windowTitle)")

        // Find all tab elements (AXRadioButton with role description "tab")
        let tabs = findTabElements(in: tabGroup)

        debugLog("Found \(tabs.count) tab elements for window: \(windowTitle)")

        guard !tabs.isEmpty else {
            debugLog("AXTabGroup found but no tabs for window: \(windowTitle)")
            return nil
        }

        // Extract tab titles from description attribute
        var tabTitles: [String] = []
        for tab in tabs {
            var descriptionReference: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(tab, kAXDescriptionAttribute as CFString, &descriptionReference)
            if result == .success, let description = descriptionReference as? String, !description.isEmpty {
                tabTitles.append(description)
            }
        }

        debugLog("Extracted \(tabTitles.count) tab titles for window: \(windowTitle)")
        return tabTitles.isEmpty ? nil : tabTitles
    }

    private func debugLog(_ message: String) {
        let logPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowRestore/tab-debug.log")
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }

    /// Find the AXTabGroup element within a window
    private func findTabGroup(in element: AXUIElement, depth: Int) -> AXUIElement? {
        // Limit depth to avoid infinite recursion
        if depth > 15 {
            return nil
        }

        // Check if this element is a tab group
        var roleReference: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleReference)
        let role = roleReference as? String ?? "?"

        if role == "AXTabGroup" {
            debugLog("Found AXTabGroup at depth \(depth)")
            return element
        }

        // Search children
        var childrenReference: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenReference)
        guard result == .success, let children = childrenReference as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let tabGroup = findTabGroup(in: child, depth: depth + 1) {
                return tabGroup
            }
        }

        return nil
    }

    /// Find all AXRadioButton elements with role description "tab"
    private func findTabElements(in element: AXUIElement) -> [AXUIElement] {
        var tabs: [AXUIElement] = []
        collectTabElements(from: element, into: &tabs)
        return tabs
    }

    private func collectTabElements(from element: AXUIElement, into tabs: inout [AXUIElement]) {
        // Check if this element is a tab
        var roleReference: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleReference)

        var roleDescriptionReference: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescriptionReference)

        if let role = roleReference as? String,
           let roleDescription = roleDescriptionReference as? String,
           role == "AXRadioButton" && roleDescription == "tab" {
            tabs.append(element)
        }

        // Search children
        var childrenReference: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenReference)
        guard result == .success, let children = childrenReference as? [AXUIElement] else {
            return
        }

        for child in children {
            collectTabElements(from: child, into: &tabs)
        }
    }
}
