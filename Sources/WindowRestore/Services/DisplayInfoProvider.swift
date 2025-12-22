import Foundation
import CoreGraphics
import AppKit
import IOKit

public protocol DisplayInfoProviding: Sendable {
    func getDisplays() -> [DisplayInfo]
    func getCurrentConfigurationIdentifier() -> String
}

public final class DisplayInfoProvider: DisplayInfoProviding, @unchecked Sendable {

    public init() {}

    public func getDisplays() -> [DisplayInfo] {
        return NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

            let vendorNumber = CGDisplayVendorNumber(displayID)
            let modelNumber = CGDisplayModelNumber(displayID)
            let serialNumber = CGDisplaySerialNumber(displayID)

            let identifier = DisplayIdentifier.generateIdentifier(
                vendorNumber: vendorNumber,
                modelNumber: modelNumber,
                serialNumber: serialNumber,
                resolutionWidth: Int(screen.frame.width),
                resolutionHeight: Int(screen.frame.height)
            )

            return DisplayInfo(
                identifier: identifier,
                name: screen.localizedName,
                resolution: CGSize(width: screen.frame.width, height: screen.frame.height),
                position: screen.frame.origin
            )
        }
    }

    public func getCurrentConfigurationIdentifier() -> String {
        let displays = getDisplays()
        let displayIdentifiers = displays.map { $0.identifier }
        return DisplayIdentifier.generateConfigurationIdentifier(displayIdentifiers: displayIdentifiers)
    }
}
