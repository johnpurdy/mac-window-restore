import Foundation
import CoreGraphics

public struct WindowSnapshot: Codable, Equatable, Sendable {
    public let applicationBundleIdentifier: String
    public let applicationName: String
    public let windowTitle: String
    public let displayIdentifier: String
    public let frame: CGRect

    public init(
        applicationBundleIdentifier: String,
        applicationName: String,
        windowTitle: String,
        displayIdentifier: String,
        frame: CGRect
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.displayIdentifier = displayIdentifier
        self.frame = frame
    }
}
