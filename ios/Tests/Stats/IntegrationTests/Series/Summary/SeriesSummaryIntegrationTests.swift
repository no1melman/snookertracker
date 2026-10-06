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

// Outside-in (spec 017): published match and player events go through the dispatcher into Stats'
// real projection and SQLite store; the series, the summary log and `IssueMonthlySummaries` run over
// the real SQLite adapters on the same in-memory database, with a fixed clock and a UTC calendar.

private let callum = UUID()
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

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class WhoAmI: @unchecked Sendable {
    var id: UUID?
}

@MainActor
private final class SummaryWorld {
    let db: SQLiteDatabase
    let dispatcher = EventDispatcher()
    let records: MatchRecordsProjection
    let repository: SQLiteSeriesRepository
    let list: SeriesListProjection
    let series: SeriesUseCases
    let summaries: MonthlySummaryProjection
    let issue: IssueMonthlySummaries
    let clock: Clock
    private let who: WhoAmI
    /// Players' `WhoAmI` as the composition root adapts it.
    var me: UUID? {
        get { who.id }
        set { who.id = newValue }
    }
    private(set) var published: [SeriesSummaryIssuedPublished] = []

    init(db: SQLiteDatabase? = nil, now: Date = day(10, 1, hour: 8)) throws {
        self.db = try db ?? .inMemory()
        let clock = Clock(now)
        self.clock = clock
        let statsStore = try SQLiteStatsStore(db: self.db)
        records = try MatchRecordsProjection(store: statsStore, calendar: utc)
        records.subscribe(to: dispatcher)
        repository = try SQLiteSeriesRepository(db: self.db)
        list = SeriesListProjection(reader: repository, catalog: StatsStoreSetupCatalog(records: statsStore, players: statsStore))
        series = SeriesUseCases(repository: repository, list: list)
        try series.loadSeries()
        let who = WhoAmI()
        self.who = who
        summaries = MonthlySummaryProjection(
            stats: records, series: repository, me: { who.id }, now: { clock.now }, calendar: utc)
        issue = IssueMonthlySummaries(
            repository: repository, summaries: summaries, log: try SQLiteSeriesSummaryLog(db: self.db),
            dispatcher: dispatcher, now: { clock.now }, calendar: utc)
        dispatcher.subscribe(SeriesSummaryIssuedPublished.self) { [unowned self] e in
            MainActor.assumeIsolated { self.published.append(e) }
        }
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
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

    /// A race-to-3 pool match between `a` and `b` started at `at`; `frames` lists each frame's winner.
    /// Finished (the leader wins) unless `abandoned`.
    @discardableResult
    func play(_ a: UUID, _ b: UUID, at start: Date, frames: [UUID], abandoned: Bool = false) -> UUID {
        let id = UUID()
        let side = { (p: UUID) -> [String: Any] in ["player": p.uuidString, "colour": p == a ? "blue" : "orange"] }
        match(id, 1, "MatchStarted", [
            "setup": ["first": a.uuidString, "second": b.uuidString, "game": "pool",
                      "style": ["raceTo": ["_0": ["raceTo": 3]]], "breakRule": "alternate"],
            "first": side(a), "second": side(b), "at": start.timeIntervalSince1970,
        ], at: start)
        for (i, w) in frames.enumerated() {
            let at = start.addingTimeInterval(Double(i + 1) * 600)
            match(id, i + 2, "FrameWon", ["player": w.uuidString, "frameNumber": i + 1, "setNumber": 1,
                                          "length": 600, "at": at.timeIntervalSince1970], at: at)
        }
        let (fa, fb) = (frames.filter { $0 == a }.count, frames.filter { $0 == b }.count)
        let end = start.addingTimeInterval(Double(frames.count + 1) * 600)
        let score: [String: Any] = ["firstFrames": fa, "secondFrames": fb]
        if abandoned {
            match(id, frames.count + 2, "MatchAbandoned", [
                "score": score, "endedAt": end.timeIntervalSince1970, "length": Double(frames.count) * 600,
            ], at: end)
        } else {
            let result: [String: Any] = fa == fb ? ["draw": [String: Any]()] : ["win": ["_0": side(fa > fb ? a : b)]]
            match(id, frames.count + 2, "MatchFinished", [
                "result": result, "score": score, "endedAt": end.timeIntervalSince1970,
                "length": Double(frames.count) * 600, "shortOfTarget": false,
            ], at: end)
        }
        list.refresh()
        return id
    }

    /// A series of the setups between these pairs (each must have been played).
    @discardableResult
    func makeSeries(_ name: String, _ pairs: [(UUID, UUID)]) throws -> UUID {
        let all = list.setupChoices(including: [])
        return try series.createSeries(name: name, setups: pairs.map { a, b in all.first { $0.setup.players == [a, b] }! })
    }

    func september(_ id: UUID) throws -> MonthlySummary {
        try #require(summaries.summary(series: id, monthOf: day(9, 15)))
    }
}

@MainActor
@Suite("Series monthly summary integration")
struct SeriesSummaryIntegrationTests {
    @Test func aSummaryIsIssuedOnlyForSeriesWithMatchesLastMonth() throws {
        let world = try SummaryWorld()
        world.play(callum, asher, at: day(9, 4), frames: [callum, callum, asher, callum])
        world.play(callum, dev, at: day(8, 7), frames: [dev, dev, dev])        // August only
        world.play(asher, dev, at: day(10, 1, hour: 7), frames: [asher, asher, asher])  // this month only
        let fridays = try world.makeSeries("Fridays with Asher", [(callum, asher)])
        try world.makeSeries("Dev nights", [(callum, dev), (asher, dev)])

        let issued = world.issue.run()

        #expect(issued.map(\.seriesId.value) == [fridays])
        #expect(issued.first?.month == (try Month.create(year: 2026, month: 9).get()))
        let event = try #require(world.published.first)
        #expect(world.published.count == 1)
        #expect(event.seriesId == fridays && event.year == 2026 && event.month == 9)
        #expect(event.text == "Fridays with Asher, September: Callum v Asher 1–0 in matches, 3–1 in frames")
        #expect(world.issue.lastError == nil)
    }

    @Test func eachMonthIsIssuedOnceEvenAcrossRelaunches() throws {
        let db = try SQLiteDatabase.inMemory()
        let world = try SummaryWorld(db: db)
        world.play(callum, asher, at: day(9, 4), frames: [callum, callum, callum])
        try world.makeSeries("Fridays", [(callum, asher)])

        #expect(world.issue.run().count == 1)
        #expect(world.issue.run().isEmpty)  // back to the foreground the same day
        world.clock.now = day(10, 20)
        #expect(world.issue.run().isEmpty)  // later in October
        #expect(world.published.count == 1)

        let relaunched = try SummaryWorld(db: db, now: day(10, 2))
        #expect(relaunched.issue.run().isEmpty)
        #expect(relaunched.published.isEmpty)

        // November covers October, which had no matches: nothing; December covers November.
        relaunched.clock.now = day(11, 1)
        #expect(relaunched.issue.run().isEmpty)
        relaunched.play(callum, asher, at: day(11, 6), frames: [asher, asher, asher])
        relaunched.clock.now = day(12, 3)
        #expect(relaunched.issue.run().map(\.month.month) == [11])
    }

    @Test func abandonedAndCancelledMatchesDoNotEarnASummary() throws {
        let world = try SummaryWorld()
        world.play(callum, asher, at: day(8, 4), frames: [callum, callum, callum])
        world.play(callum, asher, at: day(9, 4), frames: [callum], abandoned: true)
        try world.makeSeries("Fridays", [(callum, asher)])
        #expect(world.issue.run().isEmpty)
    }

    @Test func meInTheSeriesReadsAsYouOtherwiseEachPairing() throws {
        let world = try SummaryWorld()
        world.play(callum, asher, at: day(9, 4), frames: [callum, callum, callum])           // Callum 3–0
        world.play(dev, callum, at: day(9, 11), frames: [dev, callum, dev, callum, callum])   // Callum 3–2 (decider)
        world.play(asher, dev, at: day(9, 18), frames: [dev, dev, dev])                       // Dev 3–0
        let id = try world.makeSeries("Club", [(callum, asher), (callum, dev), (asher, dev)])

        world.me = callum
        let mine = try world.september(id)
        #expect(mine.lines.map(\.title) == ["you", "Asher v Dev"])
        let you = try #require(mine.lines.first)
        #expect(you.figures.won == 2 && you.figures.lost == 0)
        #expect(you.figures.framesWon == 6 && you.figures.framesLost == 2)
        #expect(you.figures.decidersWon == 1 && you.figures.decidersLost == 0)
        #expect(you.headline == "you 2–0 in matches, 6–2 in frames")
        #expect(mine.lines[1].figures.lost == 1 && mine.lines[1].figures.framesLost == 3)
        #expect(mine.matches == 3)
        #expect(mine.headline == "3 matches across 2 pairings")

        world.me = nil
        let theirs = try world.september(id)
        // Each pairing from its setup's first player's side.
        #expect(theirs.lines.map(\.title) == ["Callum v Asher", "Dev v Callum", "Asher v Dev"])
        #expect(theirs.lines.map(\.matchRecord) == ["1–0", "0–1", "0–1"])

        world.me = UUID()  // Me set, but not in the series
        #expect(try world.september(id).lines.count == 3)
    }

    @Test func theSummaryShowsTheChangeSinceThePreviousMonth() throws {
        let world = try SummaryWorld()
        world.play(callum, asher, at: day(8, 7), frames: [asher, asher, asher])
        world.play(callum, asher, at: day(8, 14), frames: [callum, callum, callum])
        world.play(callum, asher, at: day(9, 4), frames: [callum, callum, callum])
        world.play(callum, asher, at: day(9, 11), frames: [callum, asher, callum, callum])
        world.play(callum, asher, at: day(9, 18), frames: [asher, callum, asher, asher])
        let id = try world.makeSeries("Fridays", [(callum, asher)])
        world.me = callum

        let summary = try world.september(id)
        #expect(summary.title == "September 2026" && summary.previousMonthName == "August")
        let line = try #require(summary.lines.first)
        #expect(line.matchRecord == "2–1")
        let change = line.change
        #expect(!change.isFirstMonth)
        #expect(change.won == 1 && change.lost == 0)
        #expect(change.framesWon == 4 && change.framesLost == 1)   // 7–4 against 3–3
        #expect(change.winPercentagePoints.map { Int($0.rounded()) } == 17)  // 67% against 50%

        let august = try #require(world.summaries.summary(series: id, monthOf: day(8, 1)))
        #expect(august.lines.first?.change.isFirstMonth == true)
        #expect(world.summaries.lastMonth() == day(9, 1, hour: 0))
    }

    @Test func aMatchIsInTheMonthItStartedIn() throws {
        let world = try SummaryWorld()
        // Starts on 30 September at 23:30 and ends in October: September's.
        world.play(callum, asher, at: utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 30))!,
                   frames: [callum, callum, callum])
        let id = try world.makeSeries("Fridays", [(callum, asher)])
        #expect(try world.september(id).matches == 1)
        #expect(try #require(world.summaries.summary(series: id, monthOf: day(10, 2))).isEmpty)
    }
}
