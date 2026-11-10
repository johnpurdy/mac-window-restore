import Testing
import CoreGraphics
@testable import WindowRestore

@Suite("DisplayReconfigurationEvent Tests")
struct DisplayReconfigurationEventTests {

    @Test("The begin-configuration notice produces no events")
    func beginConfigurationProducesNoEvents() {
        let events = DisplayReconfigurationEvent.events(
            displayIdentifier: 1,
            flags: .beginConfigurationFlag
        )
        #expect(events.isEmpty)
    }

    @Test("An add flag produces one added event for that display")
    func addFlagProducesAddedEvent() {
        let events = DisplayReconfigurationEvent.events(displayIdentifier: 2, flags: .addFlag)
        #expect(events == [DisplayReconfigurationEvent(displayIdentifier: 2, kind: .added)])
    }

    @Test("A remove flag produces one removed event for that display")
    func removeFlagProducesRemovedEvent() {
        let events = DisplayReconfigurationEvent.events(displayIdentifier: 2, flags: .removeFlag)
        #expect(events == [DisplayReconfigurationEvent(displayIdentifier: 2, kind: .removed)])
    }

    @Test("Several flags on one display produce one event per flag, in a fixed order")
    func combinedFlagsProduceOneEventEach() {
        let flags: CGDisplayChangeSummaryFlags = [.setModeFlag, .movedFlag, .setMainFlag]
        let events = DisplayReconfigurationEvent.events(displayIdentifier: 1, flags: flags)
        #expect(events.map(\.kind) == [.moved, .becameMain, .modeChanged])
        #expect(events.allSatisfy { $0.displayIdentifier == 1 })
    }

    @Test("Every documented post-configuration flag maps to a named kind")
    func everyDocumentedFlagHasAKind() {
        let documented: [(CGDisplayChangeSummaryFlags, DisplayReconfigurationEvent.Kind)] = [
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
        for (flag, expectedKind) in documented {
            let events = DisplayReconfigurationEvent.events(displayIdentifier: 7, flags: flag)
            #expect(events.map(\.kind) == [expectedKind], "flag \(flag.rawValue)")
        }
    }

    @Test("A flag bit this build does not know is reported, not dropped")
    func unknownFlagIsReported() {
        let unknownBit: UInt32 = 1 << 30
        let flags = CGDisplayChangeSummaryFlags(rawValue: unknownBit | CGDisplayChangeSummaryFlags.addFlag.rawValue)
        let events = DisplayReconfigurationEvent.events(displayIdentifier: 3, flags: flags)
        #expect(events.map(\.kind) == [.added, .unrecognized(rawValue: unknownBit)])
    }

    @Test("Only added and removed carry a restore direction")
    func onlyAddedAndRemovedCarryADirection() {
        #expect(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .added).direction == .connect)
        #expect(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .removed).direction == .disconnect)
        #expect(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .moved).direction == nil)
        #expect(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .modeChanged).direction == nil)
        #expect(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .unrecognized(rawValue: 1 << 30)).direction == nil)
    }
}
