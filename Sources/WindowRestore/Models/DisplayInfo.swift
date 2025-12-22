import Foundation
import CoreGraphics

public struct DisplayInfo: Codable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let resolution: CGSize
    public let position: CGPoint

    public init(
        identifier: String,
        name: String,
        resolution: CGSize,
        position: CGPoint
    ) {
        self.identifier = identifier
        self.name = name
        self.resolution = resolution
        self.position = position
    }
}
