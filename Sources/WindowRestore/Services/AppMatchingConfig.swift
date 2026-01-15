import Foundation

/// Configuration for app matching behavior
public struct AppMatchingConfig: Codable, Sendable {
    public let multiWindowApps: [String]
    public let tabEnabledApps: [String]
    public let tabMatchThreshold: Double

    // Cache sets for O(1) lookup
    private let multiWindowAppsSet: Set<String>
    private let tabEnabledAppsSet: Set<String>

    public init(
        multiWindowApps: [String],
        tabEnabledApps: [String],
        tabMatchThreshold: Double
    ) {
        self.multiWindowApps = multiWindowApps
        self.tabEnabledApps = tabEnabledApps
        self.tabMatchThreshold = tabMatchThreshold
        self.multiWindowAppsSet = Set(multiWindowApps)
        self.tabEnabledAppsSet = Set(tabEnabledApps)
    }

    // Custom Codable to handle the cached sets
    private enum CodingKeys: String, CodingKey {
        case multiWindowApps
        case tabEnabledApps
        case tabMatchThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.multiWindowApps = try container.decode([String].self, forKey: .multiWindowApps)
        self.tabEnabledApps = try container.decode([String].self, forKey: .tabEnabledApps)
        self.tabMatchThreshold = try container.decode(Double.self, forKey: .tabMatchThreshold)
        self.multiWindowAppsSet = Set(self.multiWindowApps)
        self.tabEnabledAppsSet = Set(self.tabEnabledApps)
    }

    /// Check if an app is a multi-window app
    public func isMultiWindowApp(_ bundleIdentifier: String) -> Bool {
        return multiWindowAppsSet.contains(bundleIdentifier)
    }

    /// Check if an app supports tab enumeration
    public func isTabEnabledApp(_ bundleIdentifier: String) -> Bool {
        return tabEnabledAppsSet.contains(bundleIdentifier)
    }

    /// Default config file location
    public static var defaultConfigURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WindowRestore/app-matching-config.json")
    }

    /// Load config from default location, or return defaults if file doesn't exist
    public static func loadOrDefault() -> AppMatchingConfig {
        return loadOrDefault(from: defaultConfigURL)
    }

    /// Load config from file, or return defaults if file doesn't exist
    public static func loadOrDefault(from url: URL) -> AppMatchingConfig {
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AppMatchingConfig.self, from: data) {
            return config
        }
        return defaultConfig
    }

    /// Default configuration used when no config file exists
    public static let defaultConfig = AppMatchingConfig(
        multiWindowApps: [
            "com.microsoft.edgemac",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "company.thebrowser.Browser",
            "com.microsoft.VSCode",
            "com.apple.finder",
            "com.apple.Preview",
            "com.apple.TextEdit",
            "com.apple.dt.Xcode",
            "com.sublimetext.4",
            "com.jetbrains.intellij",
            "com.googlecode.iterm2"
        ],
        tabEnabledApps: [
            "com.microsoft.edgemac",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium"
        ],
        tabMatchThreshold: 0.5
    )
}
