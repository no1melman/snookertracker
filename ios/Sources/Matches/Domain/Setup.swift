import Foundation

public enum Game: String, Hashable, Sendable, Codable, CaseIterable {
    case pool
    case snooker
}

public enum BreakRule: String, Hashable, Sendable, Codable, CaseIterable {
    case alternate
    case winnerBreaks

    public static let standard: BreakRule = .alternate
}

public enum MatchStyle: Hashable, Sendable, Codable {
    /// Open-ended; draws possible.
    case mostFramesWins
    case raceTo(Target)
    /// Race to `sets` sets, each a race to `frames` frames.
    case sets(sets: Target, frames: Target)
}

public enum SetupError: Error, Equatable, Sendable {
    /// Nobody plays themselves.
    case samePlayer(PlayerId)
}

/// What a match is before play. Players are unordered for equality; equality is template identity.
/// `first`/`second` keep the entry order only for laying out the sides.
public struct Setup: Hashable, Sendable, Codable {
    public let first: PlayerId
    public let second: PlayerId
    public let game: Game
    public let style: MatchStyle
    public let breakRule: BreakRule

    private init(first: PlayerId, second: PlayerId, game: Game, style: MatchStyle, breakRule: BreakRule) {
        self.first = first
        self.second = second
        self.game = game
        self.style = style
        self.breakRule = breakRule
    }

    public static func create(
        _ first: PlayerId, _ second: PlayerId,
        game: Game, style: MatchStyle, breakRule: BreakRule = .standard
    ) -> Result<Setup, SetupError> {
        guard first != second else { return .failure(.samePlayer(first)) }
        return .success(Setup(first: first, second: second, game: game, style: style, breakRule: breakRule))
    }

    public var players: Set<PlayerId> { [first, second] }

    public static func == (lhs: Setup, rhs: Setup) -> Bool {
        lhs.players == rhs.players && lhs.game == rhs.game && lhs.style == rhs.style && lhs.breakRule == rhs.breakRule
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(players)
        hasher.combine(game)
        hasher.combine(style)
        hasher.combine(breakRule)
    }

    private enum CodingKeys: String, CodingKey { case first, second, game, style, breakRule }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let result = Setup.create(
            try c.decode(PlayerId.self, forKey: .first),
            try c.decode(PlayerId.self, forKey: .second),
            game: try c.decode(Game.self, forKey: .game),
            style: try c.decode(MatchStyle.self, forKey: .style),
            breakRule: try c.decode(BreakRule.self, forKey: .breakRule))
        switch result {
        case .success(let s): self = s
        case .failure(let e):
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Invalid Setup: \(e)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(first, forKey: .first)
        try c.encode(second, forKey: .second)
        try c.encode(game, forKey: .game)
        try c.encode(style, forKey: .style)
        try c.encode(breakRule, forKey: .breakRule)
    }
}
