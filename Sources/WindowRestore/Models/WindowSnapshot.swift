import Foundation
import CoreGraphics

public struct WindowSnapshot: Codable, Equatable, Sendable {
    public let applicationBundleIdentifier: String
    public let applicationName: String
    public let windowTitle: String
    public let displayIdentifier: String
    public let frame: CGRect
    public let lastSeenAt: Date
    public let isMinimized: Bool

    public init(
        applicationBundleIdentifier: String,
        applicationName: String,
        windowTitle: String,
        displayIdentifier: String,
        frame: CGRect,
        lastSeenAt: Date = Date(),
        isMinimized: Bool = false
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.displayIdentifier = displayIdentifier
        self.frame = frame
        self.lastSeenAt = lastSeenAt
        self.isMinimized = isMinimized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationBundleIdentifier = try container.decode(String.self, forKey: .applicationBundleIdentifier)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        displayIdentifier = try container.decode(String.self, forKey: .displayIdentifier)
        frame = try container.decode(CGRect.self, forKey: .frame)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? Date()
        isMinimized = try container.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case applicationBundleIdentifier
        case applicationName
        case windowTitle
        case displayIdentifier
        case frame
        case lastSeenAt
        case isMinimized
    }
}
