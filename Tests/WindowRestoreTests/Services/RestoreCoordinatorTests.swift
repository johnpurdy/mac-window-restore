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
