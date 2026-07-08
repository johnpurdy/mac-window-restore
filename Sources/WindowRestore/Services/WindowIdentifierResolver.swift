import Foundation
// `@preconcurrency` is the deliberate choice (over `@MainActor` isolation) for bridging
// the non-Sendable `AXUIElement` across this `Sendable` boundary: the providers run off the
// main thread on the save/restore paths, so main-actor isolation would be wrong here.
@preconcurrency import ApplicationServices
import CAXWindowID

/// Resolves the exact CGWindowID for an accessibility window element.
///
/// Replaces the old frame-matching heuristic, which mis-assigned identifiers when
/// multiple windows of one app shared the same frame (the stacked-Edge bug).
public protocol WindowIdentifierResolving: Sendable {
    /// Returns the exact CGWindowID for an accessibility window element,
    /// or nil if it cannot be determined.
    func windowIdentifier(for element: AXUIElement) -> Int?
}

/// Production resolver calling the private `_AXUIElementGetWindow` via the C shim.
public struct AXWindowIdentifierResolver: WindowIdentifierResolving {
    public init() {}

    public func windowIdentifier(for element: AXUIElement) -> Int? {
        var windowId: CGWindowID = 0
        let error = CAXGetWindowID(element, &windowId)
        return AXWindowIdentifierResolver.resolve(error: error, windowId: windowId)
    }

    /// Pure conversion from the C call's result to an identifier.
    ///
    /// A missing identifier is always preferred over a wrong one:
    /// - non-success errors return nil
    /// - a null window id (`kCGNullWindowID` / 0) returns nil even on success,
    ///   so it is never stored as the real identifier 0.
    static func resolve(error: AXError, windowId: CGWindowID) -> Int? {
        guard error == .success else { return nil }
        guard windowId != CGWindowID(kCGNullWindowID) else { return nil }
        return Int(windowId)
    }
}
