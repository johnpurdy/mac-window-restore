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
