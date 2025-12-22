import Foundation

public final class RestoreCoordinator: @unchecked Sendable {
    private let persistenceService: PersistenceService
    private let displayInfoProvider: DisplayInfoProviding
    private let windowPositioner: WindowPositioning

    public init(
        persistenceService: PersistenceService,
        displayInfoProvider: DisplayInfoProviding,
        windowPositioner: WindowPositioning
    ) {
        self.persistenceService = persistenceService
        self.displayInfoProvider = displayInfoProvider
        self.windowPositioner = windowPositioner
    }

    public func restoreWindows() -> [WindowRestoreResult] {
        // Get current display configuration identifier
        let currentConfigId = displayInfoProvider.getCurrentConfigurationIdentifier()

        // Try to load saved configuration for this display setup
        guard let savedConfig = try? persistenceService.load(identifier: currentConfigId) else {
            return []
        }

        // Restore windows from saved configuration
        return windowPositioner.restoreWindows(snapshots: savedConfig.windows)
    }
}
