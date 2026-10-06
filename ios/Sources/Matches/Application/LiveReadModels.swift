import Foundation

/// A timer that may be running: freeze it by clearing `runningSince` (pause).
public struct TimerReading: Hashable, Sendable {
    public var accumulated: TimeInterval
    public var runningSince: Date?

    public init(accumulated: TimeInterval = 0, runningSince: Date? = nil) {
        self.accumulated = accumulated
        self.runningSince = runningSince
    }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public var isRunning: Bool { runningSince != nil }
}

public struct LiveSide: Identifiable, Hashable, Sendable {
    public let id: PlayerRef
    public var name: String
    public var colour: String
    public var frames: Int
    public var isBreaker: Bool

    public init(id: PlayerRef, name: String, colour: String, frames: Int, isBreaker: Bool) {
        self.id = id
        self.name = name
        self.colour = colour
        self.frames = frames
        self.isBreaker = isBreaker
    }
}

/// `LiveMatches` row (spec 009).
public struct LiveMatchRow: Identifiable, Hashable, Sendable {
    public let id: MatchID
    public var sides: [LiveSide]
    public var matchTimer: TimerReading
    public var isPaused: Bool
    public var startedAt: Date

    public init(id: MatchID, sides: [LiveSide], matchTimer: TimerReading, isPaused: Bool, startedAt: Date) {
        self.id = id
        self.sides = sides
        self.matchTimer = matchTimer
        self.isPaused = isPaused
        self.startedAt = startedAt
    }
}

/// `LiveMatchScreen` (spec 009). Head-to-head is not provided yet.
public struct LiveMatchScreen: Identifiable, Hashable, Sendable {
    public struct Controls: Hashable, Sendable {
        public var chooseBreaker: Bool
        public var award: Bool
        /// Players who have a frame that − can remove.
        public var removeFrom: Set<PlayerRef>
        public var pause: Bool
        public var resume: Bool

        public init(chooseBreaker: Bool, award: Bool, removeFrom: Set<PlayerRef>, pause: Bool, resume: Bool) {
            self.chooseBreaker = chooseBreaker
            self.award = award
            self.removeFrom = removeFrom
            self.pause = pause
            self.resume = resume
        }
    }

    public let id: MatchID
    public var startedAt: Date
    public var game: Game
    public var style: MatchStyle
    public var breakRule: BreakRule
    public var sides: [LiveSide]
    public var matchTimer: TimerReading
    public var frameTimer: TimerReading
    public var isPaused: Bool
    public var controls: Controls
    /// Set when a + reached the match target: the app asks before ending (Finish or Undo).
    public var targetReachedBy: PlayerRef?

    public init(
        id: MatchID, startedAt: Date, game: Game, style: MatchStyle, breakRule: BreakRule,
        sides: [LiveSide], matchTimer: TimerReading, frameTimer: TimerReading, isPaused: Bool,
        controls: Controls, targetReachedBy: PlayerRef?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.game = game
        self.style = style
        self.breakRule = breakRule
        self.sides = sides
        self.matchTimer = matchTimer
        self.frameTimer = frameTimer
        self.isPaused = isPaused
        self.controls = controls
        self.targetReachedBy = targetReachedBy
    }

    /// Frame currently being played, derived from the score.
    public var frameNumber: Int { sides.reduce(0) { $0 + $1.frames } + 1 }
}
