#!/bin/bash
set -euo pipefail

SIGNING_IDENTITY="Developer ID Application: MacGregor Consulting LLC (2U3X822638)"
NOTARIZE_PROFILE="WindowRestore-Notarize"
APP_NAME="Window Restore"
BINARY_NAME="WindowRestore"
BUNDLE_ID="com.windowrestore.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BUILD_DIR=".build/release-package"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
TEMPLATE_APP="/Applications/$APP_NAME.app"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"

# Read version from Info.plist
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Error: Info.plist not found at $INFO_PLIST"
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
DMG_PATH=".build/WindowRestore-$VERSION.dmg"

echo "=== Building Window Restore v$VERSION ==="

# Verify template app bundle exists
if [[ ! -d "$TEMPLATE_APP" ]]; then
    echo "Error: Template app bundle not found at $TEMPLATE_APP"
    echo "Please install the app first before creating a release."
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

# Copy Info.plist from project (source of truth for version)
cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"

# Sign the app
echo "Signing app..."
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose "$APP_PATH"

# Create DMG
# Creating "/Volumes/Window Restore/Window Restore.app" directly is refused with
# "Operation not permitted" on this machine (cause unknown), so build the image
# under a temporary volume name and rename the volume before compressing it.
echo "Creating DMG..."
TEMPORARY_VOLUME_NAME="WindowRestoreBuild"
WRITABLE_DMG_PATH="$BUILD_DIR/WindowRestore-writable.dmg"
rm -f "$DMG_PATH" "$WRITABLE_DMG_PATH"
hdiutil create -volname "$TEMPORARY_VOLUME_NAME" -srcfolder "$APP_PATH" -format UDRW "$WRITABLE_DMG_PATH"
DEVICE=$(hdiutil attach -nobrowse -noverify "$WRITABLE_DMG_PATH" | awk -v volume="/Volumes/$TEMPORARY_VOLUME_NAME" '$NF == volume {print $1}')
if [[ -z "$DEVICE" ]]; then
    echo "Error: could not find the mounted volume $TEMPORARY_VOLUME_NAME"
    exit 1
fi
diskutil rename "$DEVICE" "$APP_NAME"
hdiutil detach "$DEVICE"
hdiutil convert "$WRITABLE_DMG_PATH" -format UDZO -o "$DMG_PATH"
rm -f "$WRITABLE_DMG_PATH"

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
