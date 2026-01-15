# Window Matching v2 Specification

## 1. Problem Statement

Window restore apps need to match saved window positions to current windows when restoring. This is challenging because:

- **Window titles change**: Browser tabs switch, chat apps show different conversations, documents get renamed
- **Multiple windows per app**: Browsers, editors, and Finder commonly have many windows open
- **No stable OS-provided identifier persists across app restarts**: CGWindowID is stable during a session but resets when the app restarts

The goal is to reliably match saved windows to current windows so positions can be restored correctly.

## 2. App Categories

### Single-Window Apps (Default)

Most apps have only one window open at a time. For these apps, matching is simple: if there's exactly 1 saved window and 1 current window for that bundle ID, they match.

Examples: System Preferences, Calculator, Calendar, most menu bar apps, chat apps (Teams, Messages, Slack, Discord)

**This is the default behavior.** All apps are assumed to be single-window unless explicitly listed as multi-window.

### Multi-Window Apps (Exception List)

Some apps commonly have multiple windows open simultaneously. These require smarter matching strategies.

Examples:
- Browsers (Edge, Chrome, Safari, Firefox)
- Code editors (VS Code, Xcode, Sublime Text)
- Finder
- Preview
- Terminal/iTerm

**These apps are defined in an external JSON configuration file.**

## 3. Window Identification

### CGWindowID as Primary Key

During a session, each window has a stable CGWindowID assigned by the OS. This ID:
- Remains constant even when window title changes (e.g., switching browser tabs)
- Is unique across all windows on the system
- Resets when the app restarts

**CGWindowID is the primary key for identifying "same window" across saves within a session.**

### Obtaining CGWindowID

CGWindowID comes from `CGWindowListCopyWindowInfo`, which is read-only. Window manipulation requires `AXUIElement` from the Accessibility API. These two APIs don't share identifiers, so correlation is done by matching:
- Process ID (PID)
- Window frame position

### Merge Behavior

When saving snapshots:
1. Generate a key for each window: `bundleId|cgWindowId`
2. Current windows replace saved windows with the same key
3. Saved windows with no matching current key are preserved (they're on other desktops)
4. Stale windows (older than threshold) are pruned

This ensures tab lists and titles update in place rather than creating duplicate entries.

## 4. Matching Strategy

When restoring, we need to match saved windows to current windows. The strategy differs by app category.

### Single-Window Apps

If an app has exactly 1 saved window and exactly 1 current window:
- **Match by bundle ID alone**
- No need to compare titles or other attributes

This handles chat apps where the window title changes based on the active conversation.

### Multi-Window Apps

Use a fallback chain:

1. **CGWindowID match**: If the saved `windowIdentifier` matches a current window's CGWindowID, use it. (Only works if app hasn't restarted since save.)

2. **Tab match** (browsers only): Compare tab lists. If overlap percentage >= threshold, consider it a match. Match the pair with highest overlap first.

3. **Title match**: Fall back to exact window title matching.

4. **No match**: Window cannot be matched; skip restoration for this window.

### Tab Matching Details

For browsers that support tab enumeration via Accessibility API:
- Extract tab titles from `AXTabGroup` → `AXRadioButton` elements
- Compare saved tabs to current tabs
- Calculate overlap as: `matchingTabs.count / min(savedTabs.count, currentTabs.count)`
- Threshold: configurable, default 50%

Tab matching solves the problem of browser windows where the active tab (and thus window title) changes frequently, but the collection of tabs remains mostly stable.

## 5. Data Model

### WindowSnapshot

```
WindowSnapshot:
  applicationBundleIdentifier: String  # e.g., "com.microsoft.edgemac"
  applicationName: String              # e.g., "Microsoft Edge"
  windowTitle: String                  # Current window title at save time
  displayIdentifier: String            # Hash of display vendor/model/serial
  frame: CGRect                        # Window position and size
  lastSeenAt: Date                     # For stale window pruning
  isMinimized: Bool                    # Window minimized state
  windowIdentifier: Int?               # CGWindowID (optional for legacy)
  tabs: [String]?                      # Tab titles for browsers (optional)
```

### DisplayConfiguration

```
DisplayConfiguration:
  identifier: String                   # Hash identifying this monitor setup
  displays: [DisplayInfo]              # Connected displays
  windows: [WindowSnapshot]            # Windows for this configuration
  capturedAt: Date                     # When this config was saved
```

## 6. Configuration

### File Location

```
~/Library/Application Support/WindowRestore/app-matching-config.json
```

### Structure

```json
{
  "multiWindowApps": [
    "com.microsoft.edgemac",
    "com.google.Chrome",
    "com.brave.Browser",
    "com.vivaldi.Vivaldi",
    "org.chromium.Chromium",
    "com.apple.Safari",
    "org.mozilla.firefox",
    "com.microsoft.VSCode",
    "com.apple.finder",
    "com.apple.Preview",
    "com.apple.TextEdit",
    "com.apple.dt.Xcode",
    "com.sublimetext.4",
    "com.jetbrains.intellij",
    "com.googlecode.iterm2"
  ],
  "tabEnabledApps": [
    "com.microsoft.edgemac",
    "com.google.Chrome",
    "com.brave.Browser",
    "com.vivaldi.Vivaldi",
    "org.chromium.Chromium"
  ],
  "tabMatchThreshold": 0.5
}
```

### Behavior

- **multiWindowApps**: Apps requiring smart matching. All others use single-window matching.
- **tabEnabledApps**: Subset of multi-window apps where tab enumeration is attempted.
- **tabMatchThreshold**: Minimum overlap percentage for tab-based matching (0.0 to 1.0).

If the config file doesn't exist, use sensible defaults compiled into the app.

## 7. Implementation Plan

### Cycle 1: Configuration Loading

**RED**: Test that `AppMatchingConfig` can load from JSON file

**GREEN**: Create `AppMatchingConfig` struct with loading logic

**REFACTOR**: Add default fallback when file missing

### Cycle 2: Single-Window Matching

**RED**: Test that single-window apps match by bundle ID when 1 saved + 1 current

**GREEN**: Implement single-window matching in `WindowPositioner`

**REFACTOR**: Clean up

### Cycle 3: Multi-Window CGWindowID Matching

**RED**: Test that multi-window apps match by CGWindowID first

**GREEN**: Implement CGWindowID matching

**REFACTOR**: Clean up

### Cycle 4: Tab Enumeration

**RED**: Test that tabs are extracted from browser windows

**GREEN**: Implement `TabEnumerator` for Chromium browsers

**REFACTOR**: Clean up

### Cycle 5: Tab-Based Matching

**RED**: Test that browser windows match by tab overlap percentage

**GREEN**: Implement tab matching with configurable threshold

**REFACTOR**: Clean up

### Cycle 6: Title Fallback

**RED**: Test fallback to title matching when other methods fail

**GREEN**: Implement title fallback

**REFACTOR**: Clean up

### Cycle 7: Merge Logic

**RED**: Test that saves update existing windows by CGWindowID key

**GREEN**: Implement merge with CGWindowID-based keying

**REFACTOR**: Clean up
