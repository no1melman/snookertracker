import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import StatsApplication
import StatsDomain
import StatsInfrastructure
import StatsPublished
import Testing

// Outside-in (spec 014): Matches' real aggregate, event store and wire produce the published events;
// Stats' real projection answers `Stats(filter)` and the open-host queries for Matches.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
/// Monday 2026-09-21, 14:13 UTC.
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let day: Double = 1440

private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

@MainActor
private final class World {
    let repository: EventSourcedMatchRepository
    let dispatcher = EventDispatcher()
    let stats: MatchRecordsProjection

    init() throws {
        let db = try SQLiteDatabase.inMemory()
        repository = EventSourcedMatchRepository(store: try SQLiteMatchEventStore(db: db, originDevice: UUID()))
        stats = try MatchRecordsProjection(store: SQLiteStatsStore(db: db), calendar: utc)
        stats.subscribe(to: dispatcher)
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
        player("PlayerAdded", asher, ["name": "Asher", "colour": "orange"])
        player("PlayerAdded", dev, ["name": "Dev", "colour": "green"])
    }

    @discardableResult
    func commit(_ match: Match) throws -> Match {
        let recorded = try repository.save(match)
        let id = UUID(uuidString: match.id.value)!
        dispatcher.dispatch(recorded.filter { MatchEventWire.isPublished($0.event) }.map { r in
            let wire = try! MatchEventWire.encode(r.event)
            return MatchEventPublished(
                matchId: id, eventId: r.eventId, originDevice: r.originDevice, streamVersion: r.streamVersion,
                type: wire.type, schemaVersion: wire.schemaVersion, payload: wire.payload, occurredAt: r.event.at)
        })
        return match.committed()
    }

    func player(_ type: String, _ id: UUID, _ fields: [String: Any] = [:]) {
        var body = fields
        body["playerId"] = id.uuidString
        body["occurredAt"] = t0.timeIntervalSince1970
        let payload = try! JSONSerialization.data(withJSONObject: body)
        dispatcher.dispatch([PlayerEventPublished(playerId: id, type: type, schemaVersion: 1, payload: payload, occurredAt: t0)])
    }

    /// Plays and finishes a match: one frame per winner, `every` minutes apart, from `at` minutes.
    @discardableResult
    func finished(
        _ a: UUID, _ b: UUID, _ winners: [UUID], game: MatchesDomain.Game = .pool,
        style: MatchesDomain.MatchStyle = .mostFramesWins, at: Double = 0, every: Double = 10
    ) throws -> Match {
        let m = play(start(a, b, game: game, style: style, at: at), winners, every: every, from: at)
        return try commit(m.finish(at: minutes(at + every * Double(winners.count)), anyway: true).value!)
    }

    /// Callum v Asher.
    @discardableResult
    func finished(
        _ winners: [UUID], game: MatchesDomain.Game = .pool, style: MatchesDomain.MatchStyle = .mostFramesWins,
        at: Double = 0, every: Double = 10
    ) throws -> Match {
        try finished(callum, asher, winners, game: game, style: style, at: at, every: every)
    }
}

extension Result {
    fileprivate var value: Success? { try? get() }
}

private func start(_ a: UUID = callum, _ b: UUID = asher, game: MatchesDomain.Game = .pool,
                   style: MatchesDomain.MatchStyle = .mostFramesWins, at: Double = 0) -> Match {
    let setup = MatchesDomain.Setup.create(PlayerId(a), PlayerId(b), game: game, style: style).value!
    return Match.start(id: MatchId(UUID()), setup: setup,
                       firstColour: Colour.create("blue").value!, secondColour: Colour.create("orange").value!, at: minutes(at))
}

private func play(_ match: Match, _ winners: [UUID], every: Double = 10, from: Double = 0) -> Match {
    var m = match.chooseBreaker(PlayerId(winners.first ?? callum), at: minutes(from)).value!
    for (i, w) in winners.enumerated() {
        m = m.awardFrame(to: PlayerId(w), at: minutes(from + every * Double(i + 1))).value!
    }
    return m
}

private func race(_ n: Int) -> MatchesDomain.MatchStyle { .raceTo(Target.raceTo(n).value!) }

private let me = StatsFilter(pointOfView: callum)

// MARK: - Stats(filter): figures

@MainActor
@Suite struct StatsFiguresTests {
    @Test func wonDrawnLostCountsDraws() throws {
        let w = try World()
        try w.finished([callum, callum])
        try w.finished([callum, asher])          // most frames, level: a draw
        try w.finished([asher, asher, callum], at: 60)

        let f = w.stats.stats(me).overall
        #expect((f.won, f.drawn, f.lost) == (1, 1, 1))
        #expect((f.framesWon, f.framesLost) == (4, 3))
        #expect(f.matches == 3)
        #expect(abs((f.winPercentage ?? 0) - 100.0 / 3) < 0.001)
        #expect(f.averageFrameTime == 600)
    }

    @Test func theFiguresAreFromThePointOfView() throws {
        let w = try World()
        try w.finished([callum, callum, asher])
        let f = w.stats.stats(StatsFilter(pointOfView: asher)).overall
        #expect((f.won, f.lost, f.framesWon, f.framesLost) == (0, 1, 1, 2))
        #expect(w.stats.stats(StatsFilter(pointOfView: asher)).pointOfView?.name == "Asher")
    }

    @Test func decidersAreCountedFromTheFramesAsPlayed() throws {
        let w = try World()
        // Race to 3 won 3–2 from 2–2: a match decider.
        try w.finished([callum, asher, asher, callum, callum], style: race(3))
        // Race to 2 sets of race to 2: sets 1–1, deciding set won 2–0 by Asher: a set decider only.
        let sets = MatchesDomain.MatchStyle.sets(sets: Target.raceTo(2).value!, frames: Target.raceTo(2).value!)
        try w.finished([callum, callum, asher, asher, asher, asher], style: sets, at: 60)

        let f = w.stats.stats(me).overall
        #expect((f.decidersWon, f.decidersLost) == (1, 0))
        #expect((f.matchDecidersWon, f.matchDecidersLost) == (1, 0))
        #expect((f.setDecidersWon, f.setDecidersLost) == (0, 1))
    }

    @Test func averageFrameTimeIsAlsoPerPlayer() throws {
        let w = try World()
        var m = start().chooseBreaker(PlayerId(callum), at: t0).value!
        m = m.awardFrame(to: PlayerId(callum), at: minutes(10)).value!
        m = m.awardFrame(to: PlayerId(asher), at: minutes(30)).value!
        m = m.awardFrame(to: PlayerId(callum), at: minutes(36)).value!
        try w.commit(m.finish(at: minutes(36)).value!)

        let f = w.stats.stats(me).overall
        #expect(f.averageFrameTime == 720)
        #expect(f.averageFrameTimeWon == 480)
        #expect(f.averageFrameTimeLost == 1200)
    }
}

// MARK: - Stats(filter): inclusion rules

@MainActor
@Suite struct StatsInclusionTests {
    @Test func onlyFinishedMatchesCountByDefault() throws {
        let w = try World()
        try w.finished([callum])
        try w.commit(play(start(at: 60), [asher], from: 60).abandon(at: minutes(80)).value!)
        try w.commit(start(at: 120).cancel(at: minutes(121)).value!)
        try w.commit(play(start(at: 180), [asher, asher], from: 180))   // live

        let f = w.stats.stats(me).overall
        #expect(f.matches == 1 && f.won == 1 && f.abandoned == 0)
        #expect((f.framesWon, f.framesLost) == (1, 0))
    }

    @Test func abandonedMatchesCountOnlyWhenIncludedWithoutAResult() throws {
        let w = try World()
        try w.finished([callum])
        try w.commit(play(start(at: 60), [asher, callum, asher], from: 60).abandon(at: minutes(100)).value!)

        var filter = me
        filter.includeAbandoned = true
        let f = w.stats.stats(filter).overall
        #expect((f.won, f.drawn, f.lost, f.abandoned) == (1, 0, 0, 1))
        #expect((f.framesWon, f.framesLost) == (2, 2))
        #expect(f.winPercentage == 100)
    }

    @Test func cancelledMatchesNeverCount() throws {
        let w = try World()
        try w.commit(start().cancel(at: minutes(1)).value!)
        let f = w.stats.stats(StatsFilter(pointOfView: callum, includeAbandoned: true, includeArchivedPlayers: true)).overall
        #expect(f.matches == 0 && f.framesWon == 0)
    }

    @Test func archivedPlayersMatchesCountOnlyWhenIncluded() throws {
        let w = try World()
        try w.finished(callum, dev, [callum])
        try w.finished(callum, asher, [asher], at: 60)
        w.player("PlayerArchived", dev)

        #expect(w.stats.stats(me).overall.matches == 1)
        #expect(w.stats.stats(StatsFilter(pointOfView: callum, includeArchivedPlayers: true)).overall.matches == 2)
        #expect(w.stats.statsPlayers(includeArchived: false).map(\.name) == ["Asher", "Callum"])
        #expect(w.stats.statsPlayers(includeArchived: true).map(\.name) == ["Asher", "Callum", "Dev"])
    }

    @Test func aRemovedPlayersMatchesNeverCount() throws {
        let w = try World()
        try w.finished(callum, dev, [callum])
        w.player("PlayerArchived", dev)
        w.player("PlayerRemoved", dev)
        #expect(w.stats.stats(StatsFilter(pointOfView: callum, includeArchivedPlayers: true)).overall.matches == 0)
    }

    @Test func aDeletedMatchLeavesTheStats() throws {
        let w = try World()
        let m = try w.finished([callum])
        try w.commit(m.delete(at: minutes(30)).value!)
        #expect(w.stats.stats(me).overall.matches == 0)
    }

    @Test func aCorrectedScoreCountsAsCorrected() throws {
        let w = try World()
        let m = try w.finished([callum, asher, callum])
        let correction = ScoreCorrection.frames(first: 2, second: 2, for: .mostFramesWins).value!
        try w.commit(m.correctScore(correction, at: minutes(60)).value!)
        let f = w.stats.stats(me).overall
        #expect((f.won, f.drawn, f.framesWon, f.framesLost) == (0, 1, 2, 2))
    }
}

// MARK: - Stats(filter): filters and groups

@MainActor
@Suite struct StatsFilterTests {
    /// Monday: Asher ×2 (pool race to 3, snooker); Friday: Asher (pool), Dev (pool).
    private func week(_ w: World) throws {
        try w.finished([callum, callum, callum], style: race(3))
        try w.finished([asher], game: .snooker, at: 60)
        try w.finished([asher, callum, callum], at: 4 * day)
        try w.finished(callum, dev, [dev], at: 4 * day + 60)
    }

    @Test func filtersNarrowTheMatchesCounted() throws {
        let w = try World()
        try week(w)
        var f = me
        f.opponent = asher
        #expect(w.stats.stats(f).overall.matches == 3)
        f.weekday = .friday
        #expect(w.stats.stats(f).overall.matches == 1)
        f = me
        f.game = "snooker"
        #expect(w.stats.stats(f).overall.lost == 1)
        f = me
        f.style = .raceTo(MatchRecord.Target(raceTo: 3, bestOf: nil))
        #expect(w.stats.stats(f).overall.won == 1)
        f = me
        f.dates = DateInterval(start: minutes(3 * day), end: minutes(5 * day))
        #expect(w.stats.stats(f).overall.matches == 2)
    }

    @Test func theSeriesFilterCountsMatchesOfItsSetupsFollowingMerges() throws {
        let w = try World()
        try week(w)
        let setup = try StatsDomain.Setup.create(asher, callum, game: "pool", style: .mostFramesWins, breakRule: "alternate").get()
        var f = me
        f.series = SeriesFilter(seriesId: UUID(), name: "Fridays", setups: [setup])
        #expect(w.stats.stats(f).overall.matches == 1)
        #expect(w.stats.stats(f).overall.won == 1)

        // Dev folded into Asher: Dev's pool match is now one of the series' setups.
        w.player("PlayersMerged", dev, ["keptPlayerId": asher.uuidString, "foldedInPlayerId": dev.uuidString])
        #expect(w.stats.stats(f).overall.matches == 2)
    }

    @Test func groupsByOpponentMostPlayedFirst() throws {
        let w = try World()
        try week(w)
        var f = me
        f.grouping = .opponent
        let groups = w.stats.stats(f).groups
        #expect(groups.map(\.opponent?.name) == ["Asher", "Dev"])
        #expect(groups.map(\.figures.matches) == [3, 1])
        #expect(groups[0].weekday == nil)
    }

    @Test func groupsByWeekdayMondayFirst() throws {
        let w = try World()
        try week(w)
        var f = me
        f.grouping = .weekday
        let groups = w.stats.stats(f).groups
        #expect(groups.map(\.weekday) == [.monday, .friday])
        #expect(groups.map(\.figures.matches) == [2, 2])
        #expect(groups[0].opponent == nil)
    }

    @Test func groupsCombineOpponentAndWeekday() throws {
        let w = try World()
        try week(w)
        var f = me
        f.grouping = [.opponent, .weekday]
        let groups = w.stats.stats(f).groups
        #expect(groups.count == 3)
        let asherOnFridays = try #require(groups.first { $0.opponent?.id == asher && $0.weekday == .friday })
        #expect(asherOnFridays.figures.won == 1)
        #expect(w.stats.stats(f).overall.matches == 4)
    }

    @Test func choicesComeFromThePointOfViewsMatches() throws {
        let w = try World()
        try week(w)
        let c = w.stats.statsChoices(for: callum, includeArchivedPlayers: false)
        #expect(c.opponents.map(\.name) == ["Asher", "Dev"])
        #expect(c.games == ["pool", "snooker"])
        #expect(c.styles.map(\.text) == ["Most frames", "Race to 3"])
    }

    @Test func aMergedAwayPlayersMatchesCountForTheKeptPlayer() throws {
        let w = try World()
        try w.finished(callum, dev, [dev])
        try w.finished(callum, asher, [callum], at: 60)
        w.player("PlayersMerged", dev, ["keptPlayerId": asher.uuidString, "foldedInPlayerId": dev.uuidString])
        var f = me
        f.grouping = .opponent
        let groups = w.stats.stats(f).groups
        #expect(groups.map(\.opponent?.name) == ["Asher"])
        #expect((groups[0].figures.won, groups[0].figures.lost) == (1, 1))
    }
}

// MARK: - Open host for Matches

@MainActor
@Suite struct MatchStatsQueriesTests {
    @Test func headToHeadCountsFinishedMatchesInAnyGameAndStyleAndExcludesTheLiveMatch() throws {
        let w = try World()
        try w.finished([callum, asher, asher, callum, callum], style: race(3))
        try w.finished([asher], game: .snooker, at: 60)
        try w.finished([callum, asher], at: 120)   // draw
        try w.commit(play(start(at: 180), [asher, asher], from: 180).abandon(at: minutes(210)).value!)
        try w.finished(callum, dev, [callum], at: 240)
        let live = try w.commit(play(start(at: 300), [callum, callum, callum], from: 300))
        let queries: any MatchStatsQueries = w.stats

        let h = queries.headToHead(callum, asher)
        #expect((h.won, h.drawn, h.lost) == (1, 1, 1))
        #expect((h.framesWon, h.framesLost) == (4, 4))
        #expect((h.decidersWon, h.decidersLost) == (1, 0))
        #expect(h.showsDeciders && !h.isEmpty)

        // The live match counts once it is finished.
        try w.commit(live.finish(at: minutes(340)).value!)
        #expect(queries.headToHead(callum, asher).won == 2)
        #expect(queries.headToHead(asher, callum).lost == 2)
    }

    @Test func headToHeadWithNoHistoryIsEmptyAndHidesDeciders() throws {
        let w = try World()
        try w.commit(play(start(), [callum]))
        let h = w.stats.headToHead(callum, asher)
        #expect(h == HeadToHead.none && h.isEmpty && !h.showsDeciders)
    }

    @Test func averageFrameTimeIsOverFramesThePlayerWonInFinishedMatches() throws {
        let w = try World()
        #expect(w.stats.averageFrameTime(callum) == nil)
        try w.finished([callum, asher], every: 10)
        try w.finished(callum, dev, [callum, callum], at: 60, every: 20)
        try w.commit(play(start(at: 200), [callum], every: 60, from: 200).abandon(at: minutes(300)).value!)
        #expect(near(w.stats.averageFrameTime(callum), 1000))
        #expect(w.stats.averageFrameTime(asher) == 600)
    }

    @Test func averageMatchLengthIsForTheTwoPlayersOnThatWeekdayAndNilWhenNone() throws {
        let w = try World()
        let monday = Weekday.monday.rawValue, friday = Weekday.friday.rawValue
        #expect(w.stats.averageMatchLength(callum, asher, weekday: monday) == nil)

        try w.finished([callum, asher], every: 30)                     // Monday, 60 min
        try w.finished(asher, callum, [asher, asher], at: 7 * day, every: 60)   // next Monday, 120 min
        try w.finished([callum], at: 4 * day, every: 15)               // Friday
        try w.finished(callum, dev, [dev], at: 60, every: 200)         // Monday, other opponent
        try w.commit(play(start(at: 14 * day), [callum], every: 300, from: 14 * day).abandon(at: minutes(14 * day + 400)).value!)

        #expect(near(w.stats.averageMatchLength(callum, asher, weekday: monday), 90 * 60))
        #expect(near(w.stats.averageMatchLength(asher, callum, weekday: friday), 15 * 60))
        #expect(w.stats.averageMatchLength(callum, asher, weekday: Weekday.sunday.rawValue) == nil)
    }
}

/// Lengths are differences of `Date`s, so compare to the millisecond.
private func near(_ t: TimeInterval?, _ expected: TimeInterval) -> Bool {
    guard let t else { return false }
    return abs(t - expected) < 0.001
}
