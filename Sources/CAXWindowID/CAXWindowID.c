#include "CAXWindowID.h"

// The private symbol is not declared in any public header, so provide a local
// prototype for it. It is exported by ApplicationServices / HIServices, which the
// target links explicitly.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);

AXError CAXGetWindowID(AXUIElementRef element, CGWindowID *outID) {
    return _AXUIElementGetWindow(element, outID);
}
