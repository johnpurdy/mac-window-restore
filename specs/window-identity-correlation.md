# Window Identity Correlation Fix Specification

## 1. Problem Statement

When restoring windows after connecting external monitors (laptop mode → external
monitor mode), Microsoft Edge windows are moved to the correct saved **positions**,
but the **wrong window** is placed in each position. The windows are shuffled — often
a clean two-way swap.

Observed in the restore log (`~/Library/Application Support/WindowRestore/restore.log`),
where the format is `Restoring: "<saved window>" matched to "<current window>"`:

```
Restoring: "Board · TrustForge - Microsoft Edge - MacGregor"       matched to "Users - Microsoft Azure - Microsoft Edge - Trustforge - Test"
Restoring: "Users - Microsoft Azure - Microsoft Edge - Trustforge" matched to "Board · TrustForge - Microsoft Edge - MacGregor"
```

The live "Users – Azure" window is sent to where "Board · TrustForge" was saved, and
vice-versa. Multiple Edge windows are cross-matched this way on every restore.

## 2. Root Cause Analysis

The app moves windows through the Accessibility API (`AXUIElement`) but stores window
identity as a **CGWindowID**. macOS provides no shared identifier between these two
APIs, so the code infers the link by **matching window frames within a 2-pixel
tolerance**:

- `WindowEnumerator.findCGWindowIdentifier(pid:frame:cgWindows:excludedIds:)`
- `WindowPositioner.findCGWindowIdentifier(frame:cgWindows:excludedIds:)`

This inference is ambiguous whenever multiple windows of one app share the same
frame — which is exactly the laptop-mode state, where Edge windows are maximized and
stacked at the same position.

Evidence from the user's saved laptop configuration
(`config-e4f7e85ab5e7abfc.json`, single Built-in Retina Display; a runtime file under
`~/Library/Application Support/WindowRestore/`, not tracked in the repo):

- Nearly every Edge window is stored at the identical frame `(65,51 1514×1049)`.
- A large fraction have `windowIdentifier = null` — the frame match found no unique
  candidate.
- Several windows share the identical title
  `"trustforge - Microsoft Edge - Trust Forge - Admin"`.

Failure sequence for laptop → external restore:

1. Live Edge windows are stacked at the same laptop frame.
2. `WindowPositioner.getCurrentWindows` tries to attach a CGWindowID to each live
   `AXUIElement` by frame. With N windows at one frame the assignment is arbitrary:
   each `AXUIElement` grabs the *next available* CGWindowID at that frame in a
   different iteration order, so IDs are **permuted** across windows (or dropped to
   `nil`).
3. `WindowMatcher` matches the external config's correct, distinct CGWindowIDs against
   these permuted current IDs → a wrong one-to-one pairing → the swaps in the log.
4. Where the current ID is `nil`, matching falls back to tab/title, which also fails
   because many Edge windows share a title.

### 2.1 Secondary defect: restore re-find treats `nil == nil` as a match

Even after identifiers are correct, a second bug in the restore path defeats the
"missing id is safer than a wrong id" goal. After `WindowMatcher` picks a match,
`WindowPositioner.restoreWindows` re-locates the AX element to move with
(`Sources/WindowRestore/Services/WindowPositioner.swift:79`):

```swift
currentWindows.first(where: {
    $0.currentWindow.windowIdentifier == match.current.windowIdentifier ||
    ($0.currentWindow.title == match.current.title && $0.currentWindow.frame == match.current.frame)
})
```

When `match.current.windowIdentifier` is `nil`, Swift optional equality makes
`nil == nil` **true**, so the *first* current window with a `nil` id is selected —
not necessarily the window the matcher chose by tab/title. With several stacked
same-title windows (identical title **and** frame), the second clause collides too.
The result: the wrong window is still moved whenever the resolver returns `nil` for
more than one window. Fixing identifier assignment (Section 4) is therefore necessary
but **not sufficient**; the restore match must carry the exact selected window through
to positioning (Section 4.5).

Positions are correct because frames are stored correctly. Only the
**window ↔ identity** mapping is wrong.

## 3. Goals and Non-Goals

### Goals

- Attach the **exact** CGWindowID to each `AXUIElement`, independent of window frame,
  so stacked same-frame windows are never confused.
- Ensure the restore path moves the **exact** window the matcher selected, even when
  the identifier is `nil` and matching fell back to tab/title.
- Eliminate the swap/mismatch on laptop → external restore while Edge remains running.
- Prefer a **missing** identifier over a **wrong** identifier: a `nil` id falls back to
  tab/title matching; a wrong id causes a confident mismatch.

### Non-Goals

- Matching windows across a full **quit-and-relaunch** of an app. CGWindowIDs reset
  when the app process restarts; that case still falls back to tab/title matching and
  is out of scope here.
- Changing the tab-overlap / title matching *strategies* in `WindowMatcher` /
  `WindowMerger`. Their strategy order is unchanged; this spec only feeds them correct
  identifiers, preserves the selected current window through positioning, and adds a
  match-reason label for observability.
- Changing persistence format, display identification, or restore triggers.

## 4. Design

### 4.1 Use the exact Accessibility → CGWindowID API

macOS exposes a private, long-stable function that returns the CGWindowID for a given
accessibility window element:

```
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier)
```

This is the correlation method used by established window managers (yabai, Amethyst,
etc.). It returns each window's true, unique CGWindowID regardless of position, so
stacking no longer causes collisions.

**Verification status (local SDK, as of this spec).** The private symbol
`__AXUIElementGetWindow` is exported by the local SDK's `ApplicationServices.tbd` /
`HIServices.tbd`, but the public `AXUIElement.h` header declares only public functions
(e.g. `AXUIElementCopyAttributeValue`). Apple's public documentation does **not**
document `_AXUIElementGetWindow`, so its long-term semantic stability is an inference,
not a documented guarantee — hence the isolation and `nil`-on-failure fallback below.

**Trade-off:** the function is undocumented private API. It has been stable across many
macOS releases; for a personal Developer-ID-signed utility this is an acceptable risk.
The dependency is isolated behind a single protocol (§4.3) so it can be swapped or
mocked.

### 4.2 Expose the symbol via a small C shim target

Add a C target to `Package.swift` that declares the prototype and re-exports it, rather
than relying on `@_silgen_name`. `Package.swift` today has only the `WindowRestore` and
`WindowRestoreTests` targets and `KeyboardShortcuts` (pinned at 2.4.0 in
`Package.resolved`) as its sole dependency; this adds one C target.

- New target `CAXWindowID` (a `.target` with a public header):
  - **Public header** `include/CAXWindowID.h`:
    - `#include <ApplicationServices/ApplicationServices.h>` (for `AXUIElementRef`,
      `AXError`, `CGWindowID`).
    - Declares the public wrapper only:
      `AXError CAXGetWindowID(AXUIElementRef element, CGWindowID *outID);`
  - **Implementation** `CAXWindowID.c`:
    - Declares the private symbol locally so it compiles under modern Clang (the public
      header does not provide a prototype):
      `extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);`
    - Implements `CAXGetWindowID` as a thin pass-through to `_AXUIElementGetWindow`.
- `WindowRestore` target gains `CAXWindowID` as a dependency.
- The `CAXWindowID` target declares `linkerSettings: [.linkedFramework("ApplicationServices")]`
  **from the start** (not as an after-failure fallback). The `_AXUIElementGetWindow`
  symbol is exported by `ApplicationServices` / `HIServices`; linking the framework
  explicitly documents the dependency and keeps Cycle 1 from depending on transitive
  Swift imports resolving the symbol.

The private symbol and its prototype live only in the `CAXWindowID` target; no other
Swift or C code references `_AXUIElementGetWindow` (no `@_silgen_name` anywhere).

### 4.3 Introduce a resolver protocol with dependency injection

```swift
public protocol WindowIdentifierResolving: Sendable {
    /// Returns the exact CGWindowID for an accessibility window element,
    /// or nil if it cannot be determined.
    func windowIdentifier(for element: AXUIElement) -> Int?
}
```

- `AXWindowIdentifierResolver` — production implementation calling `CAXGetWindowID`,
  returning `nil` on any non-`.success` result. `CGWindowID` is `UInt32`; the resolver
  explicitly casts the successful value to `Int` to satisfy the protocol (the stored
  `windowIdentifier` on `WindowSnapshot` / `CurrentWindow` is `Int?`).
- **Null-id guard.** Even on a nominal `.success`, a returned `kCGNullWindowID` (`0`) is
  treated as `nil` (and logged as a resolver failure), never stored as identifier `0` —
  otherwise "missing is safer than wrong" would be violated. The `AXError`+`CGWindowID`
  → `Int?` conversion is a pure function and is unit-tested directly (success→Int,
  non-success→nil, success-with-0→nil); only the raw `CAXGetWindowID` call itself is
  manual/integration-only.
- **Concurrency.** `AXUIElement` is a CoreFoundation type that is not `Sendable`, yet the
  protocol is `Sendable`. Silence Swift 6 strict-concurrency without weakening safety by
  either isolating the resolver/providers to `@MainActor` (AX calls prefer the main
  thread anyway) or applying `@preconcurrency import ApplicationServices`. Pick one and
  state it in the implementation; do not suppress the warning ad hoc.
- The resolver is owned by the **providers** that touch `AXUIElement` directly
  (§4.4, §4.5), not by `WindowEnumerator`. See §4.6 for the exact dependency graph.

### 4.4 Save path: a raw-window seam (provider resolves ids; enumerator owns filters)

`WindowEnumerator` currently owns display lookup **plus** AX enumeration **plus** tab
extraction **plus** the persistence filters, and guesses IDs inline. Split the
AX-touching work behind a protocol so identifier resolution has a single owner and the
mapping/filtering logic is testable with fakes:

```swift
public struct RawWindow: Sendable {
    public let bundleIdentifier: String
    public let applicationName: String
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let windowIdentifier: Int?   // resolved via WindowIdentifierResolving
    public let tabs: [String]?
}

public protocol RawWindowProviding: Sendable {
    func rawWindows() -> [RawWindow]
}
```

`RawWindow` is a pure value type and **must not** hold an `AXUIElement` (which is not
`Sendable`); the save path never needs to move windows, only describe them.

**Ownership split (one owner per concern).**

- The production `RawWindowProvider` performs the system glue: AX enumeration of regular
  apps' windows, resolver lookup for each `windowIdentifier` (calls
  `WindowIdentifierResolving`), and tab extraction **only** for tab-enabled browser
  bundle IDs (`AppMatchingConfig.isTabEnabledApp`). It applies the duplicate-id
  normalization in §4.7. It does **not** apply the empty-title / zero-size filters —
  those are a persistence-boundary concern, not an AX concern.
- `WindowEnumerator.enumerateWindows()` owns the **filters** and the mapping: it drops
  empty-title and zero-size raw windows (the exact rule that lives in
  `WindowEnumerator` today, `Sources/WindowRestore/Services/WindowEnumerator.swift:47`),
  assigns each surviving raw window to a display (`findDisplayForWindow`), and builds
  `WindowSnapshot`s — carrying `windowIdentifier` and `tabs` through verbatim. It no
  longer touches AX or CGWindowList.

This split makes the Cycle 2 test coherent: a fake `RawWindowProviding` returns
empty-title / zero-size / same-frame / `nil`-id windows, and the assertion is about what
`WindowEnumerator` (the filter owner) keeps and maps.

### 4.5 Restore path: preserve the AX element and the matcher's choice

The same frame-based guessing exists a second time in
`WindowPositioner.getCurrentWindows`, and the fragile `nil == nil` re-find (§2.1) lives
here too. Fix both without breaking `WindowMatcher`'s `Sendable` conformance.

**Keep `WindowMatcher` `Sendable`; index into a local record array.** `AXUIElement` is
not `Sendable`, and `WindowMatcher` is declared `Sendable`
(`Sources/WindowRestore/Services/WindowMatcher.swift:39`), so the matcher must **not**
accept or return any type holding an `AXUIElement`. Instead:

```swift
public struct CurrentWindowRecord {           // not Sendable: holds an AXUIElement
    public let element: AXUIElement
    public let currentWindow: CurrentWindow    // Sendable; includes resolver-provided id
}

public protocol CurrentWindowProviding {
    func currentWindows(forBundleIdentifiers bundleIdentifiers: Set<String>) -> [CurrentWindowRecord]
}

public enum WindowMatchReason: Sendable {      // for observability, not new strategy
    case windowIdentifier, tabs, title, singleWindow
}
```

- The production `CurrentWindowProvider` performs AX enumeration for the given bundle
  IDs, resolves each `windowIdentifier` via `WindowIdentifierResolving`, extracts tabs
  for tab-enabled apps, and applies the §4.7 duplicate-id normalization. It replaces
  `WindowPositioner.getCurrentWindows` and the frame-based `findCGWindowIdentifier`.
  It also preserves the pre-existing restore-side skip of **zero-size** current windows
  (a zero-size AX element has no restorable geometry and would only waste a match slot).
  This is distinct from the save-side persistence filters in §4.4 — it is a "not
  restorable" skip on live windows, not a persistence-boundary filter.
- `WindowMatcher.findMatches` continues to take `[WindowSnapshot]` and `[CurrentWindow]`
  (both `Sendable`) and returns matches that carry the **`currentIndex`** (offset into
  the `[CurrentWindow]` it was given), the `savedIndex`, and the `WindowMatchReason`.
  `WindowMatcher` already tracks these offsets internally via `enumerated()`.
- `WindowPositioner` holds the `[CurrentWindowRecord]` locally, calls the matcher with
  `records.map(\.currentWindow)`, and uses `match.currentIndex` for O(1) retrieval of
  the exact `AXUIElement` to move. No post-match search by id/title/frame; optional
  identifiers are never compared with `==` again.

**Testable restore seam (spy).** `WindowPositioner.restoreWindows` currently calls
private AX-mutating helpers directly, so a fake provider alone cannot prove *which*
element was moved. Split restore into a pure planning step and an effect step:

- A pure function builds an ordered restore **plan**:
  `[(snapshot: WindowSnapshot, record: CurrentWindowRecord, reason: WindowMatchReason)]`.
- An injected effect seam applies the plan. Its methods return a **result type**, not a
  bare `Bool`, so the existing per-axis diagnostics (`"Position: <code>, Size: <code>"`
  from `WindowPositioner.positionWindow`) are preserved in `WindowRestoreResult.error`:
  ```swift
  public struct ElementPositionResult: Sendable {   // preserves AX error codes
      public let positioned: Bool
      public let positionError: AXError?
      public let sizeError: AXError?
  }
  public protocol WindowElementPositioning {         // default impl wraps the AX calls
      func position(_ element: AXUIElement, to frame: CGRect) -> ElementPositionResult
      func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool
  }
  ```
- The Cycle 3 RED injects a spy `WindowElementPositioning` and asserts the plan/effects
  targeted the matcher-selected record's element — deterministic, no live AX.
- **Test-hang guard.** `WindowPositioner.retryMinimizeWithVerification` sleeps
  `0.5s × up to 10` retries when minimize verification fails. So a unit test's spy must
  either return the verified minimized state (so the retry loop is skipped) or the retry
  delay must be injectable; otherwise Cycle 3 tests would block ~5s. State which approach
  the implementation takes.

### 4.6 Dependency graph (explicit)

- `WindowEnumerator` ← `DisplayInfoProviding` + `RawWindowProviding`. Owns empty-title /
  zero-size filtering and display assignment. No resolver (it no longer touches AX).
- `RawWindowProvider` (production) ← `WindowIdentifierResolving` + `AppMatchingConfig` +
  a tab extractor.
- `CurrentWindowProvider` (production) ← `WindowIdentifierResolving` + `AppMatchingConfig`
  + a tab extractor.
- `WindowMatcher` — stays `Sendable`; operates only on `[WindowSnapshot]` /
  `[CurrentWindow]`; returns `savedIndex` / `currentIndex` / `reason`.
- `WindowPositioner` ← `CurrentWindowProviding` + `WindowElementPositioning`
  (+ `AppMatchingConfig` for the matcher). Resolution happens inside the provider.

### 4.7 Remove frame-based ID guessing; normalize duplicate ids

- Delete `findCGWindowIdentifier(...)`, `getCGWindowList`, `getCGWindowsForPid`, and the
  `usedCGWindowIds` bookkeeping from both `WindowEnumerator` and `WindowPositioner`.
- On resolver failure, store `windowIdentifier = nil` (never a frame-based guess).
- **Duplicate-id normalization (pure helper, both providers).** If a single
  enumeration/resolution pass yields the **same non-nil** id for two or more windows,
  that is a resolver malfunction, not a valid state. After logging the duplicate
  (count + titles), **every** window sharing that id is set to `windowIdentifier = nil`,
  so those windows fall back to tab/title matching rather than being confidently
  mismatched. Logging alone is insufficient — the corrupt id must be neutralized, because
  `WindowMatcher`'s `currentByWindowId` map and `WindowMerger`'s id-first strategy would
  otherwise make an arbitrary confident match on it.

  This normalization is a **pure, order-preserving function** shared by both providers,
  extracted so it is unit-testable **without live AX**: it maps an ordered list of
  `(identifier, ...)` values to the same list with duplicated non-nil identifiers set to
  `nil`, elements and order unchanged. Signature shape:
  `normalizeDuplicateIdentifiers([WindowSnapshot]) -> [WindowSnapshot]` for the save path
  and an equivalent over `CurrentWindow` (inside `CurrentWindowRecord`) for restore. The
  providers call it just before returning; the AX-touching part stays glue and the
  neutralization logic is tested directly.

### 4.8 Affected files

| File | Change |
|------|--------|
| `Package.swift` | Add `CAXWindowID` C target; add as dependency of `WindowRestore` |
| `Sources/CAXWindowID/include/CAXWindowID.h` | New — public wrapper prototype + ApplicationServices include |
| `Sources/CAXWindowID/CAXWindowID.c` | New — private extern + `CAXGetWindowID` wrapper |
| `Sources/WindowRestore/Services/WindowIdentifierResolver.swift` | New — protocol + AX impl (UInt32→Int cast, null-id guard, pure conversion) |
| `Sources/WindowRestore/Services/WindowIdentifierNormalization.swift` | New — pure `normalizeDuplicateIdentifiers` helper shared by both providers |
| `Sources/WindowRestore/Services/RawWindowProvider.swift` | New — `RawWindow` + protocol + AX impl (resolver + tabs; calls normalize helper) |
| `Sources/WindowRestore/Services/CurrentWindowProvider.swift` | New — `CurrentWindowRecord` + protocol + AX impl (resolver + tabs; calls normalize helper) |
| `Sources/WindowRestore/Services/WindowEnumerator.swift` | Consume `RawWindowProviding`; own empty-title/zero-size filters + display mapping; drop AX/frame guessing |
| `Sources/WindowRestore/Services/WindowMatcher.swift` | Return `savedIndex` / `currentIndex` / `WindowMatchReason`; stay `Sendable` (value types only) |
| `Sources/WindowRestore/Services/WindowPositioner.swift` | Consume `CurrentWindowProviding` + injected `WindowElementPositioning` (result type preserves AX error codes); plan then apply; index to matched element; delete `nil==nil` re-find and frame guessing |

## 5. Behavioral Contract (Non-Negotiable Invariants)

- Two windows of the same app at the **identical frame** with distinct real CGWindowIDs
  must receive their **own** distinct identifiers.
- Frame matching is **never** used to fabricate or reuse a CGWindowID after this change.
- Resolver failure, a returned null window id (`kCGNullWindowID` / `0`), or a duplicate
  non-nil id all degrade to `nil`; no incorrect id is ever stored.
- Duplicate **non-nil** ids within one enumeration are **mapped to `nil`** (after
  logging) and never used for id matching in that pass.
- Optional identifiers are **never** treated as equal when both are `nil` during restore
  element selection.
- The current window selected by the matcher is the **same** window whose AX element is
  moved — via `currentIndex`, no post-match re-lookup.
- `WindowMatcher` stays `Sendable`: it never accepts or returns a type containing an
  `AXUIElement`.
- The private API / resolver is introduced **before** the provider refactors, so the
  build compiles at every cycle (no forward dependency).
- Empty-title and zero-size filtering has exactly **one** owner (`WindowEnumerator`) with
  deterministic tests there.
- Existing persistence stays backward compatible: missing or `null` `windowIdentifier`
  still decodes as `nil`.
- Browser-only tab extraction is preserved.
- The private API stays isolated behind one C target / resolver (no `@_silgen_name`).
- Restore logs include saved/current `windowIdentifier` and the actual
  `WindowMatchReason`, not only titles, and are **written to the persistent
  `restore.log`** so verification (§9) can read them.
- The effect seam preserves AX position/size error codes (no bare `Bool`).
- `WindowMatcher` / `WindowMerger` strategy order is unchanged.

## 6. Test Strategy

| Layer | Testability | Approach |
|-------|-------------|----------|
| `WindowMatcher` / `WindowMerger` given correct ids | Unit (regression guard) | Same-frame + same-title, distinct ids → correct pairing, no swap. Expected to pass on current code |
| Restore element selection under `nil` ids | Unit (real RED) | Two current records, both `nil` id, matched by title/tab → the *matcher-selected* record's element reaches the spy positioner |
| Save-path mapping/filters (`WindowEnumerator` + fake `RawWindowProviding`) | Unit | Same-frame distinct ids pass through; `nil` stays `nil`; empty-title / zero-size dropped |
| Duplicate-id normalization (pure helper) | Unit | Directly on the pure function: no-dups pass through unchanged; duplicate non-nil ids all → `nil`; existing `nil` stays `nil`; order/elements preserved |
| Resolver id conversion (`AXError`+`CGWindowID` → `Int?`) | Unit | Pure conversion: success→Int; non-success→nil; success-with-`0`→nil |
| Resolver ↔ `_AXUIElementGetWindow` C call | Manual/integration | Cannot unit test without a live AX window; verify via §9 and logging |

Note: the current `WindowEnumeratorTests` and `WindowPositionerTests` exercise **mock**
`WindowEnumerating` / `WindowPositioning` implementations, not the production types. The
new seams (`RawWindowProviding`, `CurrentWindowProviding`, `WindowElementPositioning`)
are what make the production mapping/selection logic unit-testable for the first time.

## 7. TDD Implementation Cycles

Ordered bottom-up so the build compiles at every step (no forward dependency on the
resolver).

### Cycle 0 (preflight guards — expected GREEN)

Characterize existing correct behavior; permanent regression guards, not RED drivers.
If either fails, stop and fix that first.

- `WindowMatcherTests`: two saved + two current Edge windows, identical frame
  `(65,51 1514×1049)` and identical title, distinct ids `252` / `352` → each saved
  matches the current with the **same** id, no cross-pairing.
- `WindowMergerTests`: existing + current, identical frames/titles, distinct ids,
  `displayConfigChanged: false` → two merged windows, in-place replacement by id, no
  duplicates, no swap.

### Cycle 1: System glue (infra; one pure RED for id conversion)

- Add the `CAXWindowID` C target and header/impl (§4.2), with
  `linkerSettings: [.linkedFramework("ApplicationServices")]` from the start.
- Add `WindowIdentifierResolving` + `AXWindowIdentifierResolver` (UInt32→Int cast),
  choosing the concurrency approach (`@MainActor` or `@preconcurrency`, §4.3).
- **RED (pure):** the `AXError`+`CGWindowID` → `Int?` conversion — success→Int,
  non-success→nil, and success-with-`kCGNullWindowID` → nil. This is testable without
  live AX; only the raw `CAXGetWindowID` call stays manual.
- Nothing else consumes the resolver yet; it exists so later cycles compile against a
  real resolver and its default initializers.

### Cycle 2: Save path (seam + filters + duplicate-id normalize)

**RED** — `Tests/WindowRestoreTests/Services/WindowEnumeratorTests.swift`
- Fake `RawWindowProviding` returns: two same-frame windows with ids `252` / `352`;
  one window with `windowIdentifier: nil`; one empty-title window; one zero-size window.
- Expected: snapshots carry `252` and `352` verbatim; the `nil` stays `nil`; the
  empty-title and zero-size windows are **absent** (dropped by `WindowEnumerator`).
- Cannot be written against the current inline implementation → drives the seam.

Also add a **pure** duplicate-id normalization test (§4.7 helper), no fake AX needed:
two entries with the same non-nil id both become `nil`; a unique id and an existing
`nil` are untouched; order preserved.

**GREEN** — add `RawWindow` + `RawWindowProviding` + the pure
`normalizeDuplicateIdentifiers` helper; refactor `WindowEnumerator.enumerateWindows()`
to consume the provider, own the empty-title / zero-size filters, and map to snapshots;
production `RawWindowProvider` owns AX enumeration, resolver lookup, tab extraction, and
calls the normalization helper before returning.

**REFACTOR** — delete `findCGWindowIdentifier` / `getCGWindowList` / `usedCGWindowIds`
from `WindowEnumerator`.

### Cycle 3: Restore path (the real RED — nil-id selection + spy)

**RED** — `Tests/WindowRestoreTests/Services/WindowPositionerTests.swift`
- Fake `CurrentWindowProviding` returns two `CurrentWindowRecord`s for one bundle, both
  with `windowIdentifier == nil`, distinguishable only by title/tabs, bound to two
  distinct sentinel elements.
- Saved snapshots select the *second* record by title/tab.
- Inject a spy `WindowElementPositioning`; assert the element it was asked to position is
  the **second** record's element. Against the current `nil == nil` re-find this fails.

**GREEN** — introduce `CurrentWindowRecord` / `CurrentWindowProviding`,
`WindowMatchReason`, and the `WindowElementPositioning` seam; have `WindowMatcher` return
`savedIndex` / `currentIndex` / `reason`; build the restore plan and apply it via the
seam using `currentIndex`; delete the optional-id re-find.

**REFACTOR** — remove `getCurrentWindows` / frame-guessing from `WindowPositioner`; apply
duplicate-id normalization in `CurrentWindowProvider`.

### Cycle 4: Observability (match reasons + id logging)

- Save time: per-save aggregate — windows resolved, count with `nil` id, any duplicate
  non-nil id (with titles). Per-window resolved ids at debug level.
- Restore time: add saved/current `windowIdentifier` and `WindowMatchReason` to each
  `Restoring:` line **written to `restore.log`** (via the existing info-level
  `log(_:)` helper, so §9 can read them), plus a per-restore aggregate of matches by id
  vs tabs vs title vs unmatched (unmatched = both unmatched-saved and unmatched-current
  counts), driven by the reason the matcher already returns (no duplicated matching
  logic).

### Cycle 5: Production glue verification (manual/integration)

Wire production providers/resolver into `AppDelegate`'s default construction, build the
signed app, and verify by §9.

## 8. Observability

- **Save time:** log a per-save aggregate — number of windows resolved, number with
  `nil` id, and any duplicate non-nil id (with titles). Per-window resolved ids at debug
  level only.
- **Restore time:** the current restore log records only matched titles
  (`Sources/WindowRestore/Services/WindowPositioner.swift:86`), which is ambiguous when
  Edge windows share a title. Add the saved and current `windowIdentifier` and the
  `WindowMatchReason` to each `Restoring:` line, plus a per-restore aggregate. **These
  fields must be written to the persistent `restore.log` file** (via the existing
  `WindowPositioner.log(_:)` helper, which writes at info level to both unified logging
  and `restore.log`) — not emitted as unified-log-only debug output — because §9's manual
  verification inspects `restore.log` for exactly these fields. Keep noisy per-window
  *save*-time resolver details at debug level if desired; the *restore* evidence must be
  in the file. Define the aggregate's `unmatched` explicitly: report **both** the count
  of saved snapshots with no current match and current windows with no saved match.

## 9. Manual Verification

**Precondition — clear stale data first.** Save *merges* into the existing config rather
than replacing it (`AppDelegate.mergeWindows` → `WindowMerger`, which appends current
windows, preserves unmatched non-stale existing windows, and treats same-config non-nil
ids as authoritative). So a verification Save over a stale config would leave old
permuted records in place. Before step 2, perform the §10 cleanup for the laptop **and**
external configs (delete the target `config-*.json` files) so each Save below creates a
**fresh** config.

1. Build and install the signed app (`./scripts/build-and-install.sh`).
2. In laptop mode with several Edge windows stacked/maximized, trigger Save.
3. Inspect the current laptop config JSON:
   - All **non-nil** Edge `windowIdentifier`s are **distinct** (no collisions).
   - Any `nil` id must be explained by a corresponding resolver-failure or
     duplicate-normalization log line; a `nil` should be rare, not the norm it is today.
4. Arrange Edge windows across the external monitors and Save so the **external-monitor**
   configuration is rebuilt with correct ids. (Restore-on-connect reads the *external*
   config via `RestoreCoordinator`, so that config — not the laptop one — governs the
   reported bug.)
5. Unplug and replug the external monitors. Confirm in `restore.log`, **using the logged
   saved/current identifiers and match reason** (not title equality alone, since Edge
   titles collide):
   - Each restored window's non-nil saved id equals its current id, and the match reason
     is `windowIdentifier`.
   - The per-restore aggregate shows matches were made by id, with no swaps.

## 10. Rollout / Data Migration

Existing saved configurations already contain `null` or permuted identifiers from the
old frame-based logic, so stale data must be rebuilt for **every** display configuration
used for restore — not just the laptop one.

**Do not use "Clear All Window Positions…" blindly.** That menu action calls
`PersistenceService.deleteAllConfigurations()`
(`Sources/WindowRestore/App/AppDelegate.swift:687`), which deletes **every** `.json` in
`~/Library/Application Support/WindowRestore/` — including
`app-matching-config.json`, the user's app-matching configuration
(`Sources/WindowRestore/Services/AppMatchingConfig.swift:51`,
`Sources/WindowRestore/Services/PersistenceService.swift:66`). Prefer:

- Delete only the display-configuration files — the `config-*.json` files named by
  `DisplayIdentifier.generateConfigurationIdentifier` — leaving `app-matching-config.json`
  intact; **or** back up `app-matching-config.json` before using the menu and restore it
  after.
- Then re-save each desired arrangement (laptop mode and each external-monitor layout,
  by triggering Save) so every `config-*.json` is regenerated with correct ids.

(Optional, separate cleanup outside this spec: scope `deleteAllConfigurations()` to
`config-*.json` only so the menu can no longer delete `app-matching-config.json`.)

No automatic migration is required. Legacy `null` identifiers remain safe (they degrade
to tab/title matching), but leaving old *permuted* non-nil ids in a config would
reproduce the swap, so a rebuild is required, not optional.

## 11. Risks

- **Private API removal by Apple.** `_AXUIElementGetWindow` could change or disappear in
  a future macOS release. Isolated behind `WindowIdentifierResolving` and the
  `CAXWindowID` target; a failure returns `nil` and degrades to tab/title matching
  rather than crashing.
- **App relaunch across save/restore.** CGWindowIDs reset when the app process restarts;
  identity then depends on tab/title matching. Unchanged by this fix and out of scope.
