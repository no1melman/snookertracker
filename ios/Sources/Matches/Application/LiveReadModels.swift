import Foundation
import StatsPublished

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
    /// Palette key; `noColour` (empty) while Free, when colours aren't shown.
    public var colour: String
    /// Total frames won in the match.
    public var frames: Int
    public var isBreaker: Bool
    /// Sets style only: sets won and frames in the current set; nil otherwise.
    public var sets: SetsScore?

    public struct SetsScore: Hashable, Sendable {
        public var setsWon: Int
        public var currentSetFrames: Int

        public init(setsWon: Int, currentSetFrames: Int) {
            self.setsWon = setsWon
            self.currentSetFrames = currentSetFrames
        }
    }

    public init(id: PlayerRef, name: String, colour: String, frames: Int, isBreaker: Bool, sets: SetsScore? = nil) {
        self.id = id
        self.name = name
        self.colour = colour
        self.frames = frames
        self.isBreaker = isBreaker
        self.sets = sets
    }

    /// The colour of a side while Free: none shown (ADR-0010).
    public static let noColour = ""
    public var showsColour: Bool { colour != Self.noColour }

    /// The big number on the live screen: the current set's frames for sets, else total frames.
    public var scoreFrames: Int { sets?.currentSetFrames ?? frames }
}

/// The score as the live screen reads it (S16): "(1) 5 – 2 (0)" for sets (sets won in brackets,
/// current-set frames in the middle), else "5 – 2".
public func liveScoreText(_ sides: [LiveSide]) -> String {
    guard sides.count == 2 else { return "" }
    let (a, b) = (sides[0], sides[1])
    if let sa = a.sets, let sb = b.sets {
        return "(\(sa.setsWon)) \(sa.currentSetFrames) – \(sb.currentSetFrames) (\(sb.setsWon))"
    }
    return "\(a.frames) – \(b.frames)"
}

/// The score as VoiceOver reads it: "Asher 4, Me 3", or for sets "Asher 2 (1 set), Me 0 (0 sets)".
public func spokenLiveScore(_ sides: [LiveSide]) -> String {
    sides.map { side in
        if let s = side.sets {
            "\(side.name) \(s.currentSetFrames) (\(s.setsWon) \(s.setsWon == 1 ? "set" : "sets"))"
        } else {
            "\(side.name) \(side.frames)"
        }
    }
    .joined(separator: ", ")
}

/// The all-time head-to-head on the live screen (S14), from the first side's point of view.
/// Adapted from Stats' `HeadToHead` open-host query (`LiveHeadToHead.lookup`).
public struct LiveHeadToHead: Hashable, Sendable {
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let framesWon: Int
    public let framesLost: Int
    public let decidersWon: Int
    public let decidersLost: Int

    public init(won: Int, drawn: Int, lost: Int, framesWon: Int, framesLost: Int, decidersWon: Int, decidersLost: Int) {
        self.won = won; self.drawn = drawn; self.lost = lost
        self.framesWon = framesWon; self.framesLost = framesLost
        self.decidersWon = decidersWon; self.decidersLost = decidersLost
    }

    /// No finished match between the two: the strip is hidden.
    public var isEmpty: Bool { won + drawn + lost == 0 }
    /// Deciders are shown only when there is a value.
    public var showsDeciders: Bool { decidersWon + decidersLost > 0 }
}

/// `HeadToHead(first, second)` for the live screen.
public typealias HeadToHeadLookup = @MainActor @Sendable (PlayerRef, PlayerRef) -> LiveHeadToHead

public extension LiveHeadToHead {
    init(_ h: HeadToHead) {
        self.init(won: h.won, drawn: h.drawn, lost: h.lost, framesWon: h.framesWon, framesLost: h.framesLost,
                  decidersWon: h.decidersWon, decidersLost: h.decidersLost)
    }

    /// The live screen's lookup over Stats' open-host query (ADR-0003); the composition root hands
    /// it to `MatchesPorts.headToHead`.
    static func lookup(_ stats: any MatchStatsQueries) -> HeadToHeadLookup {
        { a, b in LiveHeadToHead(stats.headToHead(a, b)) }
    }
}

/// The set just won while the match carries on (S16): the app asks "Continue?" with Undo.
public struct SetWonPrompt: Hashable, Sendable {
    public let winner: PlayerRef
    public let setNumber: Int

    public init(winner: PlayerRef, setNumber: Int) {
        self.winner = winner
        self.setNumber = setNumber
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

/// `LiveMatchScreen` (spec 009). The head-to-head comes from Stats through `HeadToHeadLookup`
/// (`MatchesPorts.headToHead`), not from this projection.
public struct LiveMatchScreen: Identifiable, Hashable, Sendable {
    public struct Controls: Hashable, Sendable {
        public var chooseBreaker: Bool
        public var award: Bool
        /// Players who have a frame that − can remove.
        public var removeFrom: Set<PlayerRef>
        public var pause: Bool
        public var resume: Bool
        /// Correct breaker (S41): in play or paused, once a breaker has been chosen.
        public var correctBreaker: Bool
        /// Free: pausing by hand is paid, so the pause button shows "Upgrade now" (S7, S52).
        public var pauseOffersUpgrade: Bool
        /// Free: a match paused by hand can't be resumed (an automatic pause can, S8, S27).
        public var resumeOffersUpgrade: Bool

        public init(
            chooseBreaker: Bool, award: Bool, removeFrom: Set<PlayerRef>, pause: Bool, resume: Bool,
            correctBreaker: Bool = false, pauseOffersUpgrade: Bool = false, resumeOffersUpgrade: Bool = false
        ) {
            self.chooseBreaker = chooseBreaker
            self.award = award
            self.removeFrom = removeFrom
            self.pause = pause
            self.resume = resume
            self.correctBreaker = correctBreaker
            self.pauseOffersUpgrade = pauseOffersUpgrade
            self.resumeOffersUpgrade = resumeOffersUpgrade
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
    /// Set when the last + won a set short of the match (S16): the app asks "Continue?" (or Undo).
    /// Clears once the next frame is scored or the set win is undone.
    public var setWon: SetWonPrompt?
    /// Both sides share a colour and no breaker is chosen yet (S46): the app offers a temporary colour.
    /// Never while Free (no colours are shown).
    public var coloursClash: Bool
    /// Free: false, and the sides carry no colour (ADR-0010).
    public var showsColours: Bool
    /// Free: the head-to-head (S14) is greyed with an upgrade prompt instead of the figures.
    public var headToHeadLocked: Bool

    public init(
        id: MatchID, startedAt: Date, game: Game, style: MatchStyle, breakRule: BreakRule,
        sides: [LiveSide], matchTimer: TimerReading, frameTimer: TimerReading, isPaused: Bool,
        controls: Controls, targetReachedBy: PlayerRef?, setWon: SetWonPrompt? = nil, coloursClash: Bool = false,
        showsColours: Bool = true, headToHeadLocked: Bool = false
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
        self.setWon = setWon
        self.coloursClash = coloursClash
        self.showsColours = showsColours
        self.headToHeadLocked = headToHeadLocked
    }

    /// "(1) 5 – 2 (0)" for sets, else "5 – 2".
    public var scoreText: String { liveScoreText(sides) }

    /// Frame currently being played, derived from the score.
    public var frameNumber: Int { sides.reduce(0) { $0 + $1.frames } + 1 }
}
