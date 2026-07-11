#ifndef CAXWindowID_h
#define CAXWindowID_h

#include <ApplicationServices/ApplicationServices.h>

/// Private ApplicationServices function: fills `*outWindowIdentifier` with the
/// `CGWindowID` of the given accessibility window and returns `kAXErrorSuccess`,
/// or a non-success `AXError` if the element has no associated window. Exported by
/// the framework but not declared in any public header.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindowIdentifier);

/// Wrapper around `_AXUIElementGetWindow`.
///
/// It returns the exact `CGWindowID` backing a specific accessibility window element,
/// with no frame-based guessing. This wrapper returns the raw `AXError` and writes the
/// resolved id through `outWindowIdentifier` (C has no tuples, so the id cannot be part
/// of the return value). On any non-`.success` result the caller must treat the window
/// as unidentifiable and must not read `*outWindowIdentifier`.
AXError CAXWindowIDGet(AXUIElementRef element, CGWindowID *outWindowIdentifier);

#endif /* CAXWindowID_h */
