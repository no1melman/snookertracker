import EventDispatch
import Foundation
import LiveActivityShared
import MatchesApplication
import MatchesPublished

// Live Activity anti-corruption adapter (spec 018, S47, ADR-0004). No ActivityKit type crosses into
// the application layer: Matches offers `LockScreenState`, this adapter keeps exactly one activity
// in step with it, and the lock-screen buttons come back in through `MatchCommands`.

/// Shows, updates and removes the single lock-screen activity. Implemented with ActivityKit on iOS.
@MainActor public protocol LockScreenPresenter: AnyObject {
    /// Shows a new activity. Returns false when the system refused (e.g. the app is not in the
    /// foreground); the adapter then tries again on the next refresh.
    func start(_ content: MatchActivityAttributes.ContentState) -> Bool
    func update(_ content: MatchActivityAttributes.ContentState)
    func end()
}

/// Keeps the Live Activity in step with `LockScreenState` after every published match event.
@MainActor
public final class LockScreenActivity: LiveActivityPort {
    private let state: any LockScreenStateQuery
    private let presenter: any LockScreenPresenter
    private var shown: LockScreenState?
    private var synced = false

    public init(state: any LockScreenStateQuery, presenter: any LockScreenPresenter) {
        self.state = state
        self.presenter = presenter
    }

    /// Refreshes after each stored match event. Use cases dispatch on the main actor, after the
    /// read model has been projected, so `LockScreenState` is already current here.
    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.subscribe(MatchEventPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Brings the activity in line with `LockScreenState`: start one for the first live match,
    /// update it on the shown match's changes (other matches leave the state unchanged, so they are
    /// ignored), hand over to the next-oldest when it ends, and end it when no match is left.
    public func refresh() {
        let next = state.lockScreenState
        guard !synced || next != shown else { return }
        switch (shown, next) {
        case (_, nil):
            presenter.end()
        case (nil, let next?):
            guard presenter.start(Self.content(next)) else { return }
        case (_?, let next?):
            presenter.update(Self.content(next))
        }
        shown = next
        synced = true
    }

    /// `AppLocked` (S51): ends the activity straight away. `LockScreenState` is none while Free, so
    /// later refreshes keep it gone.
    public func removeLiveActivity() {
        if shown != nil || !synced { presenter.end() }
        shown = nil
        synced = true
    }

    /// `LockScreenState` → the activity's content.
    public static func content(_ s: LockScreenState) -> MatchActivityAttributes.ContentState {
        // A reading taken at `runningSince` (or frozen, when paused) puts the timer's origin here.
        let anchor = s.frameTimer.runningSince ?? Date()
        let start = anchor.addingTimeInterval(-s.frameTimer.accumulated)
        return MatchActivityAttributes.ContentState(
            matchID: s.matchID,
            sides: s.sides.map { .init(player: $0.id, name: $0.name, colour: $0.colour, frames: $0.frames, isBreaker: $0.isBreaker) },
            frameTimerStart: start,
            pausedAt: s.frameTimer.isRunning ? nil : anchor,
            canAward: s.controls.award, canPause: s.controls.pause, canResume: s.controls.resume)
    }
}

/// The lock-screen buttons, routed to the Matches use cases (`AwardFrame`, `PauseMatch`,
/// `ResumeMatch`). Commands are serialised on the main actor with the in-app ones, so a lock-screen
/// + and an in-app − apply in the order they arrive (Q4 is still deferred).
@MainActor
public final class LockScreenCommands: MatchActivityCommands {
    private let commands: any MatchCommands

    public init(commands: any MatchCommands) {
        self.commands = commands
    }

    public func awardFrame(match: UUID, to player: UUID) throws { try commands.awardFrame(match, to: player) }
    public func pauseMatch(_ match: UUID) throws { try commands.pauseMatch(match) }
    public func resumeMatch(_ match: UUID) throws { try commands.resumeMatch(match) }
}
