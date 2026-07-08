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
Sources/
├── CAXWindowID/            # C shim exposing the private _AXUIElementGetWindow symbol
└── WindowRestore/
    ├── App/                # Entry point and menu bar
    ├── Models/             # Data structures (Codable, Sendable)
    └── Services/           # Business logic
```

### Key Services

| Service | Responsibility |
|---------|----------------|
| `WindowIdentifierResolver` | Resolves the exact CGWindowID for an `AXUIElement` via `_AXUIElementGetWindow` (returns nil, never a guess, on failure/null id) |
| `RawWindowProvider` | Save-side AX enumeration: gathers windows, resolves ids, extracts tabs, normalizes duplicate ids (`RawWindowProviding` seam) |
| `CurrentWindowProvider` | Restore-side AX enumeration: binds each live `AXUIElement` to its resolved `CurrentWindow` (`CurrentWindowProviding` seam) |
| `WindowEnumerator` | Maps raw windows to `WindowSnapshot`s; owns the empty-title / zero-size persistence filters and display assignment |
| `WindowMatcher` | Matches saved snapshots to current windows (id → tabs → title), returning the matched `currentIndex` and match reason |
| `WindowPositioner` | Moves the matcher-selected element by index via the `WindowElementPositioning` effect seam; restores minimized state |
| `WindowElementPositioning` | Effect seam wrapping the AX position/size/minimize calls (result type preserves error codes) |
| `WindowIdentifierNormalization` | Pure helper that neutralizes duplicate non-nil ids to nil (shared by both providers) |
| `WindowMerger` | Merges windows by windowIdentifier (or tabs/title fallback), prunes stale entries |
| `DisplayMonitor` | Detects monitor connect/disconnect |
| `PersistenceService` | JSON storage to ~/Library/Application Support/WindowRestore/ |
| `SnapshotScheduler` | Configurable save timer (15s, 30s, 1min, 2min, 5min) |
| `RestoreCoordinator` | Orchestrates the restore flow |
| `KeyboardShortcutManager` | Registers shortcuts via KeyboardShortcuts library |

### Data Flow

1. **Save**: `SnapshotScheduler` → `WindowEnumerator` (← `RawWindowProvider` ← `WindowIdentifierResolver`) → `WindowMerger` → `PersistenceService`
2. **Restore**: `DisplayMonitor` or hotkey → `RestoreCoordinator` → `WindowPositioner` (← `CurrentWindowProvider` ← `WindowIdentifierResolver`; matches via `WindowMatcher`, moves via `WindowElementPositioning`)

### Key Models

| Model | Fields |
|-------|--------|
| `WindowSnapshot` | bundleId, appName, windowTitle, displayId, frame, `lastSeenAt`, `isMinimized`, `windowIdentifier` |
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
| Minimized state tracking | `WindowEnumerator` reads `kAXMinimizedAttribute`, `WindowPositioner` restores it |
| CGWindowID tracking | Windows identified by exact CGWindowID from `_AXUIElementGetWindow` (via `CAXWindowID`), with tab/title fallback when id is nil |

## Code Conventions

### Swift 6 Strict Concurrency

- All models are `Sendable`
- `AppDelegate` is `@MainActor`
- Stateless services prefer compiler-verified `Sendable`; `@unchecked Sendable` is used only where internal synchronization is required
- The private `AXUIElement` boundary uses `@preconcurrency import ApplicationServices` (providers run off the main thread, so `@MainActor` isolation would be wrong)
- Callbacks in schedulers/monitors use `@Sendable` closures

### Patterns

- Protocols for testability (`WindowEnumerating`, `WindowPositioning`, `DisplayInfoProviding`, `WindowIdentifierResolving`, `RawWindowProviding`, `CurrentWindowProviding`, `WindowElementPositioning`)
- Dependency injection via initializers (the AX-touching seams let save/restore logic be unit-tested with fakes)
- No singletons
- Logging via `os.Logger` (viewable in Console.app, subsystem: `com.windowrestore.app`)

### Testing

- Unit tests use mocks for system APIs
- Tests are in `Tests/WindowRestoreTests/` mirroring source structure
- Use Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- TDD approach for new features

## macOS APIs Used

| API | Purpose |
|-----|---------|
| `AXUIElement` | Get window titles/minimized state, move/resize/minimize windows |
| `_AXUIElementGetWindow` (private) | Get the exact CGWindowID for an `AXUIElement`; isolated in the `CAXWindowID` C target (no `@_silgen_name`) |
| `NSWorkspace.runningApplications` | Enumerate running apps for window enumeration |
| `KeyboardShortcuts` (library) | Configurable global hotkeys |
| `NSApplication.didChangeScreenParametersNotification` | Detect monitor changes |
| `CGDirectDisplay` | Get display properties |
| `SMAppService` | Launch at login (macOS 13+) |

## Important Notes

1. **Accessibility permissions required** - App must be signed with Developer ID and added to System Settings → Privacy & Security → Accessibility

2. **Developer ID signing** - Use `codesign --force --deep --options runtime --sign "Developer ID Application: ..."` to preserve accessibility permissions across updates

3. **Window matching** - Windows are matched by CGWindowID first (stable identifier), then by tab overlap (browsers), then by title as fallback. On restore, `WindowMatcher` returns the matched `currentIndex` so `WindowPositioner` moves the exact selected window (optional ids are never compared, avoiding `nil == nil` collisions). CGWindowID doesn't change when browser tabs switch, solving the multi-tab browser problem.

4. **Display identification** - Displays are identified by a hash of vendor/model/serial number, not display ID (which changes).

5. **App bundle required** - Must run as .app bundle (not raw executable) for Accessibility to work properly.

6. **Stale window cleanup** - Windows have a `lastSeenAt` timestamp. Windows older than the threshold (default 7 days) are pruned during merge. Legacy JSON without timestamps is handled via backward-compatible decoding.

7. **Minimized state tracking** - Windows have an `isMinimized` field. Each monitor config saves its own minimized states. On restore, windows are minimized/unminimized to match the saved state. Legacy JSON without `isMinimized` defaults to `false`.

8. **CGWindowID tracking** - Windows have a `windowIdentifier` field (CGWindowID). This exact id is obtained directly from the window's `AXUIElement` via the private `_AXUIElementGetWindow` (isolated in the `CAXWindowID` C target), not by frame matching — so windows stacked at the same position get distinct ids. If resolution fails or returns a null id, `windowIdentifier` is stored as nil (missing is safer than wrong), and duplicate non-nil ids from one pass are normalized to nil. CGWindowID persists across tab switches in browsers. Legacy/nil `windowIdentifier` falls back to tab/title matching.
