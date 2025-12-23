import Foundation

public final class PersistenceService: Sendable {
    private let storageDirectory: URL

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    public convenience init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let windowRestoreDirectory = applicationSupport
            .appendingPathComponent("WindowRestore")

        self.init(storageDirectory: windowRestoreDirectory)
    }

    public func save(configuration: DisplayConfiguration) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        let filePath = storageDirectory
            .appendingPathComponent("\(configuration.identifier).json")
        try data.write(to: filePath)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: filePath.path
        )
    }

    public func load(identifier: String) throws -> DisplayConfiguration? {
        let filePath = storageDirectory
            .appendingPathComponent("\(identifier).json")

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        let data = try Data(contentsOf: filePath)
        let decoder = JSONDecoder()
        return try decoder.decode(DisplayConfiguration.self, from: data)
    }

    public func listConfigurationIdentifiers() throws -> [String] {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        )

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    public func deleteAllConfigurations() throws {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else {
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        )

        for file in contents where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true
            )
        }
    }
}
