import CoreGraphics

/// One change to one display, as reported by the Core Graphics display reconfiguration callback
/// after a configuration transaction has been applied.
///
/// A reconfiguration storm (a dock waking its monitors, for example) arrives as several transactions,
/// each delivered per display with a set of flags. Every flag becomes one event so the scheduler can
/// treat any of them as "the displays are still settling".
public struct DisplayReconfigurationEvent: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case added
        case removed
        case moved
        case becameMain
        case modeChanged
        case enabled
        case disabled
        case mirrored
        case unmirrored
        case desktopShapeChanged
        /// A flag bit this build does not know. Reported rather than dropped so the log shows it.
        case unrecognized(rawValue: UInt32)
    }

    /// The direction the connect/disconnect restore toggles speak about.
    public enum Direction: Sendable, Hashable {
        case connect
        case disconnect
    }

    public let displayIdentifier: CGDirectDisplayID
    public let kind: Kind

    public init(displayIdentifier: CGDirectDisplayID, kind: Kind) {
        self.displayIdentifier = displayIdentifier
        self.kind = kind
    }

    /// Only an added or removed display counts toward a restore. Every other kind extends a
    /// running countdown but does not, on its own, justify a restore.
    public var direction: Direction? {
        switch kind {
        case .added:
            return .connect
        case .removed:
            return .disconnect
        default:
            return nil
        }
    }

    /// The documented post-configuration flags, in the order their events are emitted.
    private static let documentedFlags: [(flag: CGDisplayChangeSummaryFlags, kind: Kind)] = [
        (.addFlag, .added),
        (.removeFlag, .removed),
        (.movedFlag, .moved),
        (.setMainFlag, .becameMain),
        (.setModeFlag, .modeChanged),
        (.enabledFlag, .enabled),
        (.disabledFlag, .disabled),
        (.mirrorFlag, .mirrored),
        (.unMirrorFlag, .unmirrored),
        (.desktopShapeChangedFlag, .desktopShapeChanged),
    ]

    /// Maps one callback invocation to events.
    ///
    /// Returns an empty array for the begin-configuration notice, which precedes the change and
    /// carries no information about it. Any flag bit outside the documented set is reported as
    /// `.unrecognized` so it is visible in the log instead of silently ignored.
    public static func events(
        displayIdentifier: CGDirectDisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) -> [DisplayReconfigurationEvent] {
        if flags.contains(.beginConfigurationFlag) {
            return []
        }

        var events: [DisplayReconfigurationEvent] = []
        var knownBits: UInt32 = 0
        for entry in documentedFlags {
            knownBits |= entry.flag.rawValue
            if flags.contains(entry.flag) {
                events.append(DisplayReconfigurationEvent(displayIdentifier: displayIdentifier, kind: entry.kind))
            }
        }

        let unknownBits = flags.rawValue & ~knownBits
        if unknownBits != 0 {
            events.append(
                DisplayReconfigurationEvent(displayIdentifier: displayIdentifier, kind: .unrecognized(rawValue: unknownBits))
            )
        }

        return events
    }
}
