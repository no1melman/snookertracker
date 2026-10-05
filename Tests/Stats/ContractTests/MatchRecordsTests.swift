import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import StatsApplication
import StatsInfrastructure
import Testing

// Outside-in (spec 013): Matches' real event store and wire produce the published events; Stats'
// real projection and SQLite store take them in; assertions read the projection's queries, and
// relaunch tests re-open the same database file.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

extension Result {
    fileprivate var value: Success? { try? get() }
}

/// Matches' side (store + repository + open-host replay) and Stats' side, on one database.
@MainActor
private final class World {
    let db: SQLiteDatabase
    let store: SQLiteMatchEventStore
    let repository: EventSourcedMatchRepository
    let history: SQLiteMatchEventHistory
    let dispatcher = EventDispatcher()
    let stats: MatchRecordsProjection

    init(db: SQLiteDatabase, statsSubscribed: Bool = true) throws {
        self.db = db
        store = try SQLiteMatchEventStore(db: db, originDevice: UUID())
        repository = EventSourcedMatchRepository(store: store)
        history = SQLiteMatchEventHistory(db: db, store: store)
        stats = try MatchRecordsProjection(store: SQLiteStatsStore(db: db))
        if statsSubscribed { stats.subscribe(to: dispatcher) }
    }

    static func inMemory(statsSubscribed: Bool = true) throws -> World {
        try World(db: .inMemory(), statsSubscribed: statsSubscribed)
    }

    /// save → dispatch the Stage 2 events, as Matches' use cases do.
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

    func addPlayers() {
        player("PlayerAdded", callum, ["name": "Callum", "colour": "blue"])
        player("PlayerAdded", asher, ["name": "Asher", "colour": "orange"])
        player("PlayerAdded", dev, ["name": "Dev", "colour": "green"])
    }
}

private func start(
    _ a: UUID = callum, _ b: UUID = asher, style: MatchesDomain.MatchStyle = .mostFramesWins, at: Date = t0
) -> Match {
    let setup = Setup.create(PlayerId(a), PlayerId(b), game: .pool, style: style).value!
    return Match.start(id: MatchId(UUID()), setup: setup,
                       firstColour: Colour.create("blue").value!, secondColour: Colour.create("orange").value!, at: at)
}

/// Breaker chosen at t+0, then one frame per entry, `every` minutes apart.
private func play(_ match: Match, _ winners: [UUID], every: Double = 10, from: Double = 0) -> Match {
    var m = match.chooseBreaker(PlayerId(winners.first ?? callum), at: minutes(from)).value!
    for (i, w) in winners.enumerated() {
        m = m.awardFrame(to: PlayerId(w), at: minutes(from + every * Double(i + 1))).value!
    }
    return m
}

private func uuid(_ m: Match) -> UUID { UUID(uuidString: m.id.value)! }

private let all = PastMatchesFilter(showCancelled: true, includeArchivedPlayers: true)

// MARK: - PastMatches

@MainActor
@Suite struct PastMatchesTests {
    @Test func aFinishedMatchIsInHistoryWithPlayersScoreResultStyleAndLength() throws {
        let w = try World.inMemory()
        w.addPlayers()
        let m = play(start(style: .raceTo(Target.raceTo(3).value!)), [callum, asher, callum, callum])
        try w.commit(m.finish(at: minutes(41)).value!)

        let row = try #require(w.stats.pastMatches(PastMatchesFilter()).first)
        #expect(row.id == uuid(m))
        #expect(row.first.name == "Callum" && row.second.name == "Asher")
        #expect(row.first.colour == "blue")
        #expect(row.score == ScoreLine(first: 3, second: 1))
        #expect(row.status == .finished)
        #expect(row.winner == callum)
        #expect(row.style == "Race to 3")
        #expect(row.game == "pool")
        #expect(row.startedAt == t0)
        #expect(abs((row.length ?? 0) - 40 * 60) < 0.001)
        #expect(!row.isAltered)
    }

    @Test func liveMatchesAreNotHistory() throws {
        let w = try World.inMemory()
        try w.commit(play(start(), [callum]))
        #expect(w.stats.pastMatches(all).isEmpty)
    }

    @Test func pastMatchesAreNewestFirst() throws {
        let w = try World.inMemory()
        for day in [2.0, 0, 1] {
            let m = start(at: minutes(day * 1440))
            try w.commit(play(m, [callum], from: day * 1440).finish(at: minutes(day * 1440 + 20)).value!)
        }
        #expect(w.stats.pastMatches(all).map(\.startedAt) == [minutes(2880), minutes(1440), t0])
    }

    @Test func cancelledMatchesShowOnlyWhenAskedFor() throws {
        let w = try World.inMemory()
        try w.commit(start().cancel(at: minutes(1)).value!)
        try w.commit(play(start(), [asher]).abandon(at: minutes(15)).value!)

        let shown = w.stats.pastMatches(PastMatchesFilter(showCancelled: false))
        #expect(shown.map(\.status) == [.abandoned])
        #expect(shown.first?.winner == nil)
        #expect(Set(w.stats.pastMatches(PastMatchesFilter(showCancelled: true)).map(\.status)) == [.abandoned, .cancelled])
    }

    @Test func matchesWithArchivedPlayersShowOnlyWhenIncluded() throws {
        let w = try World.inMemory()
        w.addPlayers()
        try w.commit(play(start(callum, dev), [dev]).finish(at: minutes(20)).value!)
        try w.commit(play(start(callum, asher), [asher]).finish(at: minutes(20)).value!)
        w.player("PlayerArchived", dev)

        #expect(w.stats.pastMatches(PastMatchesFilter(includeArchivedPlayers: false)).map(\.second.name) == ["Asher"])
        let included = w.stats.pastMatches(PastMatchesFilter(includeArchivedPlayers: true))
        #expect(included.count == 2)
        #expect(included.contains { $0.second.name == "Dev" && $0.second.isArchived })

        w.player("PlayerUnarchived", dev)
        #expect(w.stats.pastMatches(PastMatchesFilter(includeArchivedPlayers: false)).count == 2)
    }

    @Test func renamesShowEverywhereAtOnce() throws {
        let w = try World.inMemory()
        w.addPlayers()
        try w.commit(play(start(), [asher]).finish(at: minutes(20)).value!)
        w.player("PlayerRenamed", asher, ["oldName": "Asher", "newName": "Ash"])
        w.player("PlayerColourChanged", asher, ["oldColour": "orange", "newColour": "red"])
        let row = try #require(w.stats.pastMatches(all).first)
        #expect(row.second.name == "Ash" && row.second.colour == "red")
    }
}

// MARK: - Corrections, mark finished, deletion, merges, removals

@MainActor
@Suite struct MatchRecordRebuildTests {
    @Test func aCorrectedScoreIsShownAlteredWithTheOriginalKept() throws {
        let w = try World.inMemory()
        var m = try w.commit(play(start(), [callum, asher, callum]).finish(at: minutes(35)).value!)
        let correction = ScoreCorrection.frames(first: 2, second: 2, for: .mostFramesWins).value!
        m = try w.commit(m.correctScore(correction, at: minutes(60)).value!)

        let row = try #require(w.stats.pastMatches(all).first)
        #expect(row.score == ScoreLine(first: 2, second: 2))
        #expect(row.isAltered)
        #expect(row.isDraw && row.winner == nil)

        let timeline = try #require(w.stats.timeline(uuid(m)))
        #expect(timeline.originalScore == ScoreLine(first: 2, second: 1))
        #expect(timeline.corrections.count == 1)
        #expect(timeline.corrections[0].before == ScoreLine(first: 2, second: 1))
        #expect(timeline.corrections[0].after == ScoreLine(first: 2, second: 2))
        // The frames as played are untouched.
        #expect(timeline.frames.last?.runningScore == ScoreLine(first: 2, second: 1))
    }

    @Test func markingAnAbandonedMatchFinishedGivesItAResult() throws {
        let w = try World.inMemory()
        var m = try w.commit(play(start(), [asher, asher, callum]).abandon(at: minutes(31)).value!)
        #expect(w.stats.pastMatches(all).first?.status == .abandoned)

        m = try w.commit(m.markFinished(at: minutes(90)).value!)
        let row = try #require(w.stats.pastMatches(all).first)
        #expect(row.status == .finished)
        #expect(row.winner == asher)
        #expect(w.stats.timeline(uuid(m))?.markedFinishedAt == minutes(90))
    }

    @Test func aDeletedMatchLeavesHistory() throws {
        let w = try World.inMemory()
        let m = try w.commit(play(start(), [callum]).finish(at: minutes(12)).value!)
        try w.commit(m.delete(at: minutes(30)).value!)
        #expect(w.stats.pastMatches(all).isEmpty)
        #expect(w.stats.timeline(uuid(m)) == nil)
    }

    @Test func aMergedAwayPlayersMatchesShowUnderTheKeptPlayer() throws {
        let w = try World.inMemory()
        w.addPlayers()
        try w.commit(play(start(callum, dev), [dev]).finish(at: minutes(12)).value!)
        w.player("PlayersMerged", dev, ["keptPlayerId": asher.uuidString, "foldedInPlayerId": dev.uuidString])

        let row = try #require(w.stats.pastMatches(all).first)
        #expect(row.second.id == asher && row.second.name == "Asher")
        #expect(row.winner == asher)
    }

    @Test func aRemovedPlayersMatchesLeaveHistory() throws {
        let w = try World.inMemory()
        w.addPlayers()
        try w.commit(play(start(callum, dev), [dev]).finish(at: minutes(12)).value!)
        try w.commit(play(start(callum, asher), [asher]).finish(at: minutes(12)).value!)
        w.player("PlayerArchived", dev)
        w.player("PlayerRemoved", dev)
        #expect(w.stats.pastMatches(all).map(\.second.name) == ["Asher"])
    }
}

// MARK: - MatchTimeline

@MainActor
@Suite struct MatchTimelineTests {
    @Test func eachFrameHasItsWinnerFrameTimeMatchTimeAndRunningScore() throws {
        let w = try World.inMemory()
        w.addPlayers()
        var m = start().chooseBreaker(PlayerId(callum), at: t0).value!
        m = m.awardFrame(to: PlayerId(callum), at: minutes(10)).value!
        m = m.pause(at: minutes(12)).value!.resume(at: minutes(17)).value!
        m = m.awardFrame(to: PlayerId(asher), at: minutes(25)).value!
        m = m.awardFrame(to: PlayerId(asher), at: minutes(30)).value!
        try w.commit(m.finish(at: minutes(30)).value!)

        let t = try #require(w.stats.timeline(uuid(m)))
        #expect(t.frames.map(\.number) == [1, 2, 3])
        #expect(t.frames.map(\.winner.name) == ["Callum", "Asher", "Asher"])
        #expect(t.frames.map(\.frameTime) == [600, 600, 300])
        #expect(t.frames.map(\.matchTime) == [600, 1200, 1500])
        #expect(t.frames.map(\.runningScore) == [
            ScoreLine(first: 1, second: 0), ScoreLine(first: 1, second: 1), ScoreLine(first: 1, second: 2),
        ])
        #expect(t.match.length == 1500)
    }

    @Test func aRemovedFrameLeavesTheTimeline() throws {
        let w = try World.inMemory()
        var m = play(start(), [callum, asher, callum])
        m = m.removeFrame(from: PlayerId(asher), at: minutes(31)).value!
        m = m.awardFrame(to: PlayerId(callum), at: minutes(40)).value!
        try w.commit(m.finish(at: minutes(41)).value!)

        let t = try #require(w.stats.timeline(uuid(m)))
        #expect(t.frames.map(\.number) == [1, 2, 3])
        #expect(t.frames.map(\.winner.id) == [callum, callum, callum])
        #expect(t.match.score == ScoreLine(first: 3, second: 0))
    }

    @Test func aSetsMatchCarriesItsRunningSetScore() throws {
        let w = try World.inMemory()
        let style = MatchesDomain.MatchStyle.sets(sets: Target.raceTo(2).value!, frames: Target.raceTo(2).value!)
        let m = play(start(style: style), [callum, callum, asher, asher, asher, asher])
        try w.commit(m.finish(at: minutes(60)).value!)

        let t = try #require(w.stats.timeline(uuid(m)))
        #expect(t.isSets)
        #expect(t.frames.map(\.setNumber) == [1, 1, 2, 2, 3, 3])
        #expect(t.frames.map(\.wonSet) == [false, true, false, true, false, true])
        #expect(t.frames[3].runningScore == ScoreLine(first: 2, second: 2, firstSets: 1, secondSets: 1))
        #expect(t.match.score == ScoreLine(first: 2, second: 4, firstSets: 1, secondSets: 2))
        #expect(t.match.winner == asher)
        #expect(t.match.style == "Race to 2 sets · race to 2")
    }
}

// MARK: - Catch-up and rebuild

@MainActor
@Suite struct CatchUpTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stats-\(UUID().uuidString).sqlite")
    }

    @Test func matchesRecordedBeforeStatsExistedAreCaughtUpOnce() throws {
        // Matches ran without Stats listening (an install from before Stats existed).
        let w = try World.inMemory(statsSubscribed: false)
        let finished = try w.commit(play(start(), [callum, asher, asher]).finish(at: minutes(31)).value!)
        try w.commit(start().cancel(at: minutes(2)).value!)
        let live = try w.commit(play(start(), [callum]))
        #expect(w.stats.pastMatches(all).isEmpty)

        #expect(try w.stats.catchUp(from: w.history) == 3)
        #expect(w.stats.pastMatches(all).count == 2)
        #expect(w.stats.pastMatches(all).contains { $0.id == uuid(finished) && $0.winner == asher })

        // Nothing new: nothing to do. The live match ends later and is caught up then.
        #expect(try w.stats.catchUp(from: w.history) == 0)
        try w.commit(live.finish(at: minutes(20)).value!)
        #expect(try w.stats.catchUp(from: w.history) == 1)
        #expect(w.stats.pastMatches(all).count == 3)
    }

    @Test func catchUpAndLiveDispatchNeverDoubleCount() throws {
        let w = try World.inMemory()
        let m = try w.commit(play(start(), [callum, callum]).finish(at: minutes(21)).value!)
        try w.stats.catchUp(from: w.history)
        try w.stats.rebuildAll()
        let t = try #require(w.stats.timeline(uuid(m)))
        #expect(t.frames.count == 2)
        #expect(t.match.score == ScoreLine(first: 2, second: 0))
    }

    @Test func historySurvivesARelaunch() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let id: UUID
        do {
            let w = try World(db: SQLiteDatabase(url: url))
            w.addPlayers()
            id = uuid(try w.commit(play(start(), [asher]).finish(at: minutes(11)).value!))
        }
        let relaunched = try World(db: SQLiteDatabase(url: url))
        let row = try #require(relaunched.stats.pastMatches(all).first)
        #expect(row.id == id && row.second.name == "Asher" && row.winner == asher)
        #expect(try relaunched.stats.catchUp(from: relaunched.history) == 0)
    }

    @Test func projectionsRebuildFromScratchToTheSameRecords() throws {
        let w = try World.inMemory()
        var m = try w.commit(play(start(), [callum, asher]).abandon(at: minutes(25)).value!)
        m = try w.commit(m.markFinished(at: minutes(40)).value!)
        try w.commit(play(start(at: minutes(60)), [asher], from: 60).finish(at: minutes(75)).value!)
        let before = w.stats.pastMatches(all)
        try w.stats.rebuildAll()
        #expect(w.stats.pastMatches(all) == before)
        #expect(before.count == 2)
    }
}

// MARK: - Through Matches' use cases

@MainActor
private final class Directory: MatchPlayerDirectory {
    var suggestions: [MatchPlayer] { [MatchPlayer(id: callum, name: "Callum", colour: "blue"), MatchPlayer(id: asher, name: "Asher", colour: "orange")] }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { suggestions.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

@MainActor
@Suite struct UseCaseFlowTests {
    @Test func aMatchFinishedThroughTheUseCasesLandsInHistory() throws {
        let w = try World.inMemory()
        w.addPlayers()
        let directory = Directory()
        let commands = MatchUseCases(
            repository: w.repository, settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: w.db)),
            players: directory, readModel: LiveMatchesProjection(players: directory), dispatcher: w.dispatcher)
        let id = try commands.startMatch(MatchSetup(players: [callum, asher], game: .snooker, style: .bestOf(3), breakRule: .alternate))
        try commands.chooseBreaker(id, player: callum)
        try commands.awardFrame(id, to: asher)
        try commands.awardFrame(id, to: asher)
        try commands.finishMatch(id, anyway: false)

        let row = try #require(w.stats.pastMatches(PastMatchesFilter()).first)
        #expect(row.id == id && row.winner == asher && row.score == ScoreLine(first: 0, second: 2))
        #expect(row.style == "Best of 3" && row.game == "snooker")
        #expect(w.stats.lastError == nil)
    }
}
