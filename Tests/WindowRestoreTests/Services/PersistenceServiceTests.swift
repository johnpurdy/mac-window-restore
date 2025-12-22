import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("PersistenceService Tests")
struct PersistenceServiceTests {

    private func createTestConfiguration(identifier: String = "test-config") -> DisplayConfiguration {
        let display = DisplayInfo(
            identifier: "serial-test",
            name: "Test Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let window = WindowSnapshot(
            applicationBundleIdentifier: "com.test.app",
            applicationName: "Test App",
            windowTitle: "Test Window",
            displayIdentifier: "serial-test",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )

        return DisplayConfiguration(
            identifier: identifier,
            displays: [display],
            windows: [window],
            capturedAt: Date()
        )
    }

    private func createTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        return temporaryDirectory
    }

    @Test("PersistenceService saves configuration to disk")
    func saveConfiguration() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)
        let configuration = createTestConfiguration()

        try service.save(configuration: configuration)

        let expectedPath = temporaryDirectory
            .appendingPathComponent("test-config.json")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path))
    }

    @Test("PersistenceService saves valid JSON")
    func savesValidJson() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)
        let configuration = createTestConfiguration()

        try service.save(configuration: configuration)

        let filePath = temporaryDirectory.appendingPathComponent("test-config.json")
        let data = try Data(contentsOf: filePath)
        let decoded = try JSONDecoder().decode(DisplayConfiguration.self, from: data)

        #expect(decoded.identifier == "test-config")
        #expect(decoded.windows.count == 1)
    }

    @Test("PersistenceService loads saved configuration")
    func loadConfiguration() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)
        let configuration = createTestConfiguration(identifier: "load-test")

        try service.save(configuration: configuration)

        let loaded = try service.load(identifier: "load-test")

        #expect(loaded != nil)
        #expect(loaded?.identifier == "load-test")
        #expect(loaded?.windows.count == 1)
        #expect(loaded?.windows.first?.applicationBundleIdentifier == "com.test.app")
    }

    @Test("PersistenceService returns nil for missing configuration")
    func loadMissingConfiguration() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)

        let loaded = try service.load(identifier: "nonexistent")

        #expect(loaded == nil)
    }

    @Test("PersistenceService stores multiple configurations independently")
    func multipleConfigurations() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)

        let config1 = createTestConfiguration(identifier: "config-dual-monitor")
        let config2 = createTestConfiguration(identifier: "config-single-monitor")

        try service.save(configuration: config1)
        try service.save(configuration: config2)

        let loaded1 = try service.load(identifier: "config-dual-monitor")
        let loaded2 = try service.load(identifier: "config-single-monitor")

        #expect(loaded1?.identifier == "config-dual-monitor")
        #expect(loaded2?.identifier == "config-single-monitor")
    }

    @Test("PersistenceService overwrites existing configuration with same identifier")
    func overwriteConfiguration() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)

        let display1 = DisplayInfo(
            identifier: "serial-old",
            name: "Old Monitor",
            resolution: CGSize(width: 1920, height: 1080),
            position: CGPoint(x: 0, y: 0)
        )

        let display2 = DisplayInfo(
            identifier: "serial-new",
            name: "New Monitor",
            resolution: CGSize(width: 3840, height: 2160),
            position: CGPoint(x: 0, y: 0)
        )

        let config1 = DisplayConfiguration(
            identifier: "same-id",
            displays: [display1],
            windows: [],
            capturedAt: Date()
        )

        let config2 = DisplayConfiguration(
            identifier: "same-id",
            displays: [display2],
            windows: [],
            capturedAt: Date()
        )

        try service.save(configuration: config1)
        try service.save(configuration: config2)

        let loaded = try service.load(identifier: "same-id")

        #expect(loaded?.displays.first?.name == "New Monitor")
    }

    @Test("PersistenceService lists all saved configuration identifiers")
    func listConfigurations() throws {
        let temporaryDirectory = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = PersistenceService(storageDirectory: temporaryDirectory)

        let config1 = createTestConfiguration(identifier: "config-a")
        let config2 = createTestConfiguration(identifier: "config-b")
        let config3 = createTestConfiguration(identifier: "config-c")

        try service.save(configuration: config1)
        try service.save(configuration: config2)
        try service.save(configuration: config3)

        let identifiers = try service.listConfigurationIdentifiers()

        #expect(identifiers.count == 3)
        #expect(identifiers.contains("config-a"))
        #expect(identifiers.contains("config-b"))
        #expect(identifiers.contains("config-c"))
    }
}
