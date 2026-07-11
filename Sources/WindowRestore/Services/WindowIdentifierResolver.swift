import Foundation
import CoreGraphics
import ApplicationServices
import CAXWindowID
import os

private let logger = Logger(subsystem: "com.windowrestore.app", category: "windowIdentifier")

/// Resolves the exact `CGWindowID` for an accessibility window element.
///
/// This replaces the old frame-based correlation (matching an `AXUIElement` to a
/// `CGWindowListCopyWindowInfo` entry by frame within a tolerance), which mis-assigned
/// ids when two windows shared a frame. Identity is now read directly per window, so two
/// stacked windows can never receive each other's id.
protocol WindowIdentifierResolving: Sendable {
    /// The window's `CGWindowID`, or `nil` if it cannot be resolved.
    func windowIdentifier(for element: AXUIElement) -> Int?
}

/// Reads the exact `CGWindowID` via the private `_AXUIElementGetWindow` function
/// (through the `CAXWindowID` C bridge). Fail-closed: any non-`.success` result
/// yields `nil` rather than a fabricated id.
struct ExactWindowIdentifierResolver: WindowIdentifierResolving {
    /// Injected boundary to the private API. Production uses the C bridge; tests
    /// substitute a closure so the mapping logic is verifiable without the OS.
    private let backend: @Sendable (AXUIElement) -> (AXError, CGWindowID)

    init() {
        self.backend = { element in
            var windowIdentifier = CGWindowID(0)
            let error = CAXWindowIDGet(element, &windowIdentifier)
            return (error, windowIdentifier)
        }
    }

    init(backend: @escaping @Sendable (AXUIElement) -> (AXError, CGWindowID)) {
        self.backend = backend
    }

    func windowIdentifier(for element: AXUIElement) -> Int? {
        let (error, windowIdentifier) = backend(element)
        guard error == .success else {
            logger.error("Failed to resolve CGWindowID: AXError \(error.rawValue, privacy: .public)")
            return nil
        }
        return Int(windowIdentifier)
    }
}
