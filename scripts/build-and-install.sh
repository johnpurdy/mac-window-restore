#!/bin/bash
set -euo pipefail

SIGNING_IDENTITY="Developer ID Application: John Purdy (2U3X822638)"
APP_PATH="/Applications/Window Restore.app"
BINARY_NAME="WindowRestore"
DEV_MODE=false

# Parse arguments
if [[ "${1:-}" == "--dev" ]]; then
    DEV_MODE=true
fi

# Verify app bundle exists
if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: App bundle not found at $APP_PATH"
    echo "Please install the app first before using this script."
    exit 1
fi

if [[ ! -d "$APP_PATH/Contents/MacOS" ]]; then
    echo "Error: Invalid app bundle structure at $APP_PATH"
    exit 1
fi

if [[ "$DEV_MODE" == true ]]; then
    echo "Building debug..."
    swift build
    BINARY_PATH=$(swift build --show-bin-path)/$BINARY_NAME
else
    echo "Building release..."
    swift build -c release
    BINARY_PATH=$(swift build -c release --show-bin-path)/$BINARY_NAME
fi

echo "Installing to $APP_PATH..."
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$BINARY_NAME"

echo "Signing with: $SIGNING_IDENTITY"
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"

echo "Verifying signature..."
codesign -dv "$APP_PATH" 2>&1 | grep -E "(Identifier|TeamIdentifier|Signature)"

echo ""
if [[ "$DEV_MODE" == true ]]; then
    echo "Done! Launching in dev mode with logging..."
    echo "Press Ctrl+C to stop."
    echo ""
    "$APP_PATH/Contents/MacOS/$BINARY_NAME" --dev
else
    echo "Done! Restart the app to use the new version."
fi
