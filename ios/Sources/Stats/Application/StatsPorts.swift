import Foundation
import MatchesPublished

// MARK: - Persistence ports (implemented in StatsInfrastructure)

/// Stats' own copy of every published match event it has taken in: the source its projections are
/// rebuilt from, de-duplicated by event id, plus a per-stream checkpoint for catch-up.
public protocol StatsEventLog: Sendable {
    /// Stores the event; false when it was already stored (same event id).
    func append(_ event: MatchEventPublished) throws -> Bool
    /// One match's stored events, in stream order.
    func events(of match: UUID) throws -> [MatchEventPublished]
    func loggedMatches() throws -> [UUID]
    /// The highest Matches stream version taken in, per match.
    func checkpoints() throws -> [UUID: Int]
    func setCheckpoint(_ match: UUID, version: Int) throws
}

public protocol MatchRecordStore: Sendable {
    func save(_ record: MatchRecord) throws
    func deleteRecord(_ match: UUID) throws
    func deleteAllRecords() throws
    func allRecords() throws -> [MatchRecord]
}

/// What Stats knows about a player, from the player events.
public struct StatsPlayer: Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colour: String
    public var isArchived: Bool
    public var isRemoved: Bool
    /// Set when this player was folded into another by a merge.
    public var mergedInto: UUID?

    public init(id: UUID, name: String, colour: String, isArchived: Bool = false, isRemoved: Bool = false, mergedInto: UUID? = nil) {
        self.id = id; self.name = name; self.colour = colour
        self.isArchived = isArchived; self.isRemoved = isRemoved; self.mergedInto = mergedInto
    }
}

public protocol StatsPlayerStore: Sendable {
    func save(_ player: StatsPlayer) throws
    func allPlayers() throws -> [StatsPlayer]
}

public protocol StatsTransactions: Sendable {
    /// All of `body` commits, or none of it.
    func inTransaction<T>(_ body: () throws -> T) throws -> T
}

public typealias StatsStore = StatsEventLog & MatchRecordStore & StatsPlayerStore & StatsTransactions

// MARK: - Read models (spec 013)

public struct HistoryPlayer: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// Palette key (DesignSystem `PlayerColour` raw value); `noColour` (empty) while Free, when
    /// colours aren't shown. The stored colour is kept, just left out of the read (ADR-0010).
    public let colour: String
    public let isArchived: Bool

    public init(id: UUID, name: String, colour: String, isArchived: Bool) {
        self.id = id; self.name = name; self.colour = colour; self.isArchived = isArchived
    }

    public static let noColour = ""
    public var showsColour: Bool { colour != Self.noColour }

    /// As shown under an edition: the colour only when `colours` are shown (Free: none).
    public func showing(colours: Bool) -> HistoryPlayer {
        colours ? self : HistoryPlayer(id: id, name: name, colour: Self.noColour, isArchived: isArchived)
    }
}

public enum PastMatchStatus: String, Hashable, Sendable { case finished, abandoned, cancelled }

/// A score as shown: frames, and sets for the sets style.
public struct ScoreLine: Hashable, Sendable {
    public let first: Int
    public let second: Int
    public let firstSets: Int?
    public let secondSets: Int?

    public init(first: Int, second: Int, firstSets: Int? = nil, secondSets: Int? = nil) {
        self.first = first; self.second = second; self.firstSets = firstSets; self.secondSets = secondSets
    }

    /// "5–3", or "2–1 (9–7)" for sets.
    public var text: String {
        if let a = firstSets, let b = secondSets { return "\(a)–\(b) (\(first)–\(second))" }
        return "\(first)–\(second)"
    }
}

/// `PastMatches` row: day + time, players, score, style, finished or abandoned.
public struct PastMatchRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    /// Match length, minus paused time.
    public let length: TimeInterval?
    /// "pool" or "snooker".
    public let game: String
    /// "Race to 5", "Best of 7", "Most frames", "Best of 3 sets · race to 3".
    public let style: String
    public let first: HistoryPlayer
    public let second: HistoryPlayer
    /// The score as it stands (after any correction).
    public let score: ScoreLine
    public let status: PastMatchStatus
    /// nil for a draw, an abandoned or a cancelled match.
    public let winner: UUID?
    public let isDraw: Bool
    /// The score was corrected.
    public let isAltered: Bool
}

public struct PastMatchesFilter: Hashable, Sendable {
    public var showCancelled: Bool
    public var includeArchivedPlayers: Bool

    public init(showCancelled: Bool = false, includeArchivedPlayers: Bool = true) {
        self.showCancelled = showCancelled
        self.includeArchivedPlayers = includeArchivedPlayers
    }
}

/// `MatchTimeline`: per frame, the winner, frame time, match time then and the running score.
public struct MatchTimeline: Hashable, Sendable {
    public struct FrameEntry: Hashable, Sendable, Identifiable {
        public var id: Int { number }
        public let number: Int
        public let setNumber: Int
        public let winner: HistoryPlayer
        public let breaker: HistoryPlayer?
        public let frameTime: TimeInterval
        /// Match time when the frame was won.
        public let matchTime: TimeInterval
        public let runningScore: ScoreLine
        /// This frame won its set (sets style).
        public let wonSet: Bool
    }

    public struct CorrectionEntry: Hashable, Sendable {
        public let at: Date
        public let before: ScoreLine
        public let after: ScoreLine
    }

    public let match: PastMatchRow
    public let breakRule: String
    public let isSets: Bool
    public let frames: [FrameEntry]
    /// The score the match ended with; differs from `match.score` when corrected.
    public let originalScore: ScoreLine?
    public let corrections: [CorrectionEntry]
    public let markedFinishedAt: Date?
    public let shortOfTarget: Bool
}

/// `PastMatches` + `MatchTimeline`. Reading either is observation-tracked, so views refresh as
/// events arrive.
@MainActor public protocol MatchHistoryQuery: AnyObject, Sendable {
    /// Ended matches, newest first. Free: only those among the newest `FreeLimits.visibleEndedMatches`
    /// ended matches (S17); all on unlock.
    func pastMatches(_ filter: PastMatchesFilter) -> [PastMatchRow]
    /// How many rows `filter` would show that the Free edition hides (History's "hidden" row, which
    /// opens the upgrade offer); 0 once Unlocked.
    func hiddenMatchCount(_ filter: PastMatchesFilter) -> Int
    /// nil for a live, unknown or deleted match, and while Free for a hidden one.
    func timeline(_ match: UUID) -> MatchTimeline?
}
