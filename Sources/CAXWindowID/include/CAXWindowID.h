#ifndef CAXWindowID_h
#define CAXWindowID_h

#include <ApplicationServices/ApplicationServices.h>

/// Returns the exact CGWindowID for an accessibility window element.
///
/// Thin wrapper over the private, undocumented `_AXUIElementGetWindow` symbol
/// (exported by ApplicationServices / HIServices). Isolating it here keeps the
/// private symbol out of the Swift sources.
AXError CAXGetWindowID(AXUIElementRef element, CGWindowID *outID);

#endif /* CAXWindowID_h */
