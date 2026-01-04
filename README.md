# Window Restore

A macOS menu bar app that automatically saves and restores window positions when external monitors are connected or disconnected.

## The Problem

macOS doesn't reliably remember window positions when you disconnect and reconnect external monitors. Windows often end up piled on your laptop screen or in random positions.

## The Solution

Window Restore runs quietly in your menu bar and:

- **Auto-saves** window positions at a configurable interval (default: 30 seconds)
- **Auto-restores** windows when monitors connect or disconnect
- **Remembers** different configurations for different monitor setups
- **Cleans up** stale windows that haven't been seen in a configurable period

## Requirements

- macOS 14.0 or later
- Accessibility permissions (required to move windows)

## Installation

### Download

1. Download the latest `WindowRestore-x.x.x.dmg` from [Releases](https://github.com/johnpurdy/mac-window-restore/releases)
2. Open the DMG and drag **Window Restore** to your Applications folder
3. Launch the app from Applications
4. Grant Accessibility permissions when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable **Window Restore**

That's it! The app will appear in your menu bar.

### Build from Source

```bash
git clone https://github.com/johnpurdy/mac-window-restore.git
cd mac-window-restore
./scripts/build-and-install.sh
```

This builds, signs, and installs to `/Applications/Window Restore.app`.

## Usage

The app runs in your menu bar with these options:

| Menu Item | Description |
|-----------|-------------|
| **Primary Actions** | |
| Save Window Positions Now | Manually save current positions |
| Restore Window Positions | Manually restore positions |
| **Saving Options** | |
| Pause Saving | Temporarily stop auto-saving (session only) |
| Save Frequency | Choose save interval: 15s, 30s, 1min, 2min, 5min |
| Auto-restore on Monitor Change | Submenu: On Connect / On Disconnect |
| **Data Management** | |
| Keep Windows For | Choose cleanup threshold: 1, 3, 7, 14, 30 days |
| Clear All Window Positions… | Delete all saved positions (with confirmation) |
| **App Settings** | |
| Keyboard Shortcuts… | Customize save/restore keyboard shortcuts |
| Launch at Login | Start automatically on login |
| **Help & Info** | |
| How It Works… | Detailed explanation of app behavior |
| View Logs in Console… | Open Console.app with filter applied |
| About Window Restore | App information |
| Quit | Exit the app |

### Keyboard Shortcuts

Default shortcuts (customizable via menu):
- **⌃⌘Z** (Control + Command + Z) — Restore window positions
- **⌃⌘S** (Control + Command + S) — Save window positions

Open **Keyboard Shortcuts…** from the menu to customize these.

## How It Works

### Saving
- Window positions are automatically saved at your chosen interval
- Each save captures windows visible on the current desktop
- Windows from other desktops are preserved from previous saves

### Restoring
- Only moves windows visible on your current desktop
- Windows are matched first by title, then by position (within same app)
- Position fallback handles browser tabs changing titles between save/restore
- Switch to another desktop and restore again to fix those windows

### Multiple Desktops
- The app remembers windows across all your desktops
- Visit each desktop periodically so windows get saved
- Restore works per-desktop — switch desktops and restore as needed

### Monitor Changes
- Restore triggers automatically when monitors connect or disconnect
- Both can be individually toggled via "Auto-restore on Monitor Change" submenu
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

Run with verbose logging to stdout:

```bash
.build/debug/WindowRestore --dev
```

### Viewing Logs

The app logs to the macOS unified logging system. View logs in Console.app:

1. Open **Console.app**
2. Select your Mac in the sidebar
3. Filter by: `subsystem:com.windowrestore.app`

Categories: `general`, `save`, `restore`, `monitor`, `accessibility`

## Architecture

```
Sources/WindowRestore/
├── App/
│   ├── WindowRestoreApp.swift       # Entry point
│   ├── AppDelegate.swift            # Menu bar, scheduling
│   ├── KeyboardShortcutManager.swift # Shortcut registration
│   ├── KeyboardShortcutNames.swift  # Shortcut name definitions
│   └── ShortcutsSettingsWindow.swift # Settings UI
├── Models/
│   ├── WindowSnapshot.swift      # Window state with timestamp
│   ├── DisplayInfo.swift         # Monitor info
│   └── DisplayConfiguration.swift # Full config
└── Services/
    ├── WindowEnumerator.swift    # Get all windows via Accessibility API
    ├── WindowPositioner.swift    # Move windows
    ├── WindowMatcher.swift       # Title + position-based matching
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
