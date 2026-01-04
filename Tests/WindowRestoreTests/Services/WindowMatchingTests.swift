import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("Window Matching Tests")
struct WindowMatchingTests {

    // MARK: - Title Matching (existing behavior)

    @Test("Matches window by exact title")
    func matchesByExactTitle() {
        let savedSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "GitHub - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let currentWindow = MockCurrentWindow(
            title: "GitHub - Edge",
            frame: CGRect(x: 500, y: 500, width: 800, height: 600)  // Different position
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [savedSnapshot],
            excludedIndices: []
        )

        #expect(match != nil)
        #expect(match?.1.windowTitle == "GitHub - Edge")
    }

    // MARK: - Position Fallback Matching (new behavior)

    @Test("Falls back to position matching when title doesn't match but same app and within threshold")
    func fallsBackToPositionMatching() {
        let savedSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "GitHub - Edge",  // Saved with this tab active
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let currentWindow = MockCurrentWindow(
            title: "Reddit - Edge",  // Different tab now active
            frame: CGRect(x: 110, y: 105, width: 800, height: 600),  // Slightly moved (within 200px)
            bundleIdentifier: "com.microsoft.edgemac"
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [savedSnapshot],
            excludedIndices: []
        )

        #expect(match != nil)
        #expect(match?.1.windowTitle == "GitHub - Edge")
    }

    @Test("Does not match by position if distance exceeds threshold")
    func doesNotMatchBeyondThreshold() {
        let savedSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "GitHub - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let currentWindow = MockCurrentWindow(
            title: "Reddit - Edge",  // Different title
            frame: CGRect(x: 500, y: 500, width: 800, height: 600),  // Far away (566px)
            bundleIdentifier: "com.microsoft.edgemac"
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [savedSnapshot],
            excludedIndices: []
        )

        #expect(match == nil)
    }

    @Test("Does not match by position if different app")
    func doesNotMatchDifferentApp() {
        let savedSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "GitHub - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let currentWindow = MockCurrentWindow(
            title: "Some Window",
            frame: CGRect(x: 105, y: 105, width: 800, height: 600),  // Close position
            bundleIdentifier: "com.apple.Safari"  // Different app
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [savedSnapshot],
            excludedIndices: []
        )

        #expect(match == nil)
    }

    @Test("Title match takes priority over position match")
    func titleMatchTakesPriority() {
        let positionMatchSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "Other Tab - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)  // Closer position
        )

        let titleMatchSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "GitHub - Edge",  // Exact title match
            displayIdentifier: "display-1",
            frame: CGRect(x: 1000, y: 1000, width: 800, height: 600)  // Far away
        )

        let currentWindow = MockCurrentWindow(
            title: "GitHub - Edge",
            frame: CGRect(x: 105, y: 105, width: 800, height: 600),
            bundleIdentifier: "com.microsoft.edgemac"
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [positionMatchSnapshot, titleMatchSnapshot],
            excludedIndices: []
        )

        #expect(match != nil)
        #expect(match?.1.windowTitle == "GitHub - Edge")  // Title match wins
    }

    @Test("Matches closest position when multiple windows from same app")
    func matchesClosestPosition() {
        let farSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "Tab 1 - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        let closeSnapshot = WindowSnapshot(
            applicationBundleIdentifier: "com.microsoft.edgemac",
            applicationName: "Microsoft Edge",
            windowTitle: "Tab 2 - Edge",
            displayIdentifier: "display-1",
            frame: CGRect(x: 500, y: 500, width: 800, height: 600)
        )

        let currentWindow = MockCurrentWindow(
            title: "Different Tab - Edge",  // No title match
            frame: CGRect(x: 510, y: 505, width: 800, height: 600),  // Closer to closeSnapshot
            bundleIdentifier: "com.microsoft.edgemac"
        )

        let matcher = WindowMatcher(distanceThreshold: 200)
        let match = matcher.findMatch(
            for: currentWindow,
            in: [farSnapshot, closeSnapshot],
            excludedIndices: []
        )

        #expect(match != nil)
        #expect(match?.1.windowTitle == "Tab 2 - Edge")  // Closer one wins
    }
}

// MARK: - Test Helpers

struct MockCurrentWindow: CurrentWindowInfo {
    let title: String
    let frame: CGRect
    var bundleIdentifier: String = ""
}
