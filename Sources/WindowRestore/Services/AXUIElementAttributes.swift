import CoreGraphics
@preconcurrency import ApplicationServices

/// Small typed accessors over the Accessibility attribute API, shared by the window
/// providers so the CoreFoundation boilerplate is written once.
extension AXUIElement {
    func stringAttribute(_ attribute: String) -> String? {
        var reference: CFTypeRef?
        AXUIElementCopyAttributeValue(self, attribute as CFString, &reference)
        return reference as? String
    }

    func boolAttribute(_ attribute: String) -> Bool {
        var reference: CFTypeRef?
        AXUIElementCopyAttributeValue(self, attribute as CFString, &reference)
        return (reference as? Bool) ?? false
    }

    /// The window frame assembled from the AX position and size attributes.
    func windowFrame() -> CGRect {
        var position = CGPoint.zero
        var positionReference: CFTypeRef?
        AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &positionReference)
        if let positionValue = positionReference, CFGetTypeID(positionValue) == AXValueGetTypeID() {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }

        var size = CGSize.zero
        var sizeReference: CFTypeRef?
        AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &sizeReference)
        if let sizeValue = sizeReference, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: position, size: size)
    }
}
