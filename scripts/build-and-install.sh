#!/bin/bash
set -e

SIGNING_IDENTITY="Developer ID Application: John Purdy (2U3X822638)"
APP_PATH="/Applications/Window Restore.app"
BINARY_NAME="WindowRestore"

echo "Building release..."
swift build -c release

echo "Installing to $APP_PATH..."
cp ".build/release/$BINARY_NAME" "$APP_PATH/Contents/MacOS/$BINARY_NAME"

echo "Signing with: $SIGNING_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"

echo "Verifying signature..."
codesign -dv "$APP_PATH" 2>&1 | grep -E "(Identifier|TeamIdentifier|Signature)"

echo ""
echo "Done! Restart the app to use the new version."
