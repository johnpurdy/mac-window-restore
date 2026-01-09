import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("RestoreCoordinator Tests")
struct RestoreCoordinatorTests {

    @Test("RestoreCoordinator restores windows from saved configuration")
    func restoresWindowsFromSavedConfig() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = PersistenceService(storageDirectory: temporaryDirectory)
        let mockPositioner = MockWindowPositioner()
        let mockDisplayProvider = MockDisplayInfoProvider()

        // Set up mock display config
        mockDisplayProvider.mockDisplays = [
            DisplayInfo(
                identifier: "display-1",
                name: "Test Monitor",
                resolution: CGSize(width: 1920, height: 1080),
                position: CGPoint(x: 0, y: 0)
            )
        ]
        mockDisplayProvider.mockConfigId = "config-test-123"

        // Save a configuration
        let savedConfig = DisplayConfiguration(
            identifier: "config-test-123",
            displays: mockDisplayProvider.mockDisplays,
            windows: [
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Apple",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600)
                )
            ],
            capturedAt: Date()
        )
        try persistence.save(configuration: savedConfig)

        let coordinator = RestoreCoordinator(
            persistenceService: persistence,
            displayInfoProvider: mockDisplayProvider,
            windowPositioner: mockPositioner
        )

        let results = coordinator.restoreWindows()

        #expect(results.count == 1)
        #expect(results[0].success)
    }

    @Test("RestoreCoordinator returns empty when no saved config exists")
    func returnsEmptyWhenNoConfig() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = PersistenceService(storageDirectory: temporaryDirectory)
        let mockPositioner = MockWindowPositioner()
        let mockDisplayProvider = MockDisplayInfoProvider()
        mockDisplayProvider.mockConfigId = "nonexistent-config"

        let coordinator = RestoreCoordinator(
            persistenceService: persistence,
            displayInfoProvider: mockDisplayProvider,
            windowPositioner: mockPositioner
        )

        let results = coordinator.restoreWindows()

        #expect(results.isEmpty)
    }

    @Test("Full save/restore cycle preserves minimized state")
    func preservesMinimizedState() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = PersistenceService(storageDirectory: temporaryDirectory)
        let mockPositioner = MockWindowPositioner()
        let mockDisplayProvider = MockDisplayInfoProvider()

        // Set up mock display config
        mockDisplayProvider.mockDisplays = [
            DisplayInfo(
                identifier: "display-1",
                name: "Test Monitor",
                resolution: CGSize(width: 1920, height: 1080),
                position: CGPoint(x: 0, y: 0)
            )
        ]
        mockDisplayProvider.mockConfigId = "config-minimized-test"

        // Save a configuration with mixed minimized states
        let savedConfig = DisplayConfiguration(
            identifier: "config-minimized-test",
            displays: mockDisplayProvider.mockDisplays,
            windows: [
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Visible Window",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false
                ),
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Minimized Window",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                    isMinimized: true
                )
            ],
            capturedAt: Date()
        )
        try persistence.save(configuration: savedConfig)

        // Load and verify the minimized state was persisted
        let loadedConfig = try persistence.load(identifier: "config-minimized-test")
        #expect(loadedConfig != nil)
        #expect(loadedConfig!.windows.count == 2)
        #expect(loadedConfig!.windows[0].isMinimized == false)
        #expect(loadedConfig!.windows[1].isMinimized == true)

        // Restore and verify minimized state is in results
        let coordinator = RestoreCoordinator(
            persistenceService: persistence,
            displayInfoProvider: mockDisplayProvider,
            windowPositioner: mockPositioner
        )

        let results = coordinator.restoreWindows()

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })

        // Verify minimized states are preserved in restore results
        let visibleResult = results.first { $0.snapshot.windowTitle == "Visible Window" }
        let minimizedResult = results.first { $0.snapshot.windowTitle == "Minimized Window" }
        #expect(visibleResult?.snapshot.isMinimized == false)
        #expect(minimizedResult?.snapshot.isMinimized == true)
    }

    @Test("Full save/restore cycle preserves windowIdentifier")
    func preservesWindowIdentifier() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let persistence = PersistenceService(storageDirectory: temporaryDirectory)
        let mockPositioner = MockWindowPositioner()
        let mockDisplayProvider = MockDisplayInfoProvider()

        // Set up mock display config
        mockDisplayProvider.mockDisplays = [
            DisplayInfo(
                identifier: "display-1",
                name: "Test Monitor",
                resolution: CGSize(width: 1920, height: 1080),
                position: CGPoint(x: 0, y: 0)
            )
        ]
        mockDisplayProvider.mockConfigId = "config-windowid-test"

        // Save a configuration with windowIdentifiers (simulating multiple browser windows)
        let savedConfig = DisplayConfiguration(
            identifier: "config-windowid-test",
            displays: mockDisplayProvider.mockDisplays,
            windows: [
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Tab A",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    windowIdentifier: 12345
                ),
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Tab B",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 200, y: 200, width: 800, height: 600),
                    windowIdentifier: 67890
                ),
                WindowSnapshot(
                    applicationBundleIdentifier: "com.apple.Safari",
                    applicationName: "Safari",
                    windowTitle: "Legacy Window",
                    displayIdentifier: "display-1",
                    frame: CGRect(x: 300, y: 300, width: 800, height: 600),
                    windowIdentifier: nil  // Legacy window without ID
                )
            ],
            capturedAt: Date()
        )
        try persistence.save(configuration: savedConfig)

        // Load and verify the windowIdentifiers were persisted
        let loadedConfig = try persistence.load(identifier: "config-windowid-test")
        #expect(loadedConfig != nil)
        #expect(loadedConfig!.windows.count == 3)
        #expect(loadedConfig!.windows[0].windowIdentifier == 12345)
        #expect(loadedConfig!.windows[1].windowIdentifier == 67890)
        #expect(loadedConfig!.windows[2].windowIdentifier == nil)

        // Restore and verify windowIdentifiers are in results
        let coordinator = RestoreCoordinator(
            persistenceService: persistence,
            displayInfoProvider: mockDisplayProvider,
            windowPositioner: mockPositioner
        )

        let results = coordinator.restoreWindows()

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.success })

        // Verify windowIdentifiers are preserved in restore results
        let windowIds = results.map { $0.snapshot.windowIdentifier }
        #expect(windowIds.contains(12345))
        #expect(windowIds.contains(67890))
        #expect(windowIds.contains(nil))
    }

    @Test("Restore works with legacy config without windowIdentifier")
    func restoresLegacyConfigWithoutWindowIdentifier() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // Write a legacy JSON config that doesn't have windowIdentifier field
        let legacyJson = """
        {
            "identifier": "legacy-config",
            "displays": [
                {
                    "identifier": "display-1",
                    "name": "Legacy Monitor",
                    "resolution": [1920, 1080],
                    "position": [0, 0]
                }
            ],
            "windows": [
                {
                    "applicationBundleIdentifier": "com.apple.Safari",
                    "applicationName": "Safari",
                    "windowTitle": "Legacy Safari Window",
                    "displayIdentifier": "display-1",
                    "frame": [[100, 100], [800, 600]],
                    "lastSeenAt": 0,
                    "isMinimized": false
                },
                {
                    "applicationBundleIdentifier": "com.apple.finder",
                    "applicationName": "Finder",
                    "windowTitle": "Legacy Finder Window",
                    "displayIdentifier": "display-1",
                    "frame": [[200, 200], [600, 400]],
                    "lastSeenAt": 0,
                    "isMinimized": false
                }
            ],
            "capturedAt": 0
        }
        """

        let configFile = temporaryDirectory.appendingPathComponent("legacy-config.json")
        try legacyJson.data(using: .utf8)!.write(to: configFile)

        let persistence = PersistenceService(storageDirectory: temporaryDirectory)
        let mockPositioner = MockWindowPositioner()
        let mockDisplayProvider = MockDisplayInfoProvider()
        mockDisplayProvider.mockConfigId = "legacy-config"
        mockDisplayProvider.mockDisplays = [
            DisplayInfo(
                identifier: "display-1",
                name: "Legacy Monitor",
                resolution: CGSize(width: 1920, height: 1080),
                position: CGPoint(x: 0, y: 0)
            )
        ]

        // Load legacy config - should work with nil windowIdentifiers
        let loadedConfig = try persistence.load(identifier: "legacy-config")
        #expect(loadedConfig != nil)
        #expect(loadedConfig!.windows.count == 2)
        // All windows should have nil windowIdentifier
        #expect(loadedConfig!.windows.allSatisfy { $0.windowIdentifier == nil })

        // Restore should work - falls back to title matching
        let coordinator = RestoreCoordinator(
            persistenceService: persistence,
            displayInfoProvider: mockDisplayProvider,
            windowPositioner: mockPositioner
        )

        let results = coordinator.restoreWindows()

        // Restore should succeed using title fallback
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })
        #expect(results.allSatisfy { $0.snapshot.windowIdentifier == nil })
    }
}

// Mock DisplayInfoProvider
final class MockDisplayInfoProvider: DisplayInfoProviding, @unchecked Sendable {
    var mockDisplays: [DisplayInfo] = []
    var mockConfigId: String = "mock-config"

    func getDisplays() -> [DisplayInfo] {
        return mockDisplays
    }

    func getCurrentConfigurationIdentifier() -> String {
        return mockConfigId
    }
}
