import Foundation

// MARK: - Stats(filter) read models (spec 014: S18, S19)

/// A day of the week, read from a match's start time. Raw values are `Calendar` weekdays.
public enum Weekday: Int, CaseIterable, Hashable, Sendable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public init(of date: Date, in calendar: Calendar) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    /// Monday first, as the week reads at the club.
    public static let week: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// "Fridays".
    public var plural: String { title + "s" }

    var order: Int { Self.week.firstIndex(of: self) ?? 0 }
}

public struct StatsGrouping: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let opponent = StatsGrouping(rawValue: 1)
    public static let weekday = StatsGrouping(rawValue: 2)
}

/// `Stats(filter)`. Inclusion: finished matches always; abandoned only with `includeAbandoned`;
/// cancelled and live never; matches with an archived player only with `includeArchivedPlayers`;
/// a removed player's matches never.
public struct StatsFilter: Hashable, Sendable {
    /// Whose figures these are: Me (`WhoAmI`, resolved by the caller) or a chosen player.
    public var pointOfView: UUID
    public var opponent: UUID?
    public var weekday: Weekday?
    /// "pool" or "snooker".
    public var game: String?
    public var style: MatchRecord.Style?
    /// Matches that started inside this interval.
    public var dates: DateInterval?
    public var includeAbandoned: Bool
    public var includeArchivedPlayers: Bool
    /// The series filter (spec 016): only matches whose setup (merges followed) is one of the series. nil: any.
    public var series: SeriesFilter?
    public var grouping: StatsGrouping

    public init(
        pointOfView: UUID, opponent: UUID? = nil, weekday: Weekday? = nil, game: String? = nil,
        style: MatchRecord.Style? = nil, dates: DateInterval? = nil, includeAbandoned: Bool = false,
        includeArchivedPlayers: Bool = false, series: SeriesFilter? = nil, grouping: StatsGrouping = []
    ) {
        self.pointOfView = pointOfView; self.opponent = opponent; self.weekday = weekday; self.game = game
        self.style = style; self.dates = dates; self.includeAbandoned = includeAbandoned
        self.includeArchivedPlayers = includeArchivedPlayers; self.series = series; self.grouping = grouping
    }
}

/// The figures for one group, from the point of view's side.
public struct StatsFigures: Hashable, Sendable {
    public var won = 0
    public var drawn = 0
    public var lost = 0
    /// Abandoned matches counted (frames, deciders and times only; no result).
    public var abandoned = 0
    public var framesWon = 0
    public var framesLost = 0
    /// Decider frames (match deciders included).
    public var decidersWon = 0
    public var decidersLost = 0
    public var matchDecidersWon = 0
    public var matchDecidersLost = 0
    /// Deciding sets played with sets level: their own tally.
    public var setDecidersWon = 0
    public var setDecidersLost = 0
    var frameTime = Average()
    var frameTimeWon = Average()
    var frameTimeLost = Average()

    public init() {}

    /// Matches counted, abandoned included.
    public var matches: Int { won + drawn + lost + abandoned }
    /// Won ÷ (won + drawn + lost); nil with no result yet.
    public var winPercentage: Double? {
        let results = won + drawn + lost
        return results == 0 ? nil : Double(won) / Double(results) * 100
    }
    public var averageFrameTime: TimeInterval? { frameTime.value }
    /// Average length of the frames the point of view won.
    public var averageFrameTimeWon: TimeInterval? { frameTimeWon.value }
    /// Average length of the frames the opponents won.
    public var averageFrameTimeLost: TimeInterval? { frameTimeLost.value }

    struct Average: Hashable, Sendable {
        var total: TimeInterval = 0
        var count = 0
        mutating func add(_ t: TimeInterval) { total += t; count += 1 }
        static func + (l: Average, r: Average) -> Average { Average(total: l.total + r.total, count: l.count + r.count) }
        var value: TimeInterval? { count == 0 ? nil : total / Double(count) }
    }

    static func + (l: StatsFigures, r: StatsFigures) -> StatsFigures {
        var s = StatsFigures()
        s.won = l.won + r.won; s.drawn = l.drawn + r.drawn; s.lost = l.lost + r.lost; s.abandoned = l.abandoned + r.abandoned
        s.framesWon = l.framesWon + r.framesWon; s.framesLost = l.framesLost + r.framesLost
        s.decidersWon = l.decidersWon + r.decidersWon; s.decidersLost = l.decidersLost + r.decidersLost
        s.matchDecidersWon = l.matchDecidersWon + r.matchDecidersWon; s.matchDecidersLost = l.matchDecidersLost + r.matchDecidersLost
        s.setDecidersWon = l.setDecidersWon + r.setDecidersWon; s.setDecidersLost = l.setDecidersLost + r.setDecidersLost
        s.frameTime = l.frameTime + r.frameTime
        s.frameTimeWon = l.frameTimeWon + r.frameTimeWon
        s.frameTimeLost = l.frameTimeLost + r.frameTimeLost
        return s
    }
}

/// One group: an opponent, a weekday, or both ("Asher on Fridays").
public struct StatsGroup: Identifiable, Hashable, Sendable {
    public struct Key: Hashable, Sendable {
        public let opponent: UUID?
        public let weekday: Weekday?
    }

    public var id: Key { Key(opponent: opponent?.id, weekday: weekday) }
    public let opponent: HistoryPlayer?
    public let weekday: Weekday?
    public let figures: StatsFigures
}

public struct StatsReport: Hashable, Sendable {
    public let pointOfView: HistoryPlayer?
    /// Every counted match.
    public let overall: StatsFigures
    /// Per the filter's grouping; most matches first (by weekday: Monday first). Empty when ungrouped.
    public let groups: [StatsGroup]
}

/// What the Stats screen's filters can offer for a point of view.
public struct StatsChoices: Hashable, Sendable {
    public struct StyleChoice: Hashable, Sendable, Identifiable {
        public var id: String { text }
        public let style: MatchRecord.Style
        /// "Race to 5".
        public let text: String
    }

    /// Opponents the point of view has played, by name.
    public let opponents: [HistoryPlayer]
    public let games: [String]
    public let styles: [StyleChoice]
}

/// `Stats(filter)` and the choices behind its filters. Observation-tracked, like `MatchHistoryQuery`.
@MainActor public protocol StatsQuery: AnyObject, Sendable {
    func stats(_ filter: StatsFilter) -> StatsReport
    /// Players who can be the point of view: everyone not removed or merged away, by name.
    func statsPlayers(includeArchived: Bool) -> [HistoryPlayer]
    func statsChoices(for pointOfView: UUID, includeArchivedPlayers: Bool) -> StatsChoices
}
