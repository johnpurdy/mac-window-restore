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

# Update app in /Applications after changes
swift build -c release && \
cp .build/release/WindowRestore "/Applications/Window Restore.app/Contents/MacOS/" && \
codesign --force --deep --sign - "/Applications/Window Restore.app"
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
| `DisplayMonitor` | Detects monitor connect/disconnect |
| `PersistenceService` | JSON storage to ~/Library/Application Support/WindowRestore/ |
| `SnapshotScheduler` | 30-second save timer |
| `RestoreCoordinator` | Orchestrates the restore flow |

### Data Flow

1. **Save**: `SnapshotScheduler` → `WindowEnumerator` → `PersistenceService`
2. **Restore**: `DisplayMonitor` → `RestoreCoordinator` → `WindowPositioner`

## Code Conventions

### Swift 6 Strict Concurrency

- All models are `Sendable`
- `AppDelegate` is `@MainActor`
- Services use `@unchecked Sendable` with internal synchronization where needed
- Callbacks in schedulers/monitors use `@Sendable` closures

### Patterns

- Protocols for testability (`WindowEnumerating`, `WindowPositioning`, `DisplayInfoProviding`)
- Dependency injection via initializers
- No singletons

### Testing

- Unit tests use mocks for system APIs
- Tests are in `Tests/WindowRestoreTests/` mirroring source structure
- Use Swift Testing framework (`@Test`, `#expect`)

## macOS APIs Used

| API | Purpose |
|-----|---------|
| `CGWindowListCopyWindowInfo` | Enumerate visible windows |
| `AXUIElement` | Get window titles, move/resize windows |
| `NSApplication.didChangeScreenParametersNotification` | Detect monitor changes |
| `CGDirectDisplay` | Get display properties |
| `SMAppService` | Launch at login (macOS 13+) |

## Important Notes

1. **Accessibility permissions required** - App must be code-signed and added to System Settings → Privacy & Security → Accessibility

2. **Window matching** - Windows are matched by app bundle ID + window title. Empty titles match the first window.

3. **Display identification** - Displays are identified by a hash of vendor/model/serial number, not display ID (which changes).

4. **App bundle required** - Must run as .app bundle (not raw executable) for Accessibility to work properly.
