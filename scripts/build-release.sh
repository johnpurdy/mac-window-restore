#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
SIGNING_IDENTITY="Developer ID Application: John Purdy (2U3X822638)"
NOTARIZE_PROFILE="WindowRestore-Notarize"
APP_NAME="Window Restore"
BINARY_NAME="WindowRestore"
BUNDLE_ID="com.windowrestore.app"

BUILD_DIR=".build/release-package"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH=".build/WindowRestore-$VERSION.dmg"
TEMPLATE_APP="/Applications/$APP_NAME.app"

echo "=== Building Window Restore v$VERSION ==="

# Verify template app bundle exists
if [[ ! -d "$TEMPLATE_APP" ]]; then
    echo "Error: Template app bundle not found at $TEMPLATE_APP"
    echo "Please install the app first before creating a release."
    exit 1
fi

if [[ ! -f "$TEMPLATE_APP/Contents/Info.plist" ]]; then
    echo "Error: Invalid app bundle structure - missing Info.plist"
    exit 1
fi

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release binary
echo "Building release binary..."
swift build -c release

# Find the binary (path varies by Swift version/architecture)
BINARY_PATH=$(swift build -c release --show-bin-path)/$BINARY_NAME

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: Build failed - binary not found at $BINARY_PATH"
    exit 1
fi

# Copy app bundle template
echo "Creating app bundle..."
cp -R "$TEMPLATE_APP" "$APP_PATH"

# Copy new binary
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$BINARY_NAME"

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"

# Sign the app
echo "Signing app..."
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose "$APP_PATH"

# Create DMG
echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

# Sign the DMG
echo "Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

# Notarize
echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# Verify notarization
echo "Verifying notarization..."
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

echo ""
echo "=== Done! ==="
echo "DMG ready at: $DMG_PATH"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION $DMG_PATH --title \"v$VERSION\" --notes \"Release notes here\""
