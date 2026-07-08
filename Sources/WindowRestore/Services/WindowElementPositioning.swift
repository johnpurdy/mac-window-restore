import Foundation
import CoreGraphics
@preconcurrency import ApplicationServices

/// Outcome of positioning a window element, preserving the separate AX error codes so
/// diagnostics survive the seam (rather than collapsing to a bare Bool).
public struct ElementPositionResult: Sendable {
    public let positioned: Bool
    public let positionError: AXError?
    public let sizeError: AXError?

    public init(positioned: Bool, positionError: AXError?, sizeError: AXError?) {
        self.positioned = positioned
        self.positionError = positionError
        self.sizeError = sizeError
    }
}

/// The Accessibility side effects of a restore, injected so tests can spy on which
/// element is actually moved without live windows.
public protocol WindowElementPositioning {
    func position(_ element: AXUIElement, to frame: CGRect) -> ElementPositionResult
    /// Sets minimized state and returns whether the element's state is now verified to
    /// match `minimized`.
    func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool
}

/// Production implementation wrapping the AX attribute calls.
public struct AXWindowElementPositioner: WindowElementPositioning {
    public init() {}

    public func position(_ element: AXUIElement, to frame: CGRect) -> ElementPositionResult {
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var positionResult: AXError = .failure
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        }

        var size = CGSize(width: frame.width, height: frame.height)
        var sizeResult: AXError = .failure
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }

        let positioned = positionResult == .success && sizeResult == .success
        return ElementPositionResult(
            positioned: positioned,
            positionError: positionResult == .success ? nil : positionResult,
            sizeError: sizeResult == .success ? nil : sizeResult
        )
    }

    public func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool {
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        let currentMinimized = (minimizedRef as? Bool) ?? false

        if currentMinimized == minimized {
            return true
        }

        let targetValue: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, targetValue)

        minimizedRef = nil
        AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        let newMinimized = (minimizedRef as? Bool) ?? false
        return newMinimized == minimized
    }
}
