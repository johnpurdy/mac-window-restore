#include "CAXWindowID.h"

AXError CAXWindowIDGet(AXUIElementRef element, CGWindowID *outWindowIdentifier) {
    return _AXUIElementGetWindow(element, outWindowIdentifier);
}
