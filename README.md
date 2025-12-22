# Window Restore

A macOS menu bar app that automatically saves and restores window positions when external monitors are connected or disconnected.

## The Problem

macOS doesn't reliably remember window positions when you disconnect and reconnect external monitors. Windows often end up piled on your laptop screen or in random positions.

## The Solution

Window Restore runs quietly in your menu bar and:

- **Auto-saves** window positions at a configurable interval (default: 30 seconds)
- **Auto-restores** windows when monitors reconnect
- **Remembers** different configurations for different monitor setups
- **Cleans up** stale windows that haven't been seen in a configurable period

## Requirements

- macOS 14.0 or later
- Accessibility permissions (required to move windows)

## Installation

### From Source

```bash
git clone https://github.com/johnpurdy/mac-window-restore.git
cd mac-window-restore
swift build -c release
```

Create the app bundle:

```bash
mkdir -p "Window Restore.app/Contents/MacOS"
mkdir -p "Window Restore.app/Contents/Resources"
cp .build/release/WindowRestore "Window Restore.app/Contents/MacOS/"
```

Create `Window Restore.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.windowrestore.app</string>
    <key>CFBundleName</key>
    <string>Window Restore</string>
    <key>CFBundleDisplayName</key>
    <string>Window Restore</string>
    <key>CFBundleExecutable</key>
    <string>WindowRestore</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

Move to Applications and sign:

```bash
mv "Window Restore.app" /Applications/
codesign --force --deep --options runtime --sign "Developer ID Application: Your Name (TEAMID)" "/Applications/Window Restore.app"
```

> **Note:** Signing with a Developer ID ensures accessibility permissions persist across app updates. Without proper signing, you'll need to re-grant permissions after each update.

### Updating

After making changes, use the build script:

```bash
./scripts/build-and-install.sh
```

This builds, installs, and signs the app in one step.

### Generate App Icon (Optional)

```bash
swift generate-icon.swift
iconutil -c icns AppIcon.iconset -o "/Applications/Window Restore.app/Contents/Resources/AppIcon.icns"
```

Add to Info.plist:
```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

## Usage

1. Launch the app:
   ```bash
   open "/Applications/Window Restore.app"
   ```

2. Grant Accessibility permissions when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable "Window Restore"

3. The app runs in your menu bar with these options:

| Menu Item | Description |
|-----------|-------------|
| Save Window Positions Now | Manually save current positions |
| Restore Window Positions (⌃⌘Z) | Manually restore positions |
| Save Frequency | Choose save interval: 15s, 30s, 1min, 2min, 5min |
| Keep Windows For | Choose cleanup threshold: 1, 3, 7, 14, 30 days |
| Launch at Login | Start automatically on login |
| How It Works… | Detailed explanation of app behavior |
| About Window Restore | App information |
| Quit | Exit the app |

### Global Hotkey

Press **⌃⌘Z** (Control + Command + Z) anywhere to restore window positions.

## How It Works

### Saving
- Window positions are automatically saved at your chosen interval
- Each save captures windows visible on the current desktop
- Windows from other desktops are preserved from previous saves
- Windows are identified by app bundle ID + window title

### Restoring
- Only moves windows visible on your current desktop
- Each window is matched to its saved position by title
- Switch to another desktop and restore again to fix those windows

### Multiple Desktops
- The app remembers windows across all your desktops
- Visit each desktop periodically so windows get saved
- Restore works per-desktop — switch desktops and restore as needed

### Monitor Changes
- When you reconnect external monitors, restore triggers automatically
- Different monitor configurations are saved separately

### Cleanup
- Windows not seen within the "Keep Windows For" period are removed
- This prevents the saved data from growing indefinitely
- Default threshold is 7 days

## Data Storage

Configurations are stored as JSON in:
```
~/Library/Application Support/WindowRestore/
```

Each file is named `config-{hash}.json` where the hash represents a unique monitor configuration.

## Development

### Running Tests

```bash
swift test
```

### Dev Mode

Run with logging enabled:

```bash
.build/debug/WindowRestore --dev
```

Logs are written to `~/Library/Application Support/WindowRestore/app.log`

## Architecture

```
Sources/WindowRestore/
├── App/
│   ├── WindowRestoreApp.swift    # Entry point
│   └── AppDelegate.swift         # Menu bar, hotkey, scheduling
├── Models/
│   ├── WindowSnapshot.swift      # Window state with timestamp
│   ├── DisplayInfo.swift         # Monitor info
│   └── DisplayConfiguration.swift # Full config
└── Services/
    ├── WindowEnumerator.swift    # Get all windows via Accessibility API
    ├── WindowPositioner.swift    # Move windows
    ├── WindowMerger.swift        # Merge & prune stale windows
    ├── DisplayMonitor.swift      # Detect monitor changes
    ├── DisplayInfoProvider.swift # Get monitor info
    ├── DisplayIdentifier.swift   # Stable monitor IDs
    ├── PersistenceService.swift  # Save/load configs
    ├── SnapshotScheduler.swift   # Configurable timer
    └── RestoreCoordinator.swift  # Orchestrate restore
```

## License

MIT
