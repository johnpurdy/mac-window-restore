import Foundation
import CryptoKit

public enum DisplayIdentifier {

    public static func generateIdentifier(
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        resolutionWidth: Int,
        resolutionHeight: Int
    ) -> String {
        let components = [
            "v\(vendorNumber)",
            "m\(modelNumber)",
            "s\(serialNumber)",
            "r\(resolutionWidth)x\(resolutionHeight)"
        ]

        let combined = components.joined(separator: "-")
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)

        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func generateConfigurationIdentifier(
        displayIdentifiers: [String]
    ) -> String {
        let sorted = displayIdentifiers.sorted()
        let combined = sorted.joined(separator: "+")
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)

        return "config-" + hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
