import Foundation

public struct DisplayConfiguration: Codable, Equatable, Sendable {
    public let identifier: String
    public let displays: [DisplayInfo]
    public let windows: [WindowSnapshot]
    public let capturedAt: Date

    public init(
        identifier: String,
        displays: [DisplayInfo],
        windows: [WindowSnapshot],
        capturedAt: Date
    ) {
        self.identifier = identifier
        self.displays = displays
        self.windows = windows
        self.capturedAt = capturedAt
    }
}
