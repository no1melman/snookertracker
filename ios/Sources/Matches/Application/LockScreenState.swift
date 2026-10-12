import Foundation

/// `LockScreenState` (spec 009, S47, ADR-0004): the one live match the lock screen shows, which is
/// the oldest live match (as `findLive`), or none. When it ends, the next-oldest takes its place.
public struct LockScreenState: Hashable, Sendable {
    /// What the lock-screen buttons may do right now (the matching use case would refuse otherwise).
    public struct Controls: Hashable, Sendable {
        public var award: Bool
        public var pause: Bool
        public var resume: Bool

        public init(award: Bool, pause: Bool, resume: Bool) {
            self.award = award
            self.pause = pause
            self.resume = resume
        }
    }

    public let matchID: MatchID
    /// Both sides: name, colour, frames (the score) and the breaker dot.
    public var sides: [LiveSide]
    public var frameTimer: TimerReading
    public var isPaused: Bool
    public var controls: Controls

    public init(matchID: MatchID, sides: [LiveSide], frameTimer: TimerReading, isPaused: Bool, controls: Controls) {
        self.matchID = matchID
        self.sides = sides
        self.frameTimer = frameTimer
        self.isPaused = isPaused
        self.controls = controls
    }
}

/// Query port for `LockScreenState`; nil when no match is live.
@MainActor public protocol LockScreenStateQuery: AnyObject, Sendable {
    var lockScreenState: LockScreenState? { get }
}

/// `LockScreenState` is a view over the live-match projection: its oldest row, so the hand-over
/// to the next-oldest happens as soon as the shown match leaves the projection. Unlocked only:
/// none while Free (S47, ADR-0010), so no Live Activity is shown.
extension LiveMatchesProjection: LockScreenStateQuery {
    public var lockScreenState: LockScreenState? {
        guard edition.allows(.lockScreen) else { return nil }
        guard let oldest = liveMatches.first, let screen = liveMatchScreen(oldest.id) else { return nil }
        return LockScreenState(
            matchID: screen.id, sides: screen.sides, frameTimer: screen.frameTimer, isPaused: screen.isPaused,
            controls: .init(award: screen.controls.award, pause: screen.controls.pause, resume: screen.controls.resume))
    }
}
