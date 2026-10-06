import Foundation

// Series value objects (spec 016). `Setup` is Matches' setup as published in `MatchStarted`
// (conformist, ADR-0003): Stats keeps its own copy of the shape and never imports Matches.

/// Opaque, non-empty series identifier.
public struct SeriesId: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: UUID

    /// A fresh id from a UUID supplied by the caller (the domain never generates one).
    public init(_ uuid: UUID) { value = uuid }

    public static func create(_ raw: String) -> Result<SeriesId, SeriesError> {
        guard let uuid = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(.invalidId(raw))
        }
        return .success(SeriesId(uuid))
    }

    public var description: String { value.uuidString }
}

/// A series' name: trimmed, never blank.
public struct SeriesName: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    private init(value: String) { self.value = value }

    public static func create(_ raw: String) -> Result<SeriesName, SeriesError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.blankName) }
        return .success(SeriesName(value: trimmed))
    }

    public var description: String { value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard case .success(let name) = Self.create(try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Blank SeriesName")
        }
        self = name
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// What a match is before play, as published in `MatchStarted`: two different players (unordered
/// for equality), the game, the style with its targets, and the break rule. Equality matches Matches'
/// setup equality (targets compare by race-to value), so a series covers every match of the setup.
public struct Setup: Hashable, Sendable, Codable {
    /// Race to N (frames or sets); "best of M" is kept for display only.
    public struct Target: Hashable, Sendable, Codable {
        public let raceTo: Int
        public let bestOf: Int?

        public init(raceTo: Int, bestOf: Int? = nil) { self.raceTo = raceTo; self.bestOf = bestOf }

        public static func == (lhs: Target, rhs: Target) -> Bool { lhs.raceTo == rhs.raceTo }
        public func hash(into hasher: inout Hasher) { hasher.combine(raceTo) }
    }

    public enum Style: Hashable, Sendable, Codable {
        case mostFramesWins
        case raceTo(Target)
        case sets(sets: Target, frames: Target)
    }

    /// Entry order, kept for laying out the sides.
    public let first: UUID
    public let second: UUID
    /// As published: "pool" or "snooker".
    public let game: String
    public let style: Style
    /// As published: "alternate" or "winnerBreaks".
    public let breakRule: String

    private init(first: UUID, second: UUID, game: String, style: Style, breakRule: String) {
        self.first = first; self.second = second; self.game = game; self.style = style; self.breakRule = breakRule
    }

    public static func create(
        _ first: UUID, _ second: UUID, game: String, style: Style, breakRule: String
    ) -> Result<Setup, SeriesError> {
        guard first != second else { return .failure(.samePlayer(first)) }
        return .success(Setup(first: first, second: second, game: game, style: style, breakRule: breakRule))
    }

    public var players: Set<UUID> { [first, second] }

    public func involves(_ player: UUID) -> Bool { first == player || second == player }

    /// The same setup with `player` replaced by `other` (a merge); nil if that would pit `other`
    /// against themselves.
    public func replacing(_ player: UUID, with other: UUID) -> Setup? {
        let a = first == player ? other : first
        let b = second == player ? other : second
        return try? Setup.create(a, b, game: game, style: style, breakRule: breakRule).get()
    }

    public static func == (lhs: Setup, rhs: Setup) -> Bool {
        lhs.players == rhs.players && lhs.game == rhs.game && lhs.style == rhs.style && lhs.breakRule == rhs.breakRule
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(players)
        hasher.combine(game)
        hasher.combine(style)
        hasher.combine(breakRule)
    }

    /// A stable text identity matching equality (players sorted, targets by value).
    public var key: String {
        let players = [first.uuidString, second.uuidString].sorted().joined(separator: "|")
        let style = switch style {
        case .mostFramesWins: "most"
        case .raceTo(let t): "race:\(t.raceTo)"
        case .sets(let sets, let frames): "sets:\(sets.raceTo):\(frames.raceTo)"
        }
        return [players, game, style, breakRule].joined(separator: "/")
    }

    private enum CodingKeys: String, CodingKey { case first, second, game, style, breakRule }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let result = Setup.create(
            try c.decode(UUID.self, forKey: .first), try c.decode(UUID.self, forKey: .second),
            game: try c.decode(String.self, forKey: .game), style: try c.decode(Style.self, forKey: .style),
            breakRule: try c.decode(String.self, forKey: .breakRule))
        guard case .success(let setup) = result else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Invalid Setup"))
        }
        self = setup
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

/// A calendar month (monthly summaries, spec 016 non-goal for now; S38).
public struct Month: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    /// 1...12.
    public let month: Int

    private init(year: Int, month: Int) { self.year = year; self.month = month }

    public static func create(year: Int, month: Int) -> Result<Month, SeriesError> {
        guard (1...12).contains(month) else { return .failure(.invalidMonth(month)) }
        return .success(Month(year: year, month: month))
    }

    /// The month `date` falls in, in `calendar`'s time zone.
    public static func containing(_ date: Date, calendar: Calendar = .current) -> Month {
        let c = calendar.dateComponents([.year, .month], from: date)
        return Month(year: c.year ?? 1970, month: c.month ?? 1)
    }

    public var previous: Month { month == 1 ? Month(year: year - 1, month: 12) : Month(year: year, month: month - 1) }
    public var next: Month { month == 12 ? Month(year: year + 1, month: 1) : Month(year: year, month: month + 1) }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        Month.containing(date, calendar: calendar) == self
    }

    public static func < (lhs: Month, rhs: Month) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }

    public var description: String { String(format: "%04d-%02d", year, month) }
}
