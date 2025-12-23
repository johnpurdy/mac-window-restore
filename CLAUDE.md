# CLAUDE.md

## Project Overview

Window Restore is a macOS menu bar app that saves and restores window positions when external monitors are connected/disconnected.

## Quick Commands

```bash
# Build
swift build

# Build release
swift build -c release

# Run tests
swift test

# Build, install, and sign (recommended)
./scripts/build-and-install.sh

# Manual install with Developer ID signing
swift build -c release && \
cp "$(swift build -c release --show-bin-path)/WindowRestore" "/Applications/Window Restore.app/Contents/MacOS/" && \
codesign --force --deep --options runtime --sign "Developer ID Application: John Purdy (2U3X822638)" "/Applications/Window Restore.app"

# Run in dev mode (with logging)
.build/debug/WindowRestore --dev
```

## Architecture

```
Sources/WindowRestore/
├── App/                    # Entry point and menu bar
├── Models/                 # Data structures (Codable, Sendable)
└── Services/               # Business logic
```

### Key Services

| Service | Responsibility |
|---------|----------------|
| `WindowEnumerator` | Gets all windows via CGWindowList + Accessibility API |
| `WindowPositioner` | Moves windows via AXUIElement |
| `WindowMerger` | Merges current windows with saved, prunes stale entries |
| `DisplayMonitor` | Detects monitor connect/disconnect |
| `PersistenceService` | JSON storage to ~/Library/Application Support/WindowRestore/ |
| `SnapshotScheduler` | Configurable save timer (15s, 30s, 1min, 2min, 5min) |
| `RestoreCoordinator` | Orchestrates the restore flow |
| `KeyboardShortcutManager` | Registers shortcuts via KeyboardShortcuts library |

### Data Flow

1. **Save**: `SnapshotScheduler` → `WindowEnumerator` → `WindowMerger` → `PersistenceService`
2. **Restore**: `DisplayMonitor` or hotkey → `RestoreCoordinator` → `WindowPositioner`

### Key Models

| Model | Fields |
|-------|--------|
| `WindowSnapshot` | bundleId, appName, windowTitle, displayId, frame, `lastSeenAt` |
| `DisplayInfo` | identifier, name, resolution, position |
| `DisplayConfiguration` | identifier, displays[], windows[], capturedAt |

## Features

| Feature | Implementation |
|---------|----------------|
| Auto-save | `SnapshotScheduler` with configurable interval (UserDefaults) |
| Pause Saving | Stops `SnapshotScheduler`, session-only (not persisted) |
| Auto-restore | `DisplayMonitor` triggers on monitor connect/disconnect |
| Auto-restore toggles | UserDefaults `RestoreOnConnectEnabled` and `RestoreOnDisconnectEnabled`, both default true |
| Keyboard shortcuts | Configurable via `KeyboardShortcutManager` using KeyboardShortcuts library |
| Save Frequency menu | 15s, 30s, 1min, 2min, 5min options |
| Keep Windows For menu | 1, 3, 7, 14, 30 day stale threshold |
| Clear All Positions | `PersistenceService.deleteAllConfigurations()` with confirmation dialog |
| Launch at Login | `SMAppService.mainApp` (macOS 13+) |
| Multi-desktop support | Merge preserves windows from other desktops |
| Stale cleanup | `WindowMerger` filters by `lastSeenAt` timestamp |

## Code Conventions

### Swift 6 Strict Concurrency

- All models are `Sendable`
- `AppDelegate` is `@MainActor`
- Services use `@unchecked Sendable` with internal synchronization where needed
- Callbacks in schedulers/monitors use `@Sendable` closures

### Patterns

- Protocols for testability (`WindowEnumerating`, `WindowPositioning`, `DisplayInfoProviding`)
- Dependency injection via initializers
- No singletons (except `FileLogger` for dev mode)

### Testing

- Unit tests use mocks for system APIs
- Tests are in `Tests/WindowRestoreTests/` mirroring source structure
- Use Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- TDD approach for new features

## macOS APIs Used

| API | Purpose |
|-----|---------|
| `CGWindowListCopyWindowInfo` | Enumerate visible windows |
| `AXUIElement` | Get window titles, move/resize windows |
| `KeyboardShortcuts` (library) | Configurable global hotkeys |
| `NSApplication.didChangeScreenParametersNotification` | Detect monitor changes |
| `CGDirectDisplay` | Get display properties |
| `SMAppService` | Launch at login (macOS 13+) |

## Important Notes

1. **Accessibility permissions required** - App must be signed with Developer ID and added to System Settings → Privacy & Security → Accessibility

2. **Developer ID signing** - Use `codesign --force --deep --options runtime --sign "Developer ID Application: ..."` to preserve accessibility permissions across updates

3. **Window matching** - Windows are matched by app bundle ID + window title. Empty titles match the first window.

4. **Display identification** - Displays are identified by a hash of vendor/model/serial number, not display ID (which changes).

5. **App bundle required** - Must run as .app bundle (not raw executable) for Accessibility to work properly.

6. **Stale window cleanup** - Windows have a `lastSeenAt` timestamp. Windows older than the threshold (default 7 days) are pruned during merge. Legacy JSON without timestamps is handled via backward-compatible decoding.
