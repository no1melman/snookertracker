import EventDispatch
import Foundation
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import StatsApplication
import StatsDomain
import StatsInfrastructure
import Testing

// Outside-in (spec 016): published match and player events go through the dispatcher into Stats'
// real projection and SQLite store; the series use cases and policies run over the real SQLite
// series repository on the same in-memory database. Assertions read the list and the membership.

private let callum = UUID()
private let cal = UUID()
private let asher = UUID()
private let dev = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

/// Stats + Series, wired as the composition root does (Series subscribes after the records projection).
@MainActor
private final class SeriesWorld {
    let db: SQLiteDatabase
    let dispatcher = EventDispatcher()
    let statsStore: SQLiteStatsStore
    let records: MatchRecordsProjection
    let repository: SQLiteSeriesRepository
    let list: SeriesListProjection
    let series: SeriesUseCases
    private var started = 0

    init(db: SQLiteDatabase? = nil) throws {
        self.db = try db ?? .inMemory()
        statsStore = try SQLiteStatsStore(db: self.db)
        records = try MatchRecordsProjection(store: statsStore)
        records.subscribe(to: dispatcher)
        repository = try SQLiteSeriesRepository(db: self.db)
        list = SeriesListProjection(reader: repository, catalog: StatsStoreSetupCatalog(records: statsStore, players: statsStore))
        series = SeriesUseCases(repository: repository, list: list)
        series.subscribe(to: dispatcher)
        try series.loadSeries()
    }

    func player(_ type: String, _ id: UUID, _ fields: [String: Any] = [:]) {
        var body = fields
        body["playerId"] = id.uuidString
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([PlayerEventPublished(playerId: id, type: type, schemaVersion: 1, payload: payload, occurredAt: t0)])
    }

    func addPlayers() {
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
        player("PlayerAdded", cal, ["name": "Cal", "colour": "red"])
        player("PlayerAdded", asher, ["name": "Asher", "colour": "orange"])
        player("PlayerAdded", dev, ["name": "Dev", "colour": "green"])
        list.refresh()
    }

    /// Publishes a `MatchStarted` in Matches' wire shape; returns the match id.
    @discardableResult
    func startMatch(_ a: UUID, _ b: UUID, raceTo: Int = 5, bestOf: Int? = nil) -> UUID {
        let id = UUID()
        started += 1
        var target: [String: Any] = ["raceTo": raceTo]
        if let bestOf { target["bestOf"] = bestOf }
        let body: [String: Any] = [
            "setup": ["first": a.uuidString, "second": b.uuidString, "game": "pool",
                      "style": ["raceTo": ["_0": target]], "breakRule": "alternate"],
            "first": ["player": a.uuidString, "colour": "blue"],
            "second": ["player": b.uuidString, "colour": "orange"],
            "at": t0.addingTimeInterval(Double(started) * 60).timeIntervalSince1970,
        ]
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([MatchEventPublished(
            matchId: id, eventId: UUID(), originDevice: UUID(), streamVersion: 1,
            type: "MatchStarted", schemaVersion: 1, payload: payload, occurredAt: t0)])
        list.refresh()
        return id
    }

    func choices(_ pairs: [(UUID, UUID)]) -> [SetupChoice] {
        let all = list.setupChoices(including: [])
        return pairs.map { a, b in all.first { $0.setup.players == [a, b] }! }
    }

    /// Ids of the recorded matches that belong to `seriesID`.
    func members(_ seriesID: UUID) throws -> Set<UUID> {
        let filter = try #require(try SeriesMembership(reader: repository).filter(for: seriesID))
        let resolve = SeriesFilter.followingMerges(try statsStore.allPlayers())
        return Set(try statsStore.allRecords().filter { filter.contains($0, resolve: resolve) }.map(\.id))
    }
}

@MainActor
@Suite("Series integration")
struct SeriesIntegrationTests {
    @Test func aSeriesIsCreatedFromPlayedSetupsAndSurvivesARelaunch() throws {
        let db = try SQLiteDatabase.inMemory()
        let world = try SeriesWorld(db: db)
        world.addPlayers()
        world.startMatch(callum, asher)
        world.startMatch(callum, dev)
        world.startMatch(asher, callum, raceTo: 5, bestOf: 9)  // the same setup as the first

        #expect(world.list.setupChoices(including: []).count == 2)
        let id = try world.series.createSeries(name: " Fridays with Asher ", setups: world.choices([(callum, asher)]))

        let row = try #require(world.list.series.first)
        #expect(row.id == id)
        #expect(row.name == "Fridays with Asher")
        // The setup reads as most recently played: Asher first, entered as best of 9.
        #expect(row.setups.map(\.title) == ["Asher v Callum"])
        #expect(row.setups.first?.details == "Pool · Best of 9 · Alternate breaks")

        let relaunched = try SeriesWorld(db: db)
        #expect(relaunched.list.series.map(\.name) == ["Fridays with Asher"])
        #expect(try relaunched.repository.findAll().first?.setups == [row.setups[0].setup])
    }

    @Test func aBlankNameCannotBeSaved() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        world.startMatch(callum, asher)
        #expect(throws: SeriesError.blankName) {
            try world.series.createSeries(name: "  ", setups: world.choices([(callum, asher)]))
        }
        #expect(throws: SeriesError.noSetups) { try world.series.createSeries(name: "Nothing", setups: []) }
        #expect(try world.repository.findAll().isEmpty)
    }

    @Test func membershipIsBySetupForPastAndFutureMatches() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        let past = world.startMatch(callum, asher)
        let other = world.startMatch(callum, dev)
        let raceTo3 = world.startMatch(callum, asher, raceTo: 3)
        let raceTo5 = world.list.setupChoices(including: []).filter {
            guard $0.setup.players == [callum, asher], case .raceTo(let t) = $0.setup.style else { return false }
            return t.raceTo == 5
        }
        #expect(raceTo5.count == 1)
        let id = try world.series.createSeries(name: "Fridays", setups: raceTo5)
        let future = world.startMatch(asher, callum, raceTo: 5, bestOf: 9)

        let members = try world.members(id)
        #expect(members == [past, future])
        #expect(!members.contains(other) && !members.contains(raceTo3))
    }

    @Test func aSetupCanBeInSeveralSeries() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        let match = world.startMatch(callum, asher)
        let devMatch = world.startMatch(callum, dev)
        let a = try world.series.createSeries(name: "Fridays", setups: world.choices([(callum, asher)]))
        let b = try world.series.createSeries(name: "All of Callum's", setups: world.choices([(callum, asher), (callum, dev)]))

        #expect(try world.members(a) == [match])
        #expect(try world.members(b) == [match, devMatch])
        let record = try #require(try world.statsStore.allRecords().first { $0.id == match })
        #expect(Set(try SeriesMembership(reader: world.repository).series(containing: record)) == [a, b])
        #expect(world.list.series.map(\.name) == ["All of Callum's", "Fridays"])
    }

    @Test func changingAndDeletingNeverTouchMatches() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        world.startMatch(callum, asher)
        let devMatch = world.startMatch(callum, dev)
        let id = try world.series.createSeries(name: "Fridays", setups: world.choices([(callum, asher)]))

        try world.series.changeSeries(id, name: "Thursdays", setups: world.choices([(callum, dev)]))
        #expect(world.list.series.map(\.name) == ["Thursdays"])
        #expect(try world.members(id) == [devMatch])
        #expect(throws: SeriesError.noSetups) { try world.series.changeSeries(id, name: "Thursdays", setups: []) }

        let before = try world.statsStore.allRecords().count
        try world.series.deleteSeries(id)
        #expect(world.list.series.isEmpty)
        #expect(try world.repository.getById(SeriesId(id)) == nil)
        #expect(try world.statsStore.allRecords().count == before)
        #expect(try SeriesMembership(reader: world.repository).filter(for: id) == nil)
        try world.series.deleteSeries(id)  // already gone: nothing to do
    }

    @Test func aMergeRepointsSeriesSetupsToTheKeptPlayer() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        let calMatch = world.startMatch(cal, asher)
        let callumMatch = world.startMatch(callum, asher)
        let id = try world.series.createSeries(name: "Fridays", setups: world.choices([(cal, asher), (callum, asher)]))
        let untouched = try world.series.createSeries(name: "Dev", setups: world.choices([(callum, asher)]))

        world.player("PlayersMerged", callum, ["keptPlayerId": callum.uuidString, "foldedInPlayerId": cal.uuidString])

        let repointed = try #require(try world.repository.getById(SeriesId(id)))
        #expect(repointed.setups.count == 1)
        #expect(repointed.setups.first?.players == [callum, asher])
        #expect(try world.repository.findContainingPlayer(cal).isEmpty)
        #expect(try world.repository.getById(SeriesId(untouched))?.setups.count == 1)
        // Cal's earlier match is Callum's now, so it still belongs to the series.
        #expect(try world.members(id) == [calMatch, callumMatch])
        #expect(world.list.series.first { $0.id == id }?.setups.map(\.title) == ["Callum v Asher"])
        #expect(world.series.lastError == nil)
    }

    @Test func aRemovedPlayersSetupsAreTakenOutOfSeries() throws {
        let world = try SeriesWorld()
        world.addPlayers()
        world.startMatch(callum, asher)
        world.startMatch(callum, dev)
        let mixed = try world.series.createSeries(name: "Mixed", setups: world.choices([(callum, asher), (callum, dev)]))
        let devOnly = try world.series.createSeries(name: "Dev nights", setups: world.choices([(callum, dev)]))

        world.player("PlayerRemoved", dev)

        #expect(try world.repository.getById(SeriesId(mixed))?.setups.map(\.players) == [[callum, asher]])
        let emptied = try #require(try world.repository.getById(SeriesId(devOnly)))
        #expect(emptied.setups.isEmpty)
        #expect(try world.repository.findContainingPlayer(dev).isEmpty)
        #expect(world.list.series.first { $0.id == devOnly }?.setups.isEmpty == true)
        #expect(!world.list.setupChoices(including: []).contains { $0.setup.involves(dev) })
        #expect(world.series.lastError == nil)
    }
}
