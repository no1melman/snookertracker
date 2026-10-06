import Foundation
import StatsDomain

// Series membership (spec 016): a match belongs to a series when its setup is one of the series'
// setups, whenever it was played. Nothing is stored per match; this resolves it at read time, for
// the series filter in `Stats(filter)` (spec 014) and the monthly summary (S38).

public extension Setup {
    /// The setup a recorded match was started with. `resolve` maps a player to the one they are now
    /// (a folded-in player to the kept one), because Stats' records keep the original player ids.
    static func of(_ record: MatchRecord, resolve: (UUID) -> UUID = { $0 }) -> Setup? {
        let style: Setup.Style = switch record.style {
        case .mostFramesWins: .mostFramesWins
        case .raceTo(let t): .raceTo(Setup.Target(raceTo: t.raceTo, bestOf: t.bestOf))
        case .sets(let s, let f):
            .sets(sets: Setup.Target(raceTo: s.raceTo, bestOf: s.bestOf), frames: Setup.Target(raceTo: f.raceTo, bestOf: f.bestOf))
        }
        return try? Setup.create(resolve(record.first.player), resolve(record.second.player),
                                 game: record.game, style: style, breakRule: record.breakRule).get()
    }
}

/// The series filter: the setups a series covers.
public struct SeriesFilter: Hashable, Sendable {
    public let seriesId: UUID
    public let name: String
    public let setups: Set<Setup>

    public init(seriesId: UUID, name: String, setups: Set<Setup>) {
        self.seriesId = seriesId; self.name = name; self.setups = setups
    }

    /// Whether `record` (past or future) belongs to the series.
    public func contains(_ record: MatchRecord, resolve: (UUID) -> UUID = { $0 }) -> Bool {
        Setup.of(record, resolve: resolve).map(setups.contains) ?? false
    }

    /// Follows merges: a folded-in player resolves to the player they were folded into.
    public static func followingMerges(_ players: [StatsPlayer]) -> @Sendable (UUID) -> UUID {
        let mergedInto = Dictionary(players.compactMap { p in p.mergedInto.map { (p.id, $0) } }, uniquingKeysWith: { a, _ in a })
        return { id in
            var current = id, hops = 0
            while let next = mergedInto[current], hops < 16 { current = next; hops += 1 }
            return current
        }
    }
}

/// Resolves a series to its setups, for the Stats filter.
public struct SeriesMembership: Sendable {
    private let reader: any SeriesListReader

    public init(reader: any SeriesListReader) { self.reader = reader }

    /// The filter for `series`; nil when it no longer exists.
    public func filter(for series: UUID) throws -> SeriesFilter? {
        try reader.seriesList().first { $0.id == series }
            .map { SeriesFilter(seriesId: $0.id, name: $0.name, setups: Set($0.setups)) }
    }

    /// Every series `record` belongs to (a setup can be in several).
    public func series(containing record: MatchRecord, resolve: (UUID) -> UUID = { $0 }) throws -> [UUID] {
        guard let setup = Setup.of(record, resolve: resolve) else { return [] }
        return try reader.seriesList().filter { $0.setups.contains(setup) }.map(\.id)
    }
}

/// `SeriesSetupCatalog` over Stats' own store: setups of recorded matches and players as Stats
/// knows them (merges followed, removed players left out).
@MainActor
public final class StatsStoreSetupCatalog: SeriesSetupCatalog {
    private let records: any MatchRecordStore
    private let playerStore: any StatsPlayerStore
    private var players: [UUID: StatsPlayer] = [:]
    private var setups: [Setup] = []

    public init(records: any MatchRecordStore, players: any StatsPlayerStore) {
        self.records = records
        self.playerStore = players
        refresh()
    }

    public func refresh() {
        let all = (try? playerStore.allPlayers()) ?? []
        players = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let resolve = SeriesFilter.followingMerges(all)
        var seen = Set<Setup>()
        setups = ((try? records.allRecords()) ?? [])
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { Setup.of($0, resolve: resolve) }
            .filter { s in !s.players.contains { players[$0]?.isRemoved == true } && seen.insert(s).inserted }
    }

    public func knownSetups() -> [Setup] { setups }

    public func player(_ id: UUID) -> HistoryPlayer? {
        guard var p = players[id] else { return nil }
        var hops = 0
        while let next = p.mergedInto, let kept = players[next], hops < 16 { p = kept; hops += 1 }
        guard !p.isRemoved else { return nil }
        return HistoryPlayer(id: p.id, name: p.name, colour: p.colour, isArchived: p.isArchived)
    }
}
