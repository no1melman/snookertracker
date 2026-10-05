import Foundation

// Facts on a match's stream, past tense. Each carries the time it happened (`at`), supplied by the
// caller, and enough data to rebuild the match without querying anything else.

public struct MatchStarted: Hashable, Sendable, Codable {
    public let matchId: MatchId
    public let setup: Setup
    /// The setup's first player with this match's colour.
    public let first: Side
    /// The setup's second player with this match's colour.
    public let second: Side
    /// Start time; also when the match and frame-1 timers start.
    public let at: Date

    public init(matchId: MatchId, setup: Setup, first: Side, second: Side, at: Date) {
        self.matchId = matchId; self.setup = setup; self.first = first; self.second = second; self.at = at
    }
}

public struct BreakerChosen: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let at: Date

    public init(player: PlayerId, at: Date) { self.player = player; self.at = at }
}

public struct BreakerCorrected: Hashable, Sendable, Codable {
    public let player: PlayerId
    /// The frame the corrected player is breaking now: the new break-rule origin.
    public let frameNumber: Int
    public let at: Date

    public init(player: PlayerId, frameNumber: Int, at: Date) {
        self.player = player; self.frameNumber = frameNumber; self.at = at
    }
}

public struct FrameWon: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let frameNumber: Int
    public let setNumber: Int
    /// Frame start → `at`, minus paused time.
    public let length: PlayDuration
    public let breaker: PlayerId?
    public let at: Date

    public init(player: PlayerId, frameNumber: Int, setNumber: Int, length: PlayDuration, breaker: PlayerId?, at: Date) {
        self.player = player; self.frameNumber = frameNumber; self.setNumber = setNumber
        self.length = length; self.breaker = breaker; self.at = at
    }
}

public struct SetWon: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let setNumber: Int
    /// Frames in that set, by the setup's first and second player.
    public let setScore: SetFrames
    public let at: Date

    public init(player: PlayerId, setNumber: Int, setScore: SetFrames, at: Date) {
        self.player = player; self.setNumber = setNumber; self.setScore = setScore; self.at = at
    }
}

public struct MatchTargetReached: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let score: Score
    public let at: Date

    public init(player: PlayerId, score: Score, at: Date) { self.player = player; self.score = score; self.at = at }
}

public struct FrameRemoved: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let frameNumber: Int
    public let setNumber: Int
    /// The set whose win this removal reverted, if any.
    public let revertedSetWin: Int?
    public let at: Date

    public init(player: PlayerId, frameNumber: Int, setNumber: Int, revertedSetWin: Int?, at: Date) {
        self.player = player; self.frameNumber = frameNumber; self.setNumber = setNumber
        self.revertedSetWin = revertedSetWin; self.at = at
    }
}

public struct MatchPaused: Hashable, Sendable, Codable {
    public let at: Date

    public init(at: Date) { self.at = at }
}

/// Stamped with the supplied pause time, which may be earlier than when it is raised (ADR-0004, ADR-0005).
public struct MatchAutoPaused: Hashable, Sendable, Codable {
    public let at: Date

    public init(at: Date) { self.at = at }
}

public struct MatchResumed: Hashable, Sendable, Codable {
    public let at: Date

    public init(at: Date) { self.at = at }
}

public struct MatchColourOverridden: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let colour: Colour
    public let at: Date

    public init(player: PlayerId, colour: Colour, at: Date) { self.player = player; self.colour = colour; self.at = at }
}


/// The match ended as finished (S10). `endedAt` may be earlier than `at`: the winning frame's time when
/// finished from AwaitingConfirmation, or the end chosen for a stale match.
public struct MatchFinished: Hashable, Sendable, Codable {
    public let result: MatchResult
    public let score: Score
    public let endedAt: Date
    /// Match length at the end (minus paused time), or the capped length for a stale match.
    public let length: PlayDuration
    /// A target style finished short of its target ("finish anyway").
    public let shortOfTarget: Bool
    public let at: Date

    public init(result: MatchResult, score: Score, endedAt: Date, length: PlayDuration, shortOfTarget: Bool, at: Date) {
        self.result = result; self.score = score; self.endedAt = endedAt
        self.length = length; self.shortOfTarget = shortOfTarget; self.at = at
    }
}

public struct MatchAbandoned: Hashable, Sendable, Codable {
    public let score: Score
    public let endedAt: Date
    public let length: PlayDuration
    public let at: Date

    public init(score: Score, endedAt: Date, length: PlayDuration, at: Date) {
        self.score = score; self.endedAt = endedAt; self.length = length; self.at = at
    }
}

public struct MatchCancelled: Hashable, Sendable, Codable {
    public let at: Date

    public init(at: Date) { self.at = at }
}

/// Stage 1: drives the stale-match prompt (S28). Not an action, so it doesn't reset the idle time.
public struct StaleMatchFlagged: Hashable, Sendable, Codable {
    /// Time since the last recorded action.
    public let idle: PlayDuration
    /// Match length if it ended now (minus paused time), shown beside the capped length.
    public let ranFor: PlayDuration
    public let suggestedEndTime: ChosenEndTime
    public let cappedLength: CappedLength
    public let at: Date

    public init(idle: PlayDuration, ranFor: PlayDuration, suggestedEndTime: ChosenEndTime, cappedLength: CappedLength, at: Date) {
        self.idle = idle; self.ranFor = ranFor; self.suggestedEndTime = suggestedEndTime
        self.cappedLength = cappedLength; self.at = at
    }
}

/// The current frame has run past a long-frame threshold (S37). Not an action, so it doesn't reset the idle time.
public struct LongFrameWarned: Hashable, Sendable, Codable {
    public let frameNumber: Int
    /// The threshold crossed: 30 min, 40 min, 50 min, …
    public let threshold: PlayDuration
    /// The frame's length (minus paused time) when warned.
    public let elapsed: PlayDuration
    public let at: Date

    public init(frameNumber: Int, threshold: PlayDuration, elapsed: PlayDuration, at: Date) {
        self.frameNumber = frameNumber; self.threshold = threshold; self.elapsed = elapsed; self.at = at
    }
}

/// A correction to an ended match's score (S29). The original events stay as they were.
public struct MatchScoreCorrected: Hashable, Sendable, Codable {
    public let before: Score
    public let after: Score
    public let correction: ScoreCorrection
    /// The recalculated result for a finished match; nil for an abandoned one.
    public let result: MatchResult?
    public let at: Date

    public init(before: Score, after: Score, correction: ScoreCorrection, result: MatchResult?, at: Date) {
        self.before = before; self.after = after; self.correction = correction; self.result = result; self.at = at
    }
}

/// An abandoned match turned finished (S31): whoever is ahead wins, level is a draw.
public struct MatchMarkedFinished: Hashable, Sendable, Codable {
    public let result: MatchResult
    public let at: Date

    public init(result: MatchResult, at: Date) { self.result = result; self.at = at }
}

public struct MatchDeleted: Hashable, Sendable, Codable {
    public let at: Date

    public init(at: Date) { self.at = at }
}

public enum MatchEvent: Hashable, Sendable, Codable {
    case matchStarted(MatchStarted)
    case breakerChosen(BreakerChosen)
    case breakerCorrected(BreakerCorrected)
    case frameWon(FrameWon)
    case setWon(SetWon)
    case matchTargetReached(MatchTargetReached)
    case frameRemoved(FrameRemoved)
    case matchPaused(MatchPaused)
    case matchAutoPaused(MatchAutoPaused)
    case matchResumed(MatchResumed)
    case matchColourOverridden(MatchColourOverridden)
    case matchFinished(MatchFinished)
    case matchAbandoned(MatchAbandoned)
    case matchCancelled(MatchCancelled)
    case staleMatchFlagged(StaleMatchFlagged)
    case longFrameWarned(LongFrameWarned)
    case matchScoreCorrected(MatchScoreCorrected)
    case matchMarkedFinished(MatchMarkedFinished)
    case matchDeleted(MatchDeleted)

    public var at: Date {
        switch self {
        case .matchStarted(let e): e.at
        case .breakerChosen(let e): e.at
        case .breakerCorrected(let e): e.at
        case .frameWon(let e): e.at
        case .setWon(let e): e.at
        case .matchTargetReached(let e): e.at
        case .frameRemoved(let e): e.at
        case .matchPaused(let e): e.at
        case .matchAutoPaused(let e): e.at
        case .matchResumed(let e): e.at
        case .matchColourOverridden(let e): e.at
        case .matchFinished(let e): e.at
        case .matchAbandoned(let e): e.at
        case .matchCancelled(let e): e.at
        case .staleMatchFlagged(let e): e.at
        case .longFrameWarned(let e): e.at
        case .matchScoreCorrected(let e): e.at
        case .matchMarkedFinished(let e): e.at
        case .matchDeleted(let e): e.at
        }
    }
}
