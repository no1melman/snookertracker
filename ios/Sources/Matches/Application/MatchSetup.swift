import Foundation

// Application-layer vocabulary for the Matches ports (spec 002: presentation sees only this layer).
// Names follow docs/ddd-requirements.md; the domain module has its own richer types.

public typealias MatchID = UUID
/// A Players-context player id, as Matches sees it (customer/supplier).
public typealias PlayerRef = UUID

public enum Game: String, CaseIterable, Hashable, Sendable {
    case pool, snooker

    public var title: String { self == .pool ? "Pool" : "Snooker" }
}

/// Style with targets as entered: "race to" or "best of" (odd numbers only), or most frames wins.
public enum MatchStyle: Hashable, Sendable {
    case mostFramesWins
    case raceTo(Int)
    case bestOf(Int)

    /// Frames a player needs to win, or nil when the match only ends by Finish.
    public var framesToWin: Int? {
        switch self {
        case .mostFramesWins: nil
        case .raceTo(let n): n
        case .bestOf(let n): n / 2 + 1
        }
    }

    public var title: String {
        switch self {
        case .mostFramesWins: "Most frames wins"
        case .raceTo(let n): "Race to \(n)"
        case .bestOf(let n): "Best of \(n)"
        }
    }

    public var isValid: Bool {
        switch self {
        case .mostFramesWins: true
        case .raceTo(let n): n >= 1
        case .bestOf(let n): n >= 1 && n % 2 == 1
        }
    }
}

public enum BreakRule: String, CaseIterable, Hashable, Sendable {
    case alternate, winnerBreaks

    public var title: String { self == .alternate ? "Alternate" : "Winner breaks" }
}

public struct MatchSetup: Hashable, Sendable {
    public var players: [PlayerRef]
    public var game: Game
    public var style: MatchStyle
    public var breakRule: BreakRule

    public init(players: [PlayerRef], game: Game, style: MatchStyle, breakRule: BreakRule) {
        self.players = players
        self.game = game
        self.style = style
        self.breakRule = breakRule
    }
}

/// `MatchDefaults` (spec 007): what New Game opens with.
public struct MatchDefaults: Hashable, Sendable {
    public var game: Game
    public var style: MatchStyle
    public var breakRule: BreakRule

    public init(game: Game = .pool, style: MatchStyle = .mostFramesWins, breakRule: BreakRule = .alternate) {
        self.game = game
        self.style = style
        self.breakRule = breakRule
    }
}

public enum MatchCommandError: LocalizedError, Equatable {
    case samePlayerTwice
    case invalidTargets
    case liveMatchLimitReached(Int)
    case notAllowedNow
    /// A target style is short of its target: finishing now records the match as abandoned.
    case finishShortOfTarget
    /// The match was changed elsewhere since it was loaded; reload and try again.
    case changedElsewhere

    public var errorDescription: String? {
        switch self {
        case .samePlayerTwice: "A player can't play themselves."
        case .invalidTargets: "Best of needs an odd number of frames."
        case .liveMatchLimitReached(let n): "You already have \(n) live matches. Finish one, or raise the limit in Settings."
        case .notAllowedNow: "That isn't possible right now."
        case .finishShortOfTarget: "Nobody has reached the target yet. Finishing now counts the match as abandoned."
        case .changedElsewhere: "The match changed while you were scoring. Try again."
        }
    }
}
