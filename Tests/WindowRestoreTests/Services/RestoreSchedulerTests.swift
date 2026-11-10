import Testing
import Foundation
@testable import WindowRestore

/// A clock that only moves when a test tells it to. Sleepers wake when `advance(by:)` passes their deadline.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]

    var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var minimumResolution: Duration { .zero }

    /// How many tasks are currently asleep on this clock.
    var sleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepers[identifier] = Sleeper(deadline: deadline, continuation: continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let cancelled = sleepers.removeValue(forKey: identifier)
            lock.unlock()
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let due = sleepers.filter { $0.value.deadline <= current }
        for key in due.keys {
            sleepers.removeValue(forKey: key)
        }
        lock.unlock()
        for sleeper in due.values.sorted(by: { $0.deadline < $1.deadline }) {
            sleeper.continuation.resume()
        }
    }
}

@MainActor
final class SchedulerHarness {
    let clock = ManualClock()
    private(set) var restoreCount = 0
    private(set) var logLines: [String] = []
    var toggles = RestoreScheduler<ManualClock>.Toggles(
        restoreOnConnect: true,
        restoreOnDisconnect: true,
        restoreOnDesktopChange: true
    )
    private(set) var scheduler: RestoreScheduler<ManualClock>!

    init(countdown: Duration = .seconds(10), desktopChangeDelay: Duration = .milliseconds(500)) {
        scheduler = RestoreScheduler(
            countdown: countdown,
            desktopChangeDelay: desktopChangeDelay,
            clock: clock,
            readToggles: { [unowned self] in self.toggles },
            onRestore: { [unowned self] in self.restoreCount += 1 },
            log: { [unowned self] line in self.logLines.append(line) }
        )
    }

    /// Lets every task that is ready to run do so, until the clock has the expected number of sleepers
    /// or the yield budget runs out. Fails loudly rather than hanging.
    func settle(expectingSleepers expected: Int) async {
        for _ in 0..<200 {
            if clock.sleeperCount == expected {
                await Task.yield()
                return
            }
            await Task.yield()
        }
        Issue.record("expected \(expected) sleeper(s) on the clock, found \(clock.sleeperCount)")
    }

    /// Moves the clock and lets whatever woke up run to completion.
    func advance(by duration: Duration) async {
        clock.advance(by: duration)
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    func added(_ display: UInt32) -> DisplayReconfigurationEvent {
        DisplayReconfigurationEvent(displayIdentifier: display, kind: .added)
    }

    func removed(_ display: UInt32) -> DisplayReconfigurationEvent {
        DisplayReconfigurationEvent(displayIdentifier: display, kind: .removed)
    }

    func moved(_ display: UInt32) -> DisplayReconfigurationEvent {
        DisplayReconfigurationEvent(displayIdentifier: display, kind: .moved)
    }
}

@Suite("RestoreScheduler Tests")
@MainActor
struct RestoreSchedulerTests {

    @Test("A storm of events inside the window produces exactly one restore after the countdown")
    func stormProducesOneRestore() async {
        let harness = SchedulerHarness()

        // The 2026-10-30 storm: stub added, both displays removed; builtin back, stub gone; external back.
        harness.scheduler.displayDidChange(harness.added(0x27))
        harness.scheduler.displayDidChange(harness.removed(0x1))
        harness.scheduler.displayDidChange(harness.removed(0x2))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(500))

        harness.scheduler.displayDidChange(harness.added(0x1))
        harness.scheduler.displayDidChange(harness.removed(0x27))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(750))

        harness.scheduler.displayDidChange(harness.added(0x2))
        harness.scheduler.displayDidChange(harness.moved(0x1))
        await harness.settle(expectingSleepers: 1)

        #expect(harness.restoreCount == 0)
        await harness.advance(by: .seconds(9))
        #expect(harness.restoreCount == 0, "the countdown must run from the LAST event")
        await harness.advance(by: .seconds(1))
        #expect(harness.restoreCount == 1)
        #expect(!harness.scheduler.isCountdownRunning)

        await harness.advance(by: .seconds(60))
        #expect(harness.restoreCount == 1, "nothing else may fire later")
    }

    @Test("Each event restarts the countdown")
    func eachEventRestartsTheCountdown() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.added(1))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(9))

        harness.scheduler.displayDidChange(harness.moved(1))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(9))
        #expect(harness.restoreCount == 0)

        await harness.advance(by: .seconds(1))
        #expect(harness.restoreCount == 1)
    }

    @Test("A storm that only moved or re-moded displays does not restore")
    func neutralOnlyStormDoesNotRestore() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.moved(1))
        harness.scheduler.displayDidChange(DisplayReconfigurationEvent(displayIdentifier: 1, kind: .modeChanged))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(10))

        #expect(harness.restoreCount == 0)
    }

    @Test("A restore fires if any direction seen during the countdown is enabled")
    func restoresIfAnySeenDirectionIsEnabled() async {
        let harness = SchedulerHarness()
        harness.toggles.restoreOnConnect = false

        harness.scheduler.displayDidChange(harness.removed(2))
        harness.scheduler.displayDidChange(harness.added(2))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(10))

        #expect(harness.restoreCount == 1, "disconnect is enabled and a removal was seen")
    }

    @Test("A storm made only of disabled directions does nothing")
    func disabledDirectionOnlyStormDoesNothing() async {
        let harness = SchedulerHarness()
        harness.toggles.restoreOnConnect = false

        harness.scheduler.displayDidChange(harness.added(2))
        harness.scheduler.displayDidChange(harness.moved(1))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(10))

        #expect(harness.restoreCount == 0)
    }

    @Test("Toggles are read when the countdown expires, not when the event arrives")
    func togglesAreReadAtExpiry() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.added(2))
        await harness.settle(expectingSleepers: 1)
        harness.toggles.restoreOnConnect = false
        await harness.advance(by: .seconds(10))

        #expect(harness.restoreCount == 0)
    }

    @Test("Directions seen are forgotten once the countdown has expired")
    func directionsAreForgottenAfterExpiry() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.added(2))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(10))
        #expect(harness.restoreCount == 1)

        harness.scheduler.displayDidChange(harness.moved(2))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(10))
        #expect(harness.restoreCount == 1, "a later neutral-only storm must not inherit the earlier add")
    }

    @Test("A desktop change with no countdown running restores after the short delay")
    func desktopChangeRestoresAfterShortDelay() async {
        let harness = SchedulerHarness()

        harness.scheduler.desktopDidChange()
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(499))
        #expect(harness.restoreCount == 0)
        await harness.advance(by: .milliseconds(1))
        #expect(harness.restoreCount == 1)
    }

    @Test("A desktop change while a countdown is running is absorbed and does not restart it")
    func desktopChangeDuringCountdownIsAbsorbed() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.added(1))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(6))

        harness.scheduler.desktopDidChange()
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(4))

        #expect(harness.restoreCount == 1, "the countdown kept its original deadline")
        await harness.advance(by: .seconds(60))
        #expect(harness.restoreCount == 1, "the absorbed desktop change adds no restore of its own")
    }

    @Test("A desktop change is ignored when its toggle is off")
    func desktopChangeIgnoredWhenDisabled() async {
        let harness = SchedulerHarness()
        harness.toggles.restoreOnDesktopChange = false

        harness.scheduler.desktopDidChange()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(harness.clock.sleeperCount == 0)
        await harness.advance(by: .seconds(1))
        #expect(harness.restoreCount == 0)
    }

    @Test("A display event supersedes a pending desktop-change restore")
    func displayEventSupersedesPendingDesktopRestore() async {
        let harness = SchedulerHarness()

        harness.scheduler.desktopDidChange()
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(200))

        harness.scheduler.displayDidChange(harness.removed(2))
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .seconds(1))
        #expect(harness.restoreCount == 0, "the desktop restore was cancelled")

        await harness.advance(by: .seconds(9))
        #expect(harness.restoreCount == 1, "only the countdown restore ran")
    }

    @Test("Repeated desktop changes collapse into one pending restore")
    func repeatedDesktopChangesCollapse() async {
        let harness = SchedulerHarness()

        harness.scheduler.desktopDidChange()
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(300))
        harness.scheduler.desktopDidChange()
        await harness.settle(expectingSleepers: 1)
        await harness.advance(by: .milliseconds(300))
        #expect(harness.restoreCount == 0, "the second change restarted the short delay")
        await harness.advance(by: .milliseconds(200))
        #expect(harness.restoreCount == 1)
    }

    @Test("Cancelling pending restores leaves nothing to fire")
    func cancelLeavesNothingPending() async {
        let harness = SchedulerHarness()

        harness.scheduler.displayDidChange(harness.added(1))
        await harness.settle(expectingSleepers: 1)
        harness.scheduler.cancelPendingRestores()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(!harness.scheduler.isCountdownRunning)
        await harness.advance(by: .seconds(60))
        #expect(harness.restoreCount == 0)
    }
}
