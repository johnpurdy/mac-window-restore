# Window Restore

A macOS menu bar app that automatically saves and restores window positions when external monitors are connected or disconnected.

## The Problem

macOS doesn't reliably remember window positions when you disconnect and reconnect external monitors. Windows often end up piled on your laptop screen or in random positions.

## The Solution

Window Restore runs quietly in your menu bar and:

- **Auto-saves** window positions every 30 seconds
- **Auto-restores** windows when monitors reconnect
- **Remembers** different configurations for different monitor setups

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

Sign the app (required for Accessibility permissions):

```bash
codesign --force --deep --sign - "Window Restore.app"
```

Move to Applications:

```bash
mv "Window Restore.app" /Applications/
```

### Generate App Icon (Optional)

```bash
swift generate-icon.swift
iconutil -c icns AppIcon.iconset -o "Window Restore.app/Contents/Resources/AppIcon.icns"
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

| Menu Item | Shortcut | Description |
|-----------|----------|-------------|
| Save Window Positions Now | ⌘S | Manually save current positions |
| Restore Window Positions | ⌘R | Manually restore positions |
| Launch at Login | — | Start automatically on login |
| About | — | App information |
| Quit | ⌘Q | Exit the app |

## How It Works

1. **Saving**: Every 30 seconds, the app captures all window positions using the Accessibility API, noting each window's app, title, position, size, and which monitor it's on.

2. **Display Configuration**: Windows are saved per display configuration. A unique ID is generated based on connected monitors (vendor, model, serial number).

3. **Restoring**: When monitors reconnect, the app loads the saved configuration for that monitor setup and moves windows back to their saved positions.

4. **Window Matching**: Windows are matched by app bundle ID and window title, allowing multiple windows from the same app to restore to different positions.

## Data Storage

Configurations are stored as JSON in:
```
~/Library/Application Support/WindowRestore/
```

Each file is named `config-{hash}.json` where the hash represents a unique monitor configuration.

## Running Tests

```bash
swift test
```

## Architecture

```
Sources/WindowRestore/
├── App/
│   ├── WindowRestoreApp.swift    # Entry point
│   └── AppDelegate.swift         # Menu bar setup
├── Models/
│   ├── WindowSnapshot.swift      # Window state
│   ├── DisplayInfo.swift         # Monitor info
│   └── DisplayConfiguration.swift # Full config
└── Services/
    ├── WindowEnumerator.swift    # Get all windows
    ├── WindowPositioner.swift    # Move windows
    ├── DisplayMonitor.swift      # Detect monitor changes
    ├── DisplayInfoProvider.swift # Get monitor info
    ├── DisplayIdentifier.swift   # Stable monitor IDs
    ├── PersistenceService.swift  # Save/load configs
    ├── SnapshotScheduler.swift   # 30-second timer
    └── RestoreCoordinator.swift  # Orchestrate restore
```

## License

MIT
