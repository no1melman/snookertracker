import Foundation

// Ports for the stale-match flow (S28, specs 015 and 020): `FlagStaleMatches` on launch, after
// `AutoPauseLiveMatches`, and `ResolveStaleMatch` from the prompt, one match at a time.

/// `FlagStaleMatches` + `ResolveStaleMatch`.
@MainActor public protocol StaleMatchCommands: AnyObject, Sendable {
    /// Flags each live match idle for 6 h or more and returns its prompt, in prompt order
    /// (oldest started first, as `findLive` returns them).
    func flagStaleMatches() throws -> [StaleMatchPrompt]
    /// Carries out the scorer's choice for one stale match. Ending a target style short of its target
    /// throws `MatchCommandError.finishShortOfTarget` unless `anyway` (then it counts as abandoned).
    /// A match that is no longer live or stale throws `StaleMatchError.noLongerStale`; an end time
    /// outside last action ≤ t ≤ now throws `StaleMatchError.endTimeOutOfBounds`.
    func resolveStaleMatch(_ match: MatchID, _ choice: StaleChoice, anyway: Bool) throws
}

public extension StaleMatchCommands {
    func resolveStaleMatch(_ match: MatchID, _ choice: StaleChoice) throws {
        try resolveStaleMatch(match, choice, anyway: false)
    }
}

/// The scorer's choice in the stale prompt (S28).
public enum StaleChoice: Hashable, Sendable {
    case resume
    /// End at a chosen time: last action ≤ t ≤ now (the prompt suggests one).
    case endAt(Date)
    /// End with the capped length: the same pair's same-weekday average, else 3 h.
    case endCapped
    case abandon
    case cancel
}

public enum StaleMatchError: LocalizedError, Equatable {
    /// The match ended, or was played, since it was flagged: there is nothing to resolve.
    case noLongerStale
    /// The chosen end time is before the last recorded action or after now.
    case endTimeOutOfBounds

    public var errorDescription: String? {
        switch self {
        case .noLongerStale: "This match is no longer waiting for an answer."
        case .endTimeOutOfBounds: "Pick a time between the last thing that happened in the match and now."
        }
    }
}

/// What the stale prompt shows for one match: the players and score, how long it has been idle, and
/// both lengths side by side ("Ran 1d 4h · Capped: 2h 45m (Fridays average)").
public struct StaleMatchPrompt: Identifiable, Hashable, Sendable {
    public struct Side: Identifiable, Hashable, Sendable {
        public let id: PlayerRef
        public let name: String
        public let colour: String
        public let frames: Int

        public init(id: PlayerRef, name: String, colour: String, frames: Int) {
            self.id = id; self.name = name; self.colour = colour; self.frames = frames
        }
    }

    public let id: MatchID
    public let sides: [Side]
    /// "3 – 2", or "(1) 2 – 1 (0)" for sets.
    public let score: String
    public let startedAt: Date
    public let isPaused: Bool
    /// Time since the last recorded action.
    public let idle: TimeInterval
    /// The match length if it ended at the flag time (minus paused time).
    public let ranFor: TimeInterval
    /// The capped length offered by "End capped".
    public let cappedLength: TimeInterval
    /// True when the cap is the same pair's average on `weekday`; false for the 3 h fallback.
    public let cappedFromHistory: Bool
    /// The start's `Calendar` weekday (1 = Sunday … 7 = Saturday), the cap's weekday.
    public let weekday: Int
    /// The suggested end: the last frame's time + the average frame time of whoever won it.
    public let suggestedEndTime: Date
    /// The bounds an end time must fall within: the last recorded action and the flag time.
    public let earliestEndTime: Date
    public let latestEndTime: Date
    /// Abandon and Cancel are refused while a match waits on a target confirmation.
    public let canAbandonOrCancel: Bool

    public init(
        id: MatchID, sides: [Side], score: String, startedAt: Date, isPaused: Bool, idle: TimeInterval,
        ranFor: TimeInterval, cappedLength: TimeInterval, cappedFromHistory: Bool, weekday: Int,
        suggestedEndTime: Date, earliestEndTime: Date, latestEndTime: Date, canAbandonOrCancel: Bool
    ) {
        self.id = id; self.sides = sides; self.score = score; self.startedAt = startedAt
        self.isPaused = isPaused; self.idle = idle; self.ranFor = ranFor; self.cappedLength = cappedLength
        self.cappedFromHistory = cappedFromHistory; self.weekday = weekday
        self.suggestedEndTime = suggestedEndTime; self.earliestEndTime = earliestEndTime
        self.latestEndTime = latestEndTime; self.canAbandonOrCancel = canAbandonOrCancel
    }
}
