import Foundation
import ApplicationServices

/// Extracts tab information from browser windows via Accessibility API
public final class TabEnumerator {

    public init() {}

    /// Check if an app supports tab enumeration (uses default config)
    public static func supportsTabEnumeration(bundleIdentifier: String) -> Bool {
        let config = AppMatchingConfig.loadOrDefault()
        return config.isTabEnabledApp(bundleIdentifier)
    }

    /// Extract tab titles from a browser window
    /// Returns nil if tabs cannot be extracted
    public func extractTabs(from window: AXUIElement) -> [String]? {
        // Find the AXTabGroup element
        guard let tabGroup = findTabGroup(in: window, depth: 0) else {
            return nil
        }

        // Find all tab elements (AXRadioButton with role description "tab")
        let tabs = findTabElements(in: tabGroup)

        guard !tabs.isEmpty else {
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

        return tabTitles.isEmpty ? nil : tabTitles
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
