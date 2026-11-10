import Foundation

/// Decides WHEN an automatic restore runs.
///
/// Display events restart one countdown. When it expires, one restore runs if any direction seen
/// during the countdown (a display added, a display removed) has its toggle enabled. Events that
/// only move or re-mode a display extend the countdown but never justify a restore on their own,
/// matching the previous behaviour in which an unchanged screen count did nothing.
///
/// A desktop (Space) change restores after a short delay when no countdown is running. While a
/// countdown is running the desktop change is absorbed: the countdown keeps its deadline and the
/// restore it produces covers the new desktop too.
///
/// Serialization follows from the shape: there is at most one countdown task and at most one
/// desktop-change task, a display event cancels any pending desktop-change restore, and the restore
/// callback itself runs synchronously on the main actor.
@MainActor
public final class RestoreScheduler<SchedulerClock: Clock> where SchedulerClock.Duration == Duration {

    public struct Toggles: Sendable, Equatable {
        public var restoreOnConnect: Bool
        public var restoreOnDisconnect: Bool
        public var restoreOnDesktopChange: Bool

        public init(restoreOnConnect: Bool, restoreOnDisconnect: Bool, restoreOnDesktopChange: Bool) {
            self.restoreOnConnect = restoreOnConnect
            self.restoreOnDisconnect = restoreOnDisconnect
            self.restoreOnDesktopChange = restoreOnDesktopChange
        }
    }

    private let countdown: Duration
    private let desktopChangeDelay: Duration
    private let clock: SchedulerClock
    private let readToggles: @MainActor () -> Toggles
    private let onRestore: @MainActor () -> Void
    private let log: @MainActor (String) -> Void

    private var countdownTask: Task<Void, Never>?
    private var countdownGeneration = 0
    private var directionsSeen: Set<DisplayReconfigurationEvent.Direction> = []

    private var desktopChangeTask: Task<Void, Never>?
    private var desktopChangeGeneration = 0

    /// - Parameters:
    ///   - countdown: How long after the LAST display event the restore runs.
    ///   - desktopChangeDelay: How long after a desktop change the restore runs when no countdown is running.
    ///   - clock: The clock both delays sleep on. Tests inject a manual clock.
    ///   - readToggles: Read at the moment a delay expires, so a toggle flipped during a countdown is honoured.
    ///   - onRestore: The restore itself. Runs on the main actor and is expected to be synchronous.
    ///   - log: Where the scheduler explains its decisions.
    public init(
        countdown: Duration,
        desktopChangeDelay: Duration,
        clock: SchedulerClock,
        readToggles: @escaping @MainActor () -> Toggles,
        onRestore: @escaping @MainActor () -> Void,
        log: @escaping @MainActor (String) -> Void
    ) {
        precondition(countdown > .zero, "The restore countdown must be positive")
        precondition(desktopChangeDelay >= .zero, "The desktop change delay cannot be negative")
        self.countdown = countdown
        self.desktopChangeDelay = desktopChangeDelay
        self.clock = clock
        self.readToggles = readToggles
        self.onRestore = onRestore
        self.log = log
    }

    public var isCountdownRunning: Bool {
        countdownTask != nil
    }

    /// A display was added, removed, moved or otherwise reconfigured. Restarts the countdown.
    public func displayDidChange(_ event: DisplayReconfigurationEvent) {
        if let direction = event.direction {
            directionsSeen.insert(direction)
        }

        if desktopChangeTask != nil {
            desktopChangeTask?.cancel()
            desktopChangeTask = nil
            log("Display changed while a desktop-change restore was pending: the countdown replaces it")
        }

        countdownTask?.cancel()
        countdownGeneration += 1
        let generation = countdownGeneration
        let clock = self.clock
        let countdown = self.countdown
        log("Display \(event.displayIdentifier) \(describe(event.kind)): restore countdown restarted (\(countdown))")

        countdownTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: countdown)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.countdownGeneration == generation else { return }
            self.countdownExpired()
        }
    }

    /// The active desktop (Space) changed.
    public func desktopDidChange() {
        if isCountdownRunning {
            log("Desktop changed during a restore countdown: absorbed, the countdown keeps its deadline")
            return
        }

        guard readToggles().restoreOnDesktopChange else { return }

        desktopChangeTask?.cancel()
        desktopChangeGeneration += 1
        let generation = desktopChangeGeneration
        let clock = self.clock
        let delay = self.desktopChangeDelay

        desktopChangeTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.desktopChangeGeneration == generation else { return }
            self.desktopChangeTask = nil
            self.log("Desktop changed: restoring")
            self.onRestore()
        }
    }

    /// Drops any pending restore without running it.
    public func cancelPendingRestores() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownGeneration += 1
        directionsSeen = []

        desktopChangeTask?.cancel()
        desktopChangeTask = nil
        desktopChangeGeneration += 1
    }

    private func countdownExpired() {
        countdownTask = nil
        let seen = directionsSeen
        directionsSeen = []

        let toggles = readToggles()
        let connectJustifies = seen.contains(.connect) && toggles.restoreOnConnect
        let disconnectJustifies = seen.contains(.disconnect) && toggles.restoreOnDisconnect

        if connectJustifies || disconnectJustifies {
            log("Restore countdown expired: restoring (saw \(describe(seen)))")
            onRestore()
        } else if seen.isEmpty {
            log("Restore countdown expired: displays moved or changed mode but none was added or removed, not restoring")
        } else {
            log("Restore countdown expired: saw \(describe(seen)) but the matching toggles are off, not restoring")
        }
    }

    private func describe(_ kind: DisplayReconfigurationEvent.Kind) -> String {
        switch kind {
        case .added: return "added"
        case .removed: return "removed"
        case .moved: return "moved"
        case .becameMain: return "became main"
        case .modeChanged: return "changed mode"
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .mirrored: return "mirrored"
        case .unmirrored: return "unmirrored"
        case .desktopShapeChanged: return "desktop shape changed"
        case .unrecognized(let rawValue): return "unrecognized flag bits 0x\(String(rawValue, radix: 16))"
        }
    }

    private func describe(_ directions: Set<DisplayReconfigurationEvent.Direction>) -> String {
        var parts: [String] = []
        if directions.contains(.connect) { parts.append("a display added") }
        if directions.contains(.disconnect) { parts.append("a display removed") }
        return parts.joined(separator: " and ")
    }
}
