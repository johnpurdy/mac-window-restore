# Window Position Restore for External Monitors

## Problem Statement

When using a MacBook with two external monitors, disconnecting and reconnecting the monitors causes all windows to lose their positions. macOS moves windows that were on external displays to the built-in display when monitors disconnect, and does not restore them when monitors reconnect.

**Desired behavior:** Automatically save window positions when external monitors disconnect, and restore them when the same monitors reconnect — without requiring manual "save layout" actions.

## Why Existing Solutions Don't Work

### Rectangle Pro / Moom
- Can trigger saved layouts on display connect/disconnect
- But layouts must be **manually saved** beforehand
- No API to programmatically save current layout
- If you rearrange windows throughout the day, you'd need to re-save before every disconnect

### Stay (by Cordless Dog)
- Used to do exactly what we want (auto-save/restore)
- Abandoned — no updates in years, now unreliable on modern macOS

### Display Maid
- Mixed reviews on reliability
- Similar manual-save paradigm

### Memmon (open source)
- Attempts to solve this problem
- Could be used as reference: https://github.com/relikd/Memmon

## Technical Requirements

### Core Functionality
1. **Monitor display configuration changes** — Detect when external displays connect or disconnect
2. **On disconnect:** Capture current window positions for all windows on external displays
3. **On reconnect:** Restore windows to their saved positions on the appropriate displays
4. **Persist state:** Save window positions to disk so they survive app/system restarts

### macOS APIs Needed

#### Display Change Detection
- `CGDisplayRegisterReconfigurationCallback` — Core Graphics callback for display changes
- Or `NSScreen` notifications via NotificationCenter

#### Window Position Management
- **Accessibility API** (`AXUIElement`) — Required to get and set window positions
- App will need Accessibility permissions (System Settings → Privacy & Security → Accessibility)
- Key functions:
  - `AXUIElementCopyAttributeValue` — Get window position/size
  - `AXUIElementSetAttributeValue` — Set window position/size
  - Attributes: `kAXPositionAttribute`, `kAXSizeAttribute`

#### Running Apps/Windows Enumeration
- `NSWorkspace.shared.runningApplications`
- `CGWindowListCopyWindowInfo` — Get list of all windows

### Data to Capture Per Window
- Application bundle identifier or name
- Window title (for apps with multiple windows)
- Window frame (x, y, width, height)
- Display identifier where window was located

### Display Identification
- Need to identify displays reliably across reconnects
- `CGDirectDisplayID` may change between connections
- Consider using display serial number, model, or resolution as stable identifier
- `CGDisplayIOServicePort` → `IODisplayGetInfoDictionary` for hardware info

## Architecture

### App Type
- Menu bar app (background daemon)
- Minimal UI — just a status icon, maybe with manual save/restore options
- Launch at login option

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                    WindowRestoreApp                      │
├─────────────────────────────────────────────────────────┤
│  DisplayMonitor                                          │
│  - Listens for display connect/disconnect events         │
│  - Identifies display configuration                      │
├─────────────────────────────────────────────────────────┤
│  WindowSnapshotService                                   │
│  - Enumerates all windows                                │
│  - Captures positions via Accessibility API              │
│  - Maps windows to displays                              │
├─────────────────────────────────────────────────────────┤
│  WindowRestoreService                                    │
│  - Reads saved snapshot                                  │
│  - Matches windows to saved positions                    │
│  - Restores via Accessibility API                        │
├─────────────────────────────────────────────────────────┤
│  PersistenceLayer                                        │
│  - Saves snapshots to JSON file                          │
│  - Handles multiple display configurations               │
│  - Location: ~/Library/Application Support/WindowRestore │
└─────────────────────────────────────────────────────────┘
```

### State Storage (JSON example)

```json
{
  "displayConfigs": {
    "config-abc123": {
      "displays": [
        {"id": "serial-xxx", "name": "LG UltraFine", "resolution": "3840x2160"},
        {"id": "serial-yyy", "name": "Dell U2720Q", "resolution": "3840x2160"}
      ],
      "windows": [
        {
          "appBundleId": "com.apple.Safari",
          "windowTitle": "Apple",
          "displayId": "serial-xxx",
          "frame": {"x": 100, "y": 50, "width": 1200, "height": 800}
        }
      ],
      "lastUpdated": "2024-12-22T10:30:00Z"
    }
  }
}
```

## Edge Cases to Handle

1. **App not running** — Window can't be restored if the app isn't open. Options:
   - Skip and log
   - Optionally launch the app (probably not desirable)

2. **Window doesn't exist anymore** — App is running but specific window is closed
   - Match by app + title, skip if not found

3. **Multiple windows same app** — e.g., multiple Finder or browser windows
   - Use window title to differentiate
   - May need heuristics if titles changed

4. **Display order changed** — User plugs monitors into different ports
   - Use stable display identifiers, not port-based IDs

5. **Some apps resist positioning** — Certain apps don't respond well to Accessibility API
   - Log failures, don't crash

6. **Rapid connect/disconnect** — Debounce display change events

## Known Limitations

- **Spaces/Virtual Desktops:** Apple provides no public API for moving windows between Spaces. Windows will restore to the current Space only.
- **Full-screen apps:** May need special handling or exclusion.
- **Permission required:** User must grant Accessibility permission on first run.

## Development Notes

- **Language:** Swift (best for macOS APIs and Accessibility framework)
- **Target:** macOS 13+ (or adjust based on API availability)
- **Testing:** Will need to physically connect/disconnect monitors to test fully
- **Reference:** Look at Memmon source code for implementation patterns

## Success Criteria

1. App runs silently in background with menu bar icon
2. When I disconnect my two external monitors, window positions are saved automatically
3. When I reconnect the same monitors, windows return to their saved positions within a few seconds
4. Works across system restarts
5. Handles day-to-day window rearrangement without manual intervention

## Out of Scope (for v1)

- Syncing across multiple Macs
- Multiple saved layouts/profiles
- UI for manually editing saved positions
- Integration with Rectangle Pro or other window managers