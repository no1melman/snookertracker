import Foundation

public enum UseCountError: Error, Equatable, Sendable {
    case notPositive(Int)
}

/// How many times a template's setup has been played; ≥ 1.
public struct UseCount: Hashable, Comparable, Sendable, Codable {
    public let value: Int

    private init(value: Int) { self.value = value }

    public static let one = UseCount(value: 1)

    public static func create(_ value: Int) -> Result<UseCount, UseCountError> {
        guard value >= 1 else { return .failure(.notPositive(value)) }
        return .success(UseCount(value: value))
    }

    public func incremented() -> UseCount { UseCount(value: value + 1) }
    public func adding(_ other: UseCount) -> UseCount { UseCount(value: value + other.value) }

    public static func < (lhs: UseCount, rhs: UseCount) -> Bool { lhs.value < rhs.value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard case .success(let u) = UseCount.create(try c.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "UseCount < 1")
        }
        self = u
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// Defaults for starting a match. Targets are valid by construction (`Target`).
public struct MatchDefaults: Hashable, Sendable, Codable {
    public let game: Game
    public let style: MatchStyle
    public let breakRule: BreakRule

    public init(game: Game, style: MatchStyle, breakRule: BreakRule) {
        self.game = game
        self.style = style
        self.breakRule = breakRule
    }

    /// pool, most frames wins, alternate breaks.
    public static let initial = MatchDefaults(game: .pool, style: .mostFramesWins, breakRule: .alternate)
}

public enum LiveMatchLimitError: Error, Equatable, Sendable {
    case outOfRange(Int)
}

/// How many matches may be live at once: 1…100, default 10.
public struct LiveMatchLimit: Hashable, Sendable, Codable {
    public static let range = 1...100

    public let value: Int

    private init(value: Int) { self.value = value }

    public static let standard = LiveMatchLimit(value: 10)

    public static func create(_ value: Int) -> Result<LiveMatchLimit, LiveMatchLimitError> {
        guard range.contains(value) else { return .failure(.outOfRange(value)) }
        return .success(LiveMatchLimit(value: value))
    }

    /// Whether another match may start while `liveCount` are live.
    public func allowsAnother(liveCount: Int) -> Bool { liveCount < value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard case .success(let l) = LiveMatchLimit.create(try c.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "LiveMatchLimit out of 1…100")
        }
        self = l
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
