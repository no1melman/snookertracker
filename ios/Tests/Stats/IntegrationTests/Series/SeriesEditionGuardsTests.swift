import EventDispatch
import Foundation
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import StatsApplication
import StatsDomain
import StatsInfrastructure
import StatsPublished
import Testing
import UpgradePublished

// Outside-in (spec 027): Stats, Series and `IssueMonthlySummaries` over the real SQLite adapters on
// one in-memory database, sharing a `FixedEdition` flipped by hand. Free refuses the series commands,
// locks the list and issues no summary, while the merge and removal policies (S33, S42) still run.

private let callum = UUID()
private let cal = UUID()
private let asher = UUID()
private let dev = UUID()

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_GB")
    return c
}

private func day(_ m: Int, _ d: Int, hour: Int = 19) -> Date {
    utc.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))!
}

@MainActor
private final class World {
    let dispatcher = EventDispatcher()
    let edition = FixedEdition.unlocked
    let records: MatchRecordsProjection
    let repository: SQLiteSeriesRepository
    let list: SeriesListProjection
    let series: SeriesUseCases
    let log: SQLiteSeriesSummaryLog
    let issue: IssueMonthlySummaries
    private(set) var published: [SeriesSummaryIssuedPublished] = []

    init() throws {
        let db = try SQLiteDatabase.inMemory()
        let statsStore = try SQLiteStatsStore(db: db)
        records = try MatchRecordsProjection(store: statsStore, calendar: utc, edition: edition)
        records.subscribe(to: dispatcher)
        repository = try SQLiteSeriesRepository(db: db)
        list = SeriesListProjection(
            reader: repository, catalog: StatsStoreSetupCatalog(records: statsStore, players: statsStore), edition: edition)
        series = SeriesUseCases(repository: repository, list: list, edition: edition)
        series.subscribe(to: dispatcher)
        try series.loadSeries()
        let summaries = MonthlySummaryProjection(
            stats: records, series: repository, me: { nil }, now: { day(10, 1, hour: 8) }, calendar: utc)
        log = try SQLiteSeriesSummaryLog(db: db)
        issue = IssueMonthlySummaries(
            repository: repository, summaries: summaries, log: log, dispatcher: dispatcher,
            now: { day(10, 1, hour: 8) }, calendar: utc, edition: edition)
        dispatcher.subscribe(SeriesSummaryIssuedPublished.self) { [unowned self] e in
            MainActor.assumeIsolated { self.published.append(e) }
        }
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
        player("PlayerAdded", cal, ["name": "Cal", "colour": "red"])
        player("PlayerAdded", asher, ["name": "Asher", "colour": "orange"])
        player("PlayerAdded", dev, ["name": "Dev", "colour": "green"])
    }

    func player(_ type: String, _ id: UUID, _ fields: [String: Any] = [:]) {
        var body = fields
        body["playerId"] = id.uuidString
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([PlayerEventPublished(playerId: id, type: type, schemaVersion: 1, payload: payload, occurredAt: day(1, 1))])
    }

    private func match(_ id: UUID, _ version: Int, _ type: String, _ body: [String: Any], at: Date) {
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([MatchEventPublished(
            matchId: id, eventId: UUID(), originDevice: UUID(), streamVersion: version,
            type: type, schemaVersion: 1, payload: payload, occurredAt: at)])
    }

    /// A race-to-3 pool match `a` wins 3–0, started at `start`.
    func play(_ a: UUID, _ b: UUID, at start: Date) {
        let id = UUID()
        let side = { (p: UUID) -> [String: Any] in ["player": p.uuidString, "colour": p == a ? "blue" : "orange"] }
        match(id, 1, "MatchStarted", [
            "setup": ["first": a.uuidString, "second": b.uuidString, "game": "pool",
                      "style": ["raceTo": ["_0": ["raceTo": 3]]], "breakRule": "alternate"],
            "first": side(a), "second": side(b), "at": start.timeIntervalSince1970,
        ], at: start)
        for i in 1...3 {
            let at = start.addingTimeInterval(Double(i) * 600)
            match(id, i + 1, "FrameWon", ["player": a.uuidString, "frameNumber": i, "setNumber": 1,
                                          "length": 600, "at": at.timeIntervalSince1970], at: at)
        }
        let end = start.addingTimeInterval(2400)
        match(id, 5, "MatchFinished", [
            "result": ["win": ["_0": side(a)]], "score": ["firstFrames": 3, "secondFrames": 0],
            "endedAt": end.timeIntervalSince1970, "length": 1800, "shortOfTarget": false,
        ], at: end)
        list.refresh()
    }

    func choices(_ pairs: [(UUID, UUID)]) -> [SetupChoice] {
        let all = list.setupChoices(including: [])
        return pairs.map { a, b in all.first { $0.setup.players == [a, b] }! }
    }

    func lock() {
        edition.status = .free
        dispatcher.dispatch([AppLockedPublished(occurredAt: day(10, 1))])
    }

    func unlock() {
        edition.status = .unlocked
        dispatcher.dispatch([AppUnlockedPublished(occurredAt: day(10, 1))])
    }
}

@MainActor
@Suite("Series edition guards integration")
struct SeriesEditionGuardsTests {
    @Test func freeRefusesTheSeriesCommandsAndWritesNothing() throws {
        let world = try World()
        world.play(callum, asher, at: day(9, 4))
        world.play(callum, dev, at: day(9, 5))
        let kept = try world.series.createSeries(name: "Fridays", setups: world.choices([(callum, asher)]))
        let setups = world.choices([(callum, dev)])
        world.lock()

        #expect(throws: UpgradeRequired(.series)) {
            try world.series.createSeries(name: "Dev nights", setups: setups)
        }
        #expect(throws: UpgradeRequired(.series)) {
            try world.series.changeSeries(kept, name: "Thursdays", setups: setups)
        }
        #expect(throws: UpgradeRequired(.series)) { try world.series.deleteSeries(kept) }

        let stored = try world.repository.findAll()
        #expect(stored.map(\.name.value) == ["Fridays"])
        #expect(stored.first?.setups.map(\.players) == [[callum, asher]])
    }

    @Test func theListIsLockedWhileFreeAndShowsEverythingOnUnlock() throws {
        let world = try World()
        world.play(callum, asher, at: day(9, 4))
        try world.series.createSeries(name: "Fridays", setups: world.choices([(callum, asher)]))
        world.lock()

        #expect(world.list.isLocked)
        #expect(world.list.series.isEmpty)
        #expect(world.list.setupChoices(including: []).isEmpty)
        #expect(try world.repository.findAll().count == 1)  // kept, only hidden

        world.unlock()
        #expect(!world.list.isLocked)
        #expect(world.list.series.map(\.name) == ["Fridays"])
    }

    @Test func freeIssuesNoSummaryAndTheFirstRunAfterUnlockDoes() throws {
        let world = try World()
        world.play(callum, asher, at: day(9, 4))
        let fridays = try world.series.createSeries(name: "Fridays", setups: world.choices([(callum, asher)]))
        world.lock()

        #expect(world.issue.run().isEmpty)
        #expect(world.published.isEmpty)
        let september = try Month.create(year: 2026, month: 9).get()
        #expect(try !world.log.isIssued(SeriesId(fridays), september))

        world.unlock()
        #expect(world.issue.run().map(\.seriesId.value) == [fridays])
        #expect(world.published.count == 1)
    }

    @Test func mergeAndRemovalPoliciesStillRunWhileFree() throws {
        let world = try World()
        world.play(cal, asher, at: day(9, 3))
        world.play(callum, dev, at: day(9, 4))
        let merged = try world.series.createSeries(name: "Cal", setups: world.choices([(cal, asher)]))
        let removed = try world.series.createSeries(name: "Dev nights", setups: world.choices([(callum, dev)]))
        world.lock()

        world.player("PlayersMerged", callum, ["keptPlayerId": callum.uuidString, "foldedInPlayerId": cal.uuidString])
        world.player("PlayerRemoved", dev)

        #expect(world.series.lastError == nil)
        #expect(try world.repository.getById(SeriesId(merged))?.setups.map(\.players) == [[callum, asher]])
        #expect(try world.repository.getById(SeriesId(removed))?.setups.isEmpty == true)
        #expect(try world.repository.findContainingPlayer(cal).isEmpty)
        #expect(try world.repository.findContainingPlayer(dev).isEmpty)

        world.unlock()
        #expect(world.list.series.first { $0.id == merged }?.setups.map(\.title) == ["Callum v Asher"])
    }
}
