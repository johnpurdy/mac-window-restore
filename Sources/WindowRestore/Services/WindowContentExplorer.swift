import Foundation
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "content-explorer")

/// Diagnostic tool to explore what AX exposes about window contents (tabs, etc.)
public final class WindowContentExplorer {
    private var logLines: [String] = []
    private let outputPath: String

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("WindowRestore")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        outputPath = appFolder.appendingPathComponent("content-explorer.log").path
    }

    /// Explore the AX hierarchy of browser windows and log what we find
    public func exploreBrowserWindows() {
        startLog()
        let browserBundleIds = [
            "com.microsoft.edgemac",
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox"
        ]

        for bundleId in browserBundleIds {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
                continue
            }

            let appName = app.localizedName ?? bundleId
            log("=== Exploring \(appName) ===")

            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

            guard result == .success, let windows = windowsRef as? [AXUIElement] else {
                log("  Could not get windows (error: \(result.rawValue))")
                continue
            }

            log("  Found \(windows.count) windows")

            for (windowIndex, window) in windows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? "(no title)"

                log("\n  Window \(windowIndex): \"\(title)\"")

                // Check for AXTabs attribute (Chromium browsers expose tabs this way)
                exploreTabsAttribute(window)

                // Also check available attributes on the window
                exploreAvailableAttributes(window)

                exploreElement(window, depth: 2, maxDepth: 10)
            }
        }
        flushLog()
    }

    /// Check for AXTabs attribute on a window element
    private func exploreTabsAttribute(_ window: AXUIElement) {
        var tabsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXTabs" as CFString, &tabsRef)

        if result == .success, let tabs = tabsRef as? [AXUIElement] {
            log("    AXTabs found: \(tabs.count) tabs")
            for (tabIndex, tab) in tabs.prefix(20).enumerated() {
                var tabTitleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(tab, kAXTitleAttribute as CFString, &tabTitleRef)
                let tabTitle = tabTitleRef as? String ?? "(no title)"

                var tabURLRef: CFTypeRef?
                AXUIElementCopyAttributeValue(tab, "AXURL" as CFString, &tabURLRef)
                let tabURL = (tabURLRef as? URL)?.absoluteString ?? (tabURLRef as? String)

                var tabDescRef: CFTypeRef?
                AXUIElementCopyAttributeValue(tab, kAXDescriptionAttribute as CFString, &tabDescRef)
                let tabDesc = tabDescRef as? String

                var info = "      Tab \(tabIndex): \"\(tabTitle.prefix(60))\""
                if let url = tabURL { info += " url=\"\(url.prefix(60))\"" }
                if let desc = tabDesc { info += " desc=\"\(desc.prefix(40))\"" }
                log(info)
            }
            if tabs.count > 20 {
                log("      ... and \(tabs.count - 20) more tabs")
            }
        } else {
            log("    AXTabs: not available (error: \(result.rawValue))")
        }
    }

    /// List all available attributes on an element
    private func exploreAvailableAttributes(_ element: AXUIElement) {
        var attributeNamesRef: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributeNamesRef)

        if result == .success, let names = attributeNamesRef as? [String] {
            let interesting = names.filter { $0.lowercased().contains("tab") || $0.lowercased().contains("url") || $0.lowercased().contains("document") }
            if !interesting.isEmpty {
                log("    Interesting attributes: \(interesting.joined(separator: ", "))")
            }

            // Read the values of interesting attributes
            for name in interesting {
                var valueRef: CFTypeRef?
                let valueResult = AXUIElementCopyAttributeValue(element, name as CFString, &valueRef)
                if valueResult == .success {
                    if let url = valueRef as? URL {
                        log("      \(name) = \"\(url.absoluteString.prefix(80))\"")
                    } else if let str = valueRef as? String {
                        log("      \(name) = \"\(str.prefix(80))\"")
                    } else if let arr = valueRef as? [Any] {
                        log("      \(name) = array with \(arr.count) items")
                    } else {
                        log("      \(name) = \(type(of: valueRef))")
                    }
                }
            }
        }
    }

    /// Explore VS Code windows
    public func exploreVSCodeWindows() {
        startLog()
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.microsoft.VSCode" }) else {
            log("VS Code not running")
            flushLog()
            return
        }

        log("=== Exploring VS Code ===")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            log("  Could not get windows (error: \(result.rawValue))")
            flushLog()
            return
        }

        log("  Found \(windows.count) windows")

        for (windowIndex, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "(no title)"

            log("\n  Window \(windowIndex): \"\(title)\"")
            exploreElement(window, depth: 2, maxDepth: 6)
        }
        flushLog()
    }

    /// Recursively explore an AX element and its children
    private func exploreElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        let indent = String(repeating: "  ", count: depth)

        // Get role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "?"

        // Get role description
        var roleDescRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescRef)
        let roleDesc = roleDescRef as? String

        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        // Get description
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let desc = descRef as? String

        // Get value (for text fields, etc.)
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String

        // Get identifier if available
        var identifierRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifierRef)
        let identifier = identifierRef as? String

        // Build log line
        var info = "\(indent)\(role)"
        if let roleDesc = roleDesc { info += " (\(roleDesc))" }
        if let title = title, !title.isEmpty { info += " title=\"\(title.prefix(50))\"" }
        if let desc = desc, !desc.isEmpty { info += " desc=\"\(desc.prefix(50))\"" }
        if let value = value, !value.isEmpty { info += " value=\"\(value.prefix(50))\"" }
        if let identifier = identifier { info += " id=\"\(identifier)\"" }

        // Only log interesting elements (tabs, groups, toolbars, etc.)
        let interestingRoles = ["AXTabGroup", "AXTab", "AXRadioButton", "AXToolbar", "AXGroup", "AXList", "AXOutline", "AXRow", "AXStaticText", "AXButton"]
        let isInteresting = interestingRoles.contains(role) || title != nil || role.contains("Tab") || identifier != nil

        // Log if interesting or shallow depth, but be more verbose about potential tab elements
        if isInteresting || depth <= 4 {
            log(info)
        }

        // Don't go too deep
        if depth >= maxDepth {
            return
        }

        // Get children
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)

        if let children = childrenRef as? [AXUIElement] {
            // For large child counts, only explore first few
            let maxChildren = (depth < 4) ? 20 : 5
            for child in children.prefix(maxChildren) {
                exploreElement(child, depth: depth + 1, maxDepth: maxDepth)
            }
            if children.count > maxChildren {
                log("\(indent)  ... and \(children.count - maxChildren) more children")
            }
        }
    }

    private func log(_ message: String) {
        logger.info("\(message)")
        logLines.append(message)
    }

    private func startLog() {
        logLines = []
        logLines.append("=== Content Explorer - \(Date()) ===\n")
    }

    private func flushLog() {
        let content = logLines.joined(separator: "\n")
        try? content.write(toFile: outputPath, atomically: true, encoding: .utf8)
        logger.info("Content explorer output written to: \(self.outputPath)")
    }
}
