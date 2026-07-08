import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("WindowMatcher Tests")
struct WindowMatcherTests {

    // MARK: - Single-Window App Matching

    @Test("Single-window app matches by bundle ID when 1 saved and 1 current")
    func singleWindowAppMatchesByBundleId() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],  // Calculator is NOT here, so it's single-window
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.calculator",
                applicationName: "Calculator",
                windowTitle: "Calculator",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 400, height: 300),
                lastSeenAt: Date()
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.apple.calculator",
                title: "Calculator",
                frame: CGRect(x: 200, y: 200, width: 400, height: 300),
                windowIdentifier: 12345,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        #expect(matches[0].saved.applicationBundleIdentifier == "com.apple.calculator")
        #expect(matches[0].current.windowIdentifier == 12345)
    }

    @Test("Single-window app matches even when titles differ")
    func singleWindowAppMatchesEvenWhenTitlesDiffer() {
        let config = AppMatchingConfig(
            multiWindowApps: [],  // Teams is NOT here, so it's single-window
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.teams",
                applicationName: "Teams",
                windowTitle: "Chat with Alice",  // Old title
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date()
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.microsoft.teams",
                title: "Meeting with Bob",  // Different title!
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        #expect(matches[0].saved.windowTitle == "Chat with Alice")
        #expect(matches[0].current.title == "Meeting with Bob")
    }

    @Test("Single-window app does NOT match when multiple current windows exist")
    func singleWindowAppDoesNotMatchWhenMultipleCurrent() {
        let config = AppMatchingConfig(
            multiWindowApps: [],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.calculator",
                applicationName: "Calculator",
                windowTitle: "Saved Window Title",  // Different from current titles
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 400, height: 300),
                lastSeenAt: Date()
            )
        ]

        // Two current windows for the same app - can't use single-window matching
        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.apple.calculator",
                title: "Current Window 1",  // Different title
                frame: CGRect(x: 200, y: 200, width: 400, height: 300),
                windowIdentifier: 11111,
                tabs: nil
            ),
            CurrentWindow(
                bundleIdentifier: "com.apple.calculator",
                title: "Current Window 2",  // Different title
                frame: CGRect(x: 300, y: 300, width: 400, height: 300),
                windowIdentifier: 22222,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should not match via single-window logic and titles are different
        #expect(matches.count == 0)
    }

    @Test("Single-window app does NOT match when multiple saved windows exist")
    func singleWindowAppDoesNotMatchWhenMultipleSaved() {
        let config = AppMatchingConfig(
            multiWindowApps: [],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        // Two saved windows for the same app
        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.calculator",
                applicationName: "Calculator",
                windowTitle: "Calculator 1",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 400, height: 300),
                lastSeenAt: Date()
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.calculator",
                applicationName: "Calculator",
                windowTitle: "Calculator 2",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 400, height: 300),
                lastSeenAt: Date()
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.apple.calculator",
                title: "Calculator",
                frame: CGRect(x: 300, y: 300, width: 400, height: 300),
                windowIdentifier: 12345,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should not match via single-window logic
        #expect(matches.count == 0)
    }

    @Test("Multi-window app does NOT use single-window matching")
    func multiWindowAppDoesNotUseSingleWindowMatching() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],  // Chrome IS a multi-window app
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Google",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date()
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "GitHub",  // Different title
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 12345,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Multi-window apps should NOT match just because there's 1:1 ratio
        // They need CGWindowID, tabs, or title match
        #expect(matches.count == 0)
    }

    // MARK: - CGWindowID Matching

    @Test("Multi-window app matches by CGWindowID when IDs match")
    func multiWindowAppMatchesByCGWindowId() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Old Tab Title",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: 12345  // Same CGWindowID
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "New Tab Title",  // Title changed
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 12345,  // Same CGWindowID!
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        #expect(matches[0].saved.windowIdentifier == 12345)
        #expect(matches[0].current.windowIdentifier == 12345)
    }

    @Test("CGWindowID matching works for multiple windows of same app")
    func cgWindowIdMatchingWorksForMultipleWindows() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Window A",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: 11111
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Window B",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: 22222
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Window B New",
                frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                windowIdentifier: 22222,
                tabs: nil
            ),
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Window A New",
                frame: CGRect(x: 400, y: 400, width: 800, height: 600),
                windowIdentifier: 11111,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 2)

        // Verify correct pairing by windowIdentifier
        let match11111 = matches.first { $0.saved.windowIdentifier == 11111 }
        let match22222 = matches.first { $0.saved.windowIdentifier == 22222 }

        #expect(match11111 != nil)
        #expect(match11111?.current.windowIdentifier == 11111)

        #expect(match22222 != nil)
        #expect(match22222?.current.windowIdentifier == 22222)
    }

    @Test("CGWindowID matching does NOT match different IDs")
    func cgWindowIdDoesNotMatchDifferentIds() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Saved Title",  // Different from current
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: 11111
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Current Title",  // Different from saved
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,  // Different CGWindowID
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should not match - different CGWindowIDs and different titles
        #expect(matches.count == 0)
    }

    @Test("CGWindowID matching ignores nil windowIdentifiers")
    func cgWindowIdMatchingIgnoresNilIds() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Saved Title",  // Different from current
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil  // No CGWindowID saved
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Current Title",  // Different from saved
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 12345,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should not match via CGWindowID (saved has nil) and titles differ
        #expect(matches.count == 0)
    }

    // MARK: - Tab-Based Matching

    @Test("Tab matching works when overlap meets threshold")
    func tabMatchingWorksWhenOverlapMeetsThreshold() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: ["com.google.Chrome"],
            tabMatchThreshold: 0.5  // 50% threshold
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Old Title",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil,  // No CGWindowID (app restarted)
                tabs: ["Gmail", "GitHub", "Reddit", "YouTube"]
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "New Title",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,  // Different CGWindowID
                tabs: ["Gmail", "GitHub", "Twitter"]  // 2 of 3 match = 67%
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
    }

    @Test("Tab matching fails when overlap below threshold")
    func tabMatchingFailsWhenOverlapBelowThreshold() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: ["com.google.Chrome"],
            tabMatchThreshold: 0.5  // 50% threshold
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Window A",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil,
                tabs: ["Gmail", "GitHub", "Reddit", "YouTube"]  // 4 tabs
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Window B",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: ["Gmail", "Twitter", "Facebook", "LinkedIn"]  // Only 1 of 4 match = 25%
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 0)
    }

    @Test("Tab matching picks best match when multiple candidates")
    func tabMatchingPicksBestMatch() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: ["com.google.Chrome"],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Work Window",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil,
                tabs: ["Gmail", "GitHub", "Jira", "Confluence"]
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Window 1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 11111,
                tabs: ["Gmail", "Twitter"]  // 1 of 2 = 50% match
            ),
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Window 2",
                frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                windowIdentifier: 22222,
                tabs: ["Gmail", "GitHub", "Jira"]  // 3 of 3 = 100% match (best!)
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        #expect(matches[0].current.windowIdentifier == 22222)  // Should pick Window 2
    }

    @Test("Tab matching only applies to tab-enabled apps")
    func tabMatchingOnlyAppliesToTabEnabledApps() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.apple.finder"],  // Finder is multi-window
            tabEnabledApps: [],  // But NOT tab-enabled
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                windowTitle: "Documents",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil,
                tabs: ["Tab1", "Tab2", "Tab3"]  // Finder doesn't have real tabs
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.apple.finder",
                title: "Downloads",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: ["Tab1", "Tab2", "Tab3"]  // Same "tabs" but shouldn't use tab matching
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should NOT match because Finder is not tab-enabled
        #expect(matches.count == 0)
    }

    @Test("Tab matching ignores windows without tabs")
    func tabMatchingIgnoresWindowsWithoutTabs() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: ["com.google.Chrome"],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Saved Title",  // Different from current
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil,
                tabs: nil  // No tabs saved
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Current Title",  // Different from saved
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: ["Gmail", "GitHub"]
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        // Should not match via tabs (saved has nil tabs) and titles differ
        #expect(matches.count == 0)
    }

    // MARK: - Title Fallback Matching

    @Test("Title fallback matches when titles are identical")
    func titleFallbackMatchesIdenticalTitles() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.microsoft.VSCode"],
            tabEnabledApps: [],  // VS Code not tab-enabled
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                applicationName: "VS Code",
                windowTitle: "main.swift — MyProject",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil  // No CGWindowID (app restarted)
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.microsoft.VSCode",
                title: "main.swift — MyProject",  // Same title
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        #expect(matches[0].saved.windowTitle == "main.swift — MyProject")
    }

    @Test("Title fallback does NOT match different titles")
    func titleFallbackDoesNotMatchDifferentTitles() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.microsoft.VSCode"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.VSCode",
                applicationName: "VS Code",
                windowTitle: "main.swift — ProjectA",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.microsoft.VSCode",
                title: "index.ts — ProjectB",  // Different title
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 0)
    }

    @Test("Title fallback matches multiple windows correctly")
    func titleFallbackMatchesMultipleWindows() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.apple.finder"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                windowTitle: "Documents",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.apple.finder",
                applicationName: "Finder",
                windowTitle: "Downloads",
                displayIdentifier: "display-1",
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: nil
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.apple.finder",
                title: "Downloads",
                frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                windowIdentifier: 11111,
                tabs: nil
            ),
            CurrentWindow(
                bundleIdentifier: "com.apple.finder",
                title: "Documents",
                frame: CGRect(x: 400, y: 400, width: 800, height: 600),
                windowIdentifier: 22222,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 2)

        // Verify correct pairing by title
        let documentsMatch = matches.first { $0.saved.windowTitle == "Documents" }
        let downloadsMatch = matches.first { $0.saved.windowTitle == "Downloads" }

        #expect(documentsMatch?.current.title == "Documents")
        #expect(downloadsMatch?.current.title == "Downloads")
    }

    @Test("Title fallback is last resort after CGWindowID and tabs")
    func titleFallbackIsLastResort() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.google.Chrome"],
            tabEnabledApps: ["com.google.Chrome"],
            tabMatchThreshold: 0.5
        )

        // Window with CGWindowID match should use that, not title
        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.google.Chrome",
                applicationName: "Chrome",
                windowTitle: "Gmail",
                displayIdentifier: "display-1",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                lastSeenAt: Date(),
                windowIdentifier: 12345,  // Has CGWindowID
                tabs: ["Gmail", "GitHub"]
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "Gmail",  // Same title
                frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                windowIdentifier: 99999,  // Different CGWindowID
                tabs: ["Twitter", "Facebook"]  // Different tabs
            ),
            CurrentWindow(
                bundleIdentifier: "com.google.Chrome",
                title: "GitHub",  // Different title
                frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                windowIdentifier: 12345,  // SAME CGWindowID!
                tabs: ["Docs", "Sheets"]
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 1)
        // Should match by CGWindowID (12345), not by title ("Gmail")
        #expect(matches[0].current.windowIdentifier == 12345)
        #expect(matches[0].current.title == "GitHub")
    }

    // MARK: - Cycle 0 Guard: stacked same-frame same-title windows

    @Test("Distinct ids pair correctly even when frame and title are identical")
    func distinctIdsPairCorrectlyWhenFrameAndTitleIdentical() {
        let config = AppMatchingConfig(
            multiWindowApps: ["com.microsoft.edgemac"],
            tabEnabledApps: [],
            tabMatchThreshold: 0.5
        )

        let sharedFrame = CGRect(x: 65, y: 51, width: 1514, height: 1049)
        let sharedTitle = "trustforge - Microsoft Edge - Trust Forge - Admin"

        let savedSnapshots = [
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: sharedTitle,
                displayIdentifier: "display-1",
                frame: sharedFrame,
                lastSeenAt: Date(),
                windowIdentifier: 252
            ),
            WindowSnapshot(
                applicationBundleIdentifier: "com.microsoft.edgemac",
                applicationName: "Microsoft Edge",
                windowTitle: sharedTitle,
                displayIdentifier: "display-1",
                frame: sharedFrame,
                lastSeenAt: Date(),
                windowIdentifier: 352
            )
        ]

        let currentWindows: [CurrentWindow] = [
            CurrentWindow(
                bundleIdentifier: "com.microsoft.edgemac",
                title: sharedTitle,
                frame: sharedFrame,
                windowIdentifier: 252,
                tabs: nil
            ),
            CurrentWindow(
                bundleIdentifier: "com.microsoft.edgemac",
                title: sharedTitle,
                frame: sharedFrame,
                windowIdentifier: 352,
                tabs: nil
            )
        ]

        let matcher = WindowMatcher(config: config)
        let matches = matcher.findMatches(saved: savedSnapshots, current: currentWindows)

        #expect(matches.count == 2)
        // Each saved id must pair with the SAME current id — no cross-pairing.
        for match in matches {
            #expect(match.saved.windowIdentifier == match.current.windowIdentifier)
            #expect(match.reason == .windowIdentifier)
        }
    }
}
