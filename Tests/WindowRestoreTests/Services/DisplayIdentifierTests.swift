import Testing
import Foundation
import CoreGraphics
@testable import WindowRestore

@Suite("DisplayIdentifier Tests")
struct DisplayIdentifierTests {

    @Test("Same display properties produce same identifier")
    func samePropertiesSameIdentifier() {
        let identifier1 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 9999,
            resolutionWidth: 3840,
            resolutionHeight: 2160
        )

        let identifier2 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 9999,
            resolutionWidth: 3840,
            resolutionHeight: 2160
        )

        #expect(identifier1 == identifier2)
    }

    @Test("Different serial numbers produce different identifiers")
    func differentSerialDifferentIdentifier() {
        let identifier1 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 1111,
            resolutionWidth: 3840,
            resolutionHeight: 2160
        )

        let identifier2 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 2222,
            resolutionWidth: 3840,
            resolutionHeight: 2160
        )

        #expect(identifier1 != identifier2)
    }

    @Test("Different resolutions produce different identifiers")
    func differentResolutionDifferentIdentifier() {
        let identifier1 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 9999,
            resolutionWidth: 3840,
            resolutionHeight: 2160
        )

        let identifier2 = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 9999,
            resolutionWidth: 1920,
            resolutionHeight: 1080
        )

        #expect(identifier1 != identifier2)
    }

    @Test("Zero serial number still produces valid identifier")
    func zeroSerialNumber() {
        let identifier = DisplayIdentifier.generateIdentifier(
            vendorNumber: 1234,
            modelNumber: 5678,
            serialNumber: 0,
            resolutionWidth: 1920,
            resolutionHeight: 1080
        )

        #expect(!identifier.isEmpty)
    }

    @Test("Configuration identifier combines multiple display identifiers")
    func configurationIdentifier() {
        let displayIdentifiers = ["display-abc", "display-xyz"]

        let configId1 = DisplayIdentifier.generateConfigurationIdentifier(
            displayIdentifiers: displayIdentifiers
        )

        let configId2 = DisplayIdentifier.generateConfigurationIdentifier(
            displayIdentifiers: displayIdentifiers
        )

        #expect(configId1 == configId2)
    }

    @Test("Configuration identifier order matters")
    func configurationIdentifierOrderMatters() {
        let configId1 = DisplayIdentifier.generateConfigurationIdentifier(
            displayIdentifiers: ["display-abc", "display-xyz"]
        )

        let configId2 = DisplayIdentifier.generateConfigurationIdentifier(
            displayIdentifiers: ["display-xyz", "display-abc"]
        )

        // Same displays should produce same config ID regardless of order
        // We sort internally to ensure consistency
        #expect(configId1 == configId2)
    }
}
