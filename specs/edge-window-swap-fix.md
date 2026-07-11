# Edge Window Swap Fix Specification

## 1. Problem Statement

When restoring from laptop-only mode to external-monitor mode, Microsoft Edge windows
are moved to the correct saved positions, but the **wrong window lands in each slot** —
the windows are swapped. Titles are correct per window, but window A ends up where
window B belonged and vice versa.

Concrete failure case: two Edge windows are both maximized (or otherwise stacked) on the
laptop screen, so they occupy the **same frame** (same position and size). One belongs on
the left external monitor, one on the right. After restore, they land on the correct
monitors but reversed.

## 2. Root Cause

Every macOS window has a stable per-session identifier, `CGWindowID`. The app uses it to
tell same-app windows apart. But it does **not** read that ID directly from each window.
Instead it *infers* the ID by correlating two separate lists by frame:

- The list that carries `CGWindowID`s (`CGWindowListCopyWindowInfo`) only says "a window
  exists at frame X."
- The list of windows the app can actually move (`AXUIElement` from the Accessibility
  API) does not carry `CGWindowID`.

To bridge them, the code matches by process ID plus frame within a **2-pixel tolerance,
first-match-wins**:

- `WindowEnumerator.swift:200-225` (`findCGWindowIdentifier`) — at save time.
- `WindowPositioner.swift:213-225` (`findCGWindowIdentifier`) — at restore time.

When two same-app windows share a frame, both correlation candidates match within
tolerance, and the assignment is decided by iteration order — which is effectively
arbitrary. The two windows therefore receive each other's `CGWindowID`. At restore,
`WindowMatcher` correctly matches by `CGWindowID` (Strategy 2), so it faithfully moves
"the window holding ID 1234" to ID 1234's saved slot — but ID 1234 was stuck on the wrong
window at save time, producing the swap.

## 3. Scope

### In scope

- Replace frame-based `CGWindowID` correlation with an **exact** lookup that asks each
  `AXUIElement` window for its own `CGWindowID` directly, at both save and restore time.

### Explicitly out of scope (do NOT touch)

- Minimized-window restore behavior, un-minimize/re-minimize ordering, position
  verification, retry loops — none of it. Minimized-window matching, positioning, and
  minimize/unminimize behavior must remain **identical to 1.0.4** (see §5).
- Cold-start / per-Space / apps-still-waking timing.
- The broad structural refactor that 1.0.5 shipped (new resolver/provider/normalization
  file hierarchy, reworked matcher/merger). This change is surgical: it edits the two ID
  lookup sites in place and adds one small C bridge.
- The pre-existing `nil == nil` element re-lookup fragility in `WindowPositioner.swift:80-82`
  (see §5.1). This change does not aggravate it and does not fix it.
- `WindowMatcher`, `WindowMerger`, `PersistenceService`, the menu, and settings are
  unchanged. In particular, no match-basis metadata is threaded through `WindowMatcher`
  (see §7 for how restore logging stays within existing data).

## 4. The Fix

macOS exposes a direct function, `_AXUIElementGetWindow(AXUIElement, CGWindowID*)`, that
returns the exact `CGWindowID` for a specific accessibility window. It is not in the public
headers, so it is reached through a tiny C bridge target. **This behavior is an empirical
macOS assumption** (see §12), not an Apple-documented contract: the symbol is exported by
the local SDK stubs but has no public header declaration. The bridge returns an `AXError`
we check, and the resolver is fail-closed on any non-success (§6).

The fix introduces a single injected seam, `WindowIdentifierResolving`, whose only job is
"return this window's exact `CGWindowID`, or `nil` if it can't be resolved." Both
frame-correlation sites are replaced by a call to this resolver. Because identity is now
read per-window rather than inferred from position, two visible windows sharing a frame
each get their own correct, distinct ID.

This removes the frame-order swap **whenever the resolver succeeds for both visible stacked
windows** — which the §10 hardware gate must confirm by observing two distinct non-nil IDs.
It is not an absolute guarantee: if resolution fails for a window (§6), it falls back to
`nil` and `WindowMatcher`'s tab/title matching, where two indistinguishable windows could
still be mismatched — the same fallback that exists today.

Once the resolver is in place, the frame-correlation helpers become dead code and are
removed:

- `WindowEnumerator`: `getCGWindowList()` and `findCGWindowIdentifier(...)`.
- `WindowPositioner`: `getCGWindowsForPid(_:)` and `findCGWindowIdentifier(...)`.

## 5. Minimized-Window Handling (save-side guard)

### The real 1.0.4 behavior

1.0.4 does **not** universally leave minimized windows alone. Matched windows are always
positioned first (`WindowPositioner.swift:88`) and only then minimized/unminimized
(`WindowPositioner.swift:92`), and a minimized window can still be matched by title or tabs
in `WindowMatcher` (Strategies 3–4). The one thing 1.0.4 reliably does is give minimized
windows **no `CGWindowID` at save time**: `WindowEnumerator.getCGWindowList()` uses
`.optionOnScreenOnly`, which excludes minimized windows, so save-side frame correlation
finds nothing and stores `nil`. That save-side `nil` is the load-bearing fact — it keeps
minimized windows out of `CGWindowID`-based matching (Strategy 2). At restore, 1.0.4's
list (`.excludeDesktopElements`, no `.optionOnScreenOnly`) *includes* minimized windows, so
they do receive real IDs on the current-window side.

### Why a naive adoption regresses, and the guard

`_AXUIElementGetWindow` returns a valid ID **even for minimized windows**. If the save side
adopted it without a guard, saved minimized windows would gain real IDs, start matching by
`CGWindowID` on restore, and get positioned while minimized (a silent no-op) then
unminimized onto the wrong screen — the exact regression that made 1.0.5 unusable.

Therefore the **save side withholds the ID for any minimized window** (`isMinimized == true
→ nil`), reproducing 1.0.4's `.optionOnScreenOnly` exclusion for the minimized case. The
**restore side applies no such guard** — it resolves the exact ID of every current window
that passes the existing title/size filters, exactly as 1.0.4's restore list already
included minimized windows. For **minimized** windows the net effect versus 1.0.4 is
**none**: save-side minimized windows stay `nil` (as before), restore-side minimized windows
get real IDs (as before, only now exact instead of frame-inferred). Visible windows change
in the intended way: exact IDs instead of frame-guessed.

### 5.2 Open question — hidden / off-Space windows at save

`.optionOnScreenOnly` in 1.0.4 excluded more than minimized windows: it also excluded
**hidden** windows (e.g. an app hidden with ⌘H) and windows on **inactive Spaces**, giving
them `nil` IDs at save. A save-side guard that keys only on `isMinimized` does **not**
reproduce that broader exclusion — such windows, if the AX layer surfaces them, would now
receive exact IDs at save instead of `nil`. This is very likely an improvement (exact
identity is strictly better), but it is a behavior change beyond "only visible windows."
**Decision (resolved): option (a) — guard on `isMinimized` only.** Hidden windows (⌘H) that
the AX layer still surfaces will now receive exact IDs at save instead of `nil`. This was
chosen deliberately: it is simpler, strictly more accurate, and lets the frame-correlation /
CG-list machinery be deleted entirely. In practice the delta is tiny — a window is only saved
if it is on the current desktop, and hidden apps' windows are off-screen — so day-to-day
behavior is unchanged. (The rejected option (b) would have added an on-screen-membership
check at the save site to replicate 1.0.4's `.optionOnScreenOnly` exclusion exactly.)

### 5.1 Out-of-scope hazard (do not fix here)

`WindowPositioner.swift:80-82` re-finds a matched window's `AXUIElement` with
`first(where: { $0.currentWindow.windowIdentifier == match.current.windowIdentifier || … })`.
Because `nil == nil` is `true` in Swift, if several current windows have `nil` IDs the
lookup can grab the wrong element. This is a **pre-existing** 1.0.4 fragility. On the resolver-**success**
path this change does **not** increase the restore-side `nil`-ID population — exact lookup is
strictly more reliable than 1.0.4's frame correlation, so the set of `nil`-ID current windows
only shrinks (fewer frame-mismatch failures; minimized windows still resolve real IDs at
restore), and the hazard's real-world trigger frequency should drop. The one case that *could*
raise the `nil` count is a widespread resolver **failure** (§6/§12), where visible windows fall
to `nil` and enter the existing title/frame fallback — the same path 1.0.4 uses for
unidentifiable windows. That is exactly what the §10 two-distinct-non-nil-IDs gate exists to
catch, so it is non-negotiable. Either way this change does not *fix* the latent hazard; fixing
it is a separate change, and the implementer must not introduce the symmetric-guard variant
that *would* systematically aggravate it.

## 6. Fail-Closed Resolution

Per project convention (no forgiving code), the resolver does not fabricate values:

- `_AXUIElementGetWindow` returns `.success` → return the `CGWindowID` as `Int`.
- Any other `AXError` → return `nil` and log the raw `AXError` value (via `os.Logger`, the
  project's logging convention). `nil` routes the window to the existing title/single-window
  fallback in `WindowMatcher`, an already-valid path for an unidentifiable window.

The minimized→`nil` decision is **not** in the resolver; it is applied by the save call site
(§5) before the resolver is consulted, so it is testable without invoking the private API.

## 7. Components

| Component | Change |
|-----------|--------|
| `Package.swift` | Add a C target `CAXWindowID`; make `WindowRestore` depend on it. |
| `Sources/CAXWindowID/include/CAXWindowID.h` | `#include <ApplicationServices/ApplicationServices.h>`, then declare the private `_AXUIElementGetWindow` and a C wrapper. Use the C type `AXUIElementRef` (not the Swift name `AXUIElement`). C has no tuples, so the wrapper returns `AXError` and writes the id through a `CGWindowID *outWindowId` out-parameter. |
| `Sources/CAXWindowID/CAXWindowID.c` | Implement the wrapper. |
| `WindowIdentifierResolving` (new protocol) | `internal`, `Sendable`. `func windowIdentifier(for element: AXUIElement) -> Int?` — pure exact-lookup seam (no `isMinimized` parameter). |
| `ExactWindowIdentifierResolver` (new, real impl) | Calls the bridge, maps `.success → Int`, else `nil` + logs raw `AXError`. Exposes an **internal** test-only initializer accepting a `@Sendable (AXUIElement) -> (AXError, CGWindowID)` backend closure so tests drive success / non-success without the OS; the default production initializer uses the C wrapper. Existing public initializers of the enumerator/positioner stay source-compatible; resolver injection is an internal overload. |
| `WindowEnumerator` (save) | Extract the per-window mapping into an **internal** pure function over internal raw-window value types; assign `isMinimized ? nil : resolver.windowIdentifier(for: element)`; delete `getCGWindowList`/`findCGWindowIdentifier`. Inject resolver (default `ExactWindowIdentifierResolver`). |
| `WindowPositioner` (restore) | Extract the `getCurrentWindows` mapping into an **internal** pure function over internal raw-window value types; assign `resolver.windowIdentifier(for: element)` for every window that passes the existing title/size filters (no minimized guard); delete `getCGWindowsForPid`/`findCGWindowIdentifier`. Inject resolver. |
| `WindowPositioner` restore logging | Per restore match, additively log the **saved `windowIdentifier` and the current `windowIdentifier`** (both already carried on `WindowMatch`) to `restore.log`. Two distinct non-nil IDs that are equal per window evidence an ID-to-ID match; no `MatchBasis` metadata and no `WindowMatcher` change is required. Resolver failures are logged by the resolver itself (§6). No behavior change. |

## 8. Data Model

No change. `WindowSnapshot.windowIdentifier: Int?` and `CurrentWindow.windowIdentifier: Int?`
keep their meaning ("the window's `CGWindowID`, or `nil` if unidentifiable; also `nil` at
save for minimized windows"). Existing saved JSON remains valid; the only difference is that
newly-saved IDs for visible windows are now exact rather than frame-inferred.

## 9. Testability and the Honest Limitation

The core guarantee — "two distinct windows sharing a frame get distinct IDs" — is a
property of `_AXUIElementGetWindow` itself, which is the OS and cannot be unit tested. What
unit tests **can** cover:

- **Resolver mapping (via the injected backend, not the OS):** a backend returning
  `.success` yields that exact ID; a backend returning any other `AXError` yields `nil` (and
  logs it). This isolates the mapping from the private call, so a green test is not a false
  green from the dummy element failing for an unrelated reason.
- **Save-side minimized guard:** given a raw window with `isMinimized == true`, the save
  assignment function returns a `nil` ID **without consulting the resolver** (assert the
  injected mock resolver is not called for it).
- **Identity comes from the resolver, not the frame:** given two raw windows with
  *identical* frames but **distinct** elements, the assignment function returns the two
  distinct resolver IDs. The two dummy `AXUIElement`s must be genuinely distinct — create
  them for **different PIDs** (e.g. `AXUIElementCreateApplication(1)` and
  `AXUIElementCreateApplication(2)`), because two elements created for the *same* PID may
  compare equal. The mock resolver maps each distinct element to its own ID by reference
  identity (do not rely on `CFEqual` meaning pointer identity); the test must fail if the
  implementation resolves element B but assigns element A's ID.

To make these testable without live windows, the per-window read at each site is split into
(a) a thin, untestable AX-reading layer that produces internal raw-window value types
`(element, title, frame, isMinimized, …)`, and (b) an **internal** pure assignment function
(visible via `@testable import WindowRestore`) that maps raw windows to
snapshots/current-windows by calling the injected resolver.

**Green unit tests are necessary but NOT sufficient.** The prior two attempts passed unit
tests and failed on real hardware. This change is not "done" until the §10 hardware check
passes.

## 10. Mandatory Hardware Verification (acceptance gate)

Must be performed from the **signed, installed `.app` bundle** (via
`./scripts/build-and-install.sh`, with Accessibility permission preserved) on the real
machine with external monitors — the raw Swift executable can give misleading AX behavior
(`CLAUDE.md`):

1. Open two Edge windows; stack them both maximized on the laptop screen (same frame).
   Note which is which (e.g. distinct sites).
2. Arrange them on the external monitors as desired (left window vs right window), let a
   save occur.
3. Return to laptop-only, then reconnect the external monitors to trigger restore.
4. **Pass criteria:** each Edge window returns to its own correct monitor — no swap.
5. Inspect `~/Library/Application Support/WindowRestore/restore.log`: the stacked Edge pair
   must show **two distinct non-nil IDs**, each matched saved-ID == current-ID — the log
   line ends with `via identifier` (not `via title-or-tab`) and shows distinct
   `savedIdentifier=`/`currentIdentifier=` values per window. (The §7 restore logging exists
   to make this observable.) A single shared or `nil` ID for the pair, or `via title-or-tab`,
   is a **failure**, even if the windows happen to land correctly.
6. **Minimize regression check:** minimize a window on the laptop, let a save occur, then
   inspect the saved `config-*.json` and confirm that window's `windowIdentifier` is `null`
   (the save-side guard held). Reconnect monitors and confirm behavior is unchanged from
   1.0.4 (the minimized window is not flung to the wrong screen). This guards against §5
   leaking.

## 11. Implementation Plan (TDD)

### Cycle 1: C bridge + resolver (mapping + fail-closed)

- **RED**: Test `ExactWindowIdentifierResolver` via its internal `@Sendable` backend closure:
  a backend returning `(.success, 4242)` yields `4242`; a backend returning `(.failure, 0)`
  yields `nil`. Fails: type does not exist.
- **GREEN**: Add the `CAXWindowID` target + wrapper (out-parameter form); implement the
  resolver (call backend → map `.success` to `Int`, else `nil`). Production init uses the C
  wrapper as the backend.
- **REFACTOR**: Tidy logging of the raw `AXError`.

### Cycle 2: Save-side assignment uses the resolver, not the frame; minimized→nil at save

- **RED**: Test `WindowEnumerator`'s internal save-assignment function: two raw windows with
  identical frames and **distinct elements (different PIDs)** receive the two distinct
  resolver IDs; a raw window with `isMinimized == true` receives `nil` and the mock resolver
  is not consulted for it. Fails: assignment still uses frame correlation.
- **GREEN**: Extract the internal raw-window type + assignment function; route through the
  injected resolver with the `isMinimized ? nil : resolve` guard at this call site.
- **REFACTOR**: Delete `getCGWindowList` and `findCGWindowIdentifier` from
  `WindowEnumerator`.

### Cycle 3: Restore-side assignment uses the resolver, not the frame (no guard)

- **RED**: Test `WindowPositioner`'s internal current-window assignment function:
  identical-frame distinct elements (different PIDs) get distinct resolver IDs; a raw window
  with `isMinimized == true` still receives its resolver ID (no guard — restore parity with
  1.0.4). Fails: still frame-correlated.
- **GREEN**: Extract the internal raw-window type + assignment function; route
  `getCurrentWindows` ID resolution through the resolver for every filtered window.
- **REFACTOR**: Delete `getCGWindowsForPid` and `findCGWindowIdentifier` from
  `WindowPositioner`; confirm both sites share one resolver type. Add the additive restore
  saved-ID/current-ID logging (§7).

### Cycle 4: Regression safety

- Run the full existing suite (`WindowMatcherTests`, `WindowMergerTests`,
  `WindowPositionerTests`, `WindowEnumeratorTests`) unchanged — they must still pass,
  proving matching/merging behavior is untouched.
- Run `swift test` and `swift build`. (This repo has no SwiftLint/SwiftFormat config or lint
  script, so the build is the static check; if a linter is later added it belongs in its own
  spec.)

## 12. Non-Goals / Risks

- **Private API (empirical)**: `_AXUIElementGetWindow` is undocumented by Apple; its symbol
  is present in the local SDK export stubs and it is widely used, but its behavior —
  including that it returns valid IDs for minimized windows — is an **empirical assumption
  verified only by the §10 hardware test**, not an Apple contract.
- **Resolver failure mode**: failure is fail-closed and non-crashing (returns `nil` → title
  fallback). It is **not** equivalent to 1.0.4 for visible windows: once frame correlation is
  removed, a widespread resolver failure would leave visible windows with `nil` IDs and only
  tab/title matching, which is a functional regression for multi-window apps whose titles
  changed or whose tabs are unavailable. A future macOS change to the private symbol is the
  realistic trigger; the §10 gate (two distinct non-nil IDs) is what catches it early.
- This spec does **not** fix minimized-window placement, cold-start timing, or the §5.1
  `nil == nil` re-lookup fragility. Those remain known, separate issues.

## 13. Acceptance Criteria

- All new and existing unit tests pass; `swift test` and `swift build` clean.
- Frame-correlation ID code is fully removed from both sites.
- Minimized windows still resolve to `nil` ID **at save**; restore-side resolution is
  applied to all filtered windows (parity with 1.0.4).
- §10 hardware verification passes, including the two-distinct-non-nil-IDs check, the saved
  `windowIdentifier == null` check for the minimized window, and the minimize regression
  check.
