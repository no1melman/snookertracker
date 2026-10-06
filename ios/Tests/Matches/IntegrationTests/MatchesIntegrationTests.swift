import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import SQLiteSupport
import Testing

// Outside-in: real use cases and adapters over a real SQLite database (in memory, or a temp file
// when a "relaunch" is simulated). The only stand-in is the Players supplier port, which belongs
// to another context.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
private let device = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

@MainActor
private final class FixedPlayers: MatchPlayerDirectory {
    let all = [
        MatchPlayer(id: callum, name: "Callum", colour: "blue"),
        MatchPlayer(id: asher, name: "Asher", colour: "orange"),
        MatchPlayer(id: dev, name: "Dev", colour: "green"),
    ]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

/// A clock the test moves by hand.
private final class Clock: @unchecked Sendable {
    var now = t0
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

/// The Matches composition, as the app root builds it.
@MainActor
private struct Stack {
    let db: SQLiteDatabase
    let store: SQLiteMatchEventStore
    let repository: EventSourcedMatchRepository
    let settings: MatchSettingsService
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases
    let dispatcher: EventDispatcher

    init(db: SQLiteDatabase, clock: Clock = Clock()) throws {
        self.db = db
        store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        repository = EventSourcedMatchRepository(store: store)
        settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db))
        let players = FixedPlayers()
        readModel = LiveMatchesProjection(players: players)
        dispatcher = EventDispatcher()
        commands = MatchUseCases(
            repository: repository, settings: settings, players: players, readModel: readModel,
            dispatcher: dispatcher, now: { clock.now })
        try commands.loadLiveMatches()
    }

    static func inMemory(clock: Clock = Clock()) throws -> Stack { try Stack(db: .inMemory(), clock: clock) }
}

private func tempDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "snooker-\(UUID().uuidString).sqlite")
}

private func setup(_ a: UUID = callum, _ b: UUID = asher, style: MatchesApplication.MatchStyle = .mostFramesWins) -> MatchSetup {
    MatchSetup(players: [a, b], game: .pool, style: style, breakRule: .alternate)
}

private func started(_ id: String, at: Date, players: (UUID, UUID) = (callum, asher)) -> Match {
    let setup = Setup.create(PlayerId(players.0), PlayerId(players.1), game: .pool, style: .mostFramesWins).value!
    return Match.start(id: MatchId.create(id).value!, setup: setup,
                       firstColour: Colour.create("red").value!, secondColour: Colour.create("blue").value!, at: at)
}

extension Result {
    fileprivate var value: Success? { try? get() }
}

// MARK: - Event store and repository (spec 006)

@MainActor
@Suite struct MatchEventStoreTests {
    @Test func aSavedMatchIsRebuiltIdenticallyFromItsStream() throws {
        let stack = try Stack.inMemory()
        let id = UUID()
        let match = started(id.uuidString, at: t0)
            .chooseBreaker(PlayerId(callum), at: t0.addingTimeInterval(10)).value!
            .awardFrame(to: PlayerId(asher), at: t0.addingTimeInterval(600)).value!
        try stack.repository.save(match)

        let loaded = try #require(try stack.repository.getById(id))
        #expect(loaded == match.committed())
        #expect(loaded.version == 3)
        #expect(loaded.score.secondFrames == 1)
    }

    @Test func anUnknownMatchIsNil() throws {
        #expect(try Stack.inMemory().repository.getById(UUID()) == nil)
    }

    @Test func savingFromAStaleCopyIsAConcurrencyConflict() throws {
        let stack = try Stack.inMemory()
        let id = UUID()
        try stack.repository.save(started(id.uuidString, at: t0))
        let copyA = try #require(try stack.repository.getById(id))
        let copyB = try #require(try stack.repository.getById(id))

        try stack.repository.save(copyA.chooseBreaker(PlayerId(callum), at: t0).value!)
        #expect(throws: MatchRepositoryError.concurrencyConflict(match: id, expectedVersion: 1, actualVersion: 2)) {
            try stack.repository.save(copyB.chooseBreaker(PlayerId(asher), at: t0).value!)
        }
        // The losing write left nothing behind.
        #expect(try stack.store.readStream(id.uuidString).count == 2)
    }

    @Test func findLiveListsOnlyLiveMatchesOldestStartedFirst() throws {
        let stack = try Stack.inMemory()
        let (late, early, ended) = (UUID(), UUID(), UUID())
        try stack.repository.save(started(late.uuidString, at: t0.addingTimeInterval(120)))
        try stack.repository.save(started(early.uuidString, at: t0))
        try stack.repository.save(started(ended.uuidString, at: t0.addingTimeInterval(-60)).cancel(at: t0).value!)

        #expect(try stack.repository.findLive().map(\.id.value) == [early.uuidString, late.uuidString])
    }

    @Test func findByPlayerFindsEveryMatchWithThatPlayerOnEitherSide() throws {
        let stack = try Stack.inMemory()
        let (a, b, c) = (UUID(), UUID(), UUID())
        try stack.repository.save(started(a.uuidString, at: t0, players: (callum, asher)))
        try stack.repository.save(started(b.uuidString, at: t0.addingTimeInterval(60), players: (dev, callum)).abandon(at: t0).value!)
        try stack.repository.save(started(c.uuidString, at: t0.addingTimeInterval(120), players: (asher, dev)))

        #expect(try stack.repository.findByPlayer(callum).map(\.id.value) == [a.uuidString, b.uuidString])
        #expect(try stack.repository.findByPlayer(dev).map(\.id.value) == [b.uuidString, c.uuidString])
    }

    @Test func aWholeStreamReadsBackInOrderWithEventIdsAndOriginDevice() throws {
        let db = try SQLiteDatabase.inMemory()
        let store = try SQLiteMatchEventStore(db: db, originDevice: device)
        let repository = EventSourcedMatchRepository(store: store)
        let id = UUID()
        var match = started(id.uuidString, at: t0)
        try repository.save(match)
        match = try #require(try repository.getById(id))
        match = match.chooseBreaker(PlayerId(callum), at: t0).value!
            .awardFrame(to: PlayerId(callum), at: t0.addingTimeInterval(300)).value!
            .pause(at: t0.addingTimeInterval(400)).value!
        try repository.save(match)

        let stream = try store.readStream(id.uuidString)
        #expect(stream.map(\.streamVersion) == [1, 2, 3, 4])
        #expect(stream.map(\.event) == [started(id.uuidString, at: t0).uncommittedEvents[0]] + match.uncommittedEvents)
        #expect(Set(stream.map(\.eventId)).count == 4)
        #expect(stream.allSatisfy { $0.originDevice == device })
        #expect(try store.allStreams() == [id.uuidString])
    }

    @Test func everyStoredEventIsVersionedOnTheWire() throws {
        let db = try SQLiteDatabase.inMemory()
        let repository = EventSourcedMatchRepository(store: try SQLiteMatchEventStore(db: db, originDevice: device))
        try repository.save(started(UUID().uuidString, at: t0))
        let row = try #require(try db.query("SELECT type, schema_version FROM match_events").first)
        #expect(row.string("type") == "MatchStarted")
        #expect(row.int("schema_version") == 1)
    }
}

// MARK: - Use cases and read models (specs 007, 009, 010)

@MainActor
@Suite struct MatchUseCaseTests {
    @Test func scoringAMatchSurvivesARelaunch() throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock()
        let id: MatchID
        do {
            let app = try Stack(db: SQLiteDatabase(url: url), clock: clock)
            id = try app.commands.startMatch(setup(style: .raceTo(5)))
            try app.commands.chooseBreaker(id, player: asher)
            for winner in [asher, callum, asher] {
                clock.advance(minutes: 5)
                try app.commands.awardFrame(id, to: winner)
            }
            clock.advance(minutes: 2)
            app.settings.changeLiveMatchLimit(4)
        }

        clock.advance(minutes: 1)
        let relaunched = try Stack(db: SQLiteDatabase(url: url), clock: clock)
        let screen = try #require(relaunched.readModel.liveMatchScreen(id))
        #expect(screen.sides.map(\.name) == ["Callum", "Asher"])
        #expect(screen.sides.map(\.frames) == [1, 2])
        #expect(screen.style == .raceTo(5))
        #expect(screen.sides.first { $0.isBreaker }?.id == callum)  // alternate: frame 4 is Callum's break
        // Timers carry on from the stored timestamps: 18 min in, frame 4 started 3 min ago.
        #expect(screen.matchTimer.elapsed(at: clock.now) == 18 * 60)
        #expect(screen.frameTimer.elapsed(at: clock.now) == 3 * 60)
        #expect(relaunched.readModel.liveMatches.map(\.id) == [id])
        #expect(relaunched.settings.liveMatchLimit == 4)
    }

    @Test func liveMatchesAreOldestFirstAndShowThePausedFlag() throws {
        let clock = Clock()
        let app = try Stack.inMemory(clock: clock)
        let first = try app.commands.startMatch(setup())
        clock.advance(minutes: 1)
        let second = try app.commands.startMatch(setup(asher, dev))
        try app.commands.pauseMatch(first)

        #expect(app.readModel.liveMatches.map(\.id) == [first, second])
        #expect(app.readModel.liveMatches.map(\.isPaused) == [true, false])
        let paused = try #require(app.readModel.liveMatchScreen(first))
        #expect(paused.controls == .init(chooseBreaker: false, award: false, removeFrom: [], pause: false, resume: true))
    }

    @Test func theLiveMatchLimitIsEnforcedOnStart() throws {
        let app = try Stack.inMemory()
        app.settings.changeLiveMatchLimit(1)
        _ = try app.commands.startMatch(setup())
        #expect(throws: MatchCommandError.liveMatchLimitReached(1)) { try app.commands.startMatch(setup(asher, dev)) }
    }

    @Test func defaultsAreStoredAndOfferedToNewGame() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try Stack(db: db)
        #expect(app.settings.defaults == MatchesApplication.MatchDefaults())
        #expect(app.settings.liveMatchLimit == 10)
        try app.settings.changeDefaults(.init(game: .snooker, style: .bestOf(7), breakRule: .winnerBreaks))
        #expect(throws: MatchCommandError.invalidTargets) {
            try app.settings.changeDefaults(.init(game: .pool, style: .bestOf(4), breakRule: .alternate))
        }
        let reopened = try Stack(db: db)
        #expect(reopened.settings.defaults == .init(game: .snooker, style: .bestOf(7), breakRule: .winnerBreaks))
    }

    @Test func finishingShortOfTheTargetAsksFirstThenEndsTheMatch() throws {
        let app = try Stack.inMemory()
        let id = try app.commands.startMatch(setup(style: .raceTo(3)))
        try app.commands.chooseBreaker(id, player: callum)
        try app.commands.awardFrame(id, to: callum)

        #expect(throws: MatchCommandError.finishShortOfTarget) { try app.commands.finishMatch(id) }
        #expect(app.readModel.liveMatchScreen(id) != nil)

        try app.commands.finishMatch(id, anyway: true)
        #expect(app.readModel.liveMatchScreen(id) == nil)
        #expect(try app.repository.getById(id)?.status == .finished)
    }

    @Test func reachingTheTargetAsksToFinishAndUndoTakesItBack() throws {
        let app = try Stack.inMemory()
        let id = try app.commands.startMatch(setup(style: .raceTo(2)))
        try app.commands.chooseBreaker(id, player: callum)
        try app.commands.awardFrame(id, to: asher)
        try app.commands.awardFrame(id, to: asher)
        #expect(app.readModel.liveMatchScreen(id)?.targetReachedBy == asher)

        try app.commands.removeFrame(id, from: asher)
        #expect(app.readModel.liveMatchScreen(id)?.targetReachedBy == nil)
        try app.commands.awardFrame(id, to: asher)
        try app.commands.finishMatch(id)
        #expect(app.readModel.liveMatches.isEmpty)
    }

    @Test func abandonAndCancelEndTheMatch() throws {
        let app = try Stack.inMemory()
        let a = try app.commands.startMatch(setup())
        let b = try app.commands.startMatch(setup(asher, dev))
        try app.commands.abandonMatch(a)
        try app.commands.cancelMatch(b)
        #expect(app.readModel.liveMatches.isEmpty)
        #expect(try app.repository.getById(a)?.status == .abandoned)
        #expect(try app.repository.getById(b)?.status == .cancelled)
        #expect(throws: MatchCommandError.notAllowedNow) { try app.commands.awardFrame(a, to: callum) }
    }

    @Test func anEndedMatchCanBeDeletedAndTheDeletionIsPublished() throws {
        let app = try Stack.inMemory()
        nonisolated(unsafe) var received: [String] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { received.append($0.type) }
        let id = try app.commands.startMatch(setup())
        try app.commands.abandonMatch(id)

        try app.commands.deleteMatch(id)

        #expect(try app.repository.getById(id)?.status == .deleted)
        #expect(received.last == "MatchDeleted")
        #expect(throws: MatchCommandError.notAllowedNow) { try app.commands.deleteMatch(id) }
    }

    @Test func aLiveMatchCannotBeDeleted() throws {
        let app = try Stack.inMemory()
        let id = try app.commands.startMatch(setup())
        #expect(throws: MatchCommandError.notAllowedNow) { try app.commands.deleteMatch(id) }
        #expect(app.readModel.liveMatches.count == 1)
    }

    // MARK: Finish all (S43)

    @Test func finishAllFinishesTheFinishableAndAbandonsTheRestAfterOneWarning() throws {
        let app = try Stack.inMemory()
        nonisolated(unsafe) var received: [String] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { received.append($0.type) }
        let mostFrames = try app.commands.startMatch(setup())
        let reached = try app.commands.startMatch(setup(asher, dev, style: .raceTo(2)))
        try app.commands.chooseBreaker(reached, player: asher)
        try app.commands.awardFrame(reached, to: dev)
        try app.commands.awardFrame(reached, to: dev)
        let short = try app.commands.startMatch(setup(callum, dev, style: .bestOf(5)))
        try app.commands.chooseBreaker(short, player: dev)
        try app.commands.awardFrame(short, to: callum)
        try app.commands.pauseMatch(short)

        #expect(try app.commands.finishAllMatchesPreview() == FinishAllPreview(finishing: 2, abandoning: 1))
        received = []
        try app.commands.finishAllMatches()

        #expect(app.readModel.liveMatches.isEmpty)
        #expect(try app.repository.getById(mostFrames)?.status == .finished)
        #expect(try app.repository.getById(reached)?.status == .finished)
        #expect(try app.repository.getById(short)?.status == .abandoned)
        #expect(received.sorted() == ["MatchAbandoned", "MatchFinished", "MatchFinished"])
    }

    @Test func finishAllWarnsOfNothingWhenEveryMatchCanFinish() throws {
        let app = try Stack.inMemory()
        _ = try app.commands.startMatch(setup())
        _ = try app.commands.startMatch(setup(asher, dev))
        let preview = try app.commands.finishAllMatchesPreview()
        #expect(!preview.willAbandonAny && preview.finishing == 2)
        try app.commands.finishAllMatches()
        #expect(app.readModel.liveMatches.isEmpty)
    }

    // MARK: Correct score (S29)

    @Test func anEndedRaceToScoreIsCorrectedOnTargetOnly() throws {
        let app = try Stack.inMemory()
        nonisolated(unsafe) var received: [String] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { received.append($0.type) }
        let id = try app.commands.startMatch(setup(style: .raceTo(3)))
        try app.commands.chooseBreaker(id, player: callum)
        for _ in 0..<3 { try app.commands.awardFrame(id, to: callum) }
        try app.commands.finishMatch(id)

        #expect(throws: MatchCommandError.correctionNotOnTarget(3)) {
            try app.commands.correctMatchScore(id, to: .frames(first: 2, second: 1), confirmed: false)
        }
        try app.commands.correctMatchScore(id, to: .frames(first: 3, second: 2), confirmed: false)

        let match = try #require(try app.repository.getById(id))
        #expect(match.status == .finished)
        #expect((match.score.firstFrames, match.score.secondFrames) == (3, 2))
        #expect(received.last == "MatchScoreCorrected")
    }

    @Test func aSecondCorrectionBuildsOnTheFirstAndBothAreKept() throws {
        let app = try Stack.inMemory()
        let id = try app.commands.startMatch(setup())
        try app.commands.chooseBreaker(id, player: callum)
        try app.commands.awardFrame(id, to: asher)
        try app.commands.finishMatch(id)

        try app.commands.correctMatchScore(id, to: .frames(first: 4, second: 2), confirmed: false)
        try app.commands.correctMatchScore(id, to: .frames(first: 4, second: 5), confirmed: false)

        let match = try #require(try app.repository.getById(id))
        #expect((match.score.firstFrames, match.score.secondFrames) == (4, 5))
        #expect(try app.store.readStream(id.uuidString).filter {
            if case .matchScoreCorrected = $0.event { true } else { false }
        }.count == 2)
    }

    @Test func anInconsistentSetsCorrectionIsConfirmedBeforeItIsSaved() throws {
        let app = try Stack.inMemory()
        let id = UUID()
        let style = MatchesDomain.MatchStyle.sets(sets: Target.raceTo(2).value!, frames: Target.raceTo(3).value!)
        let s = Setup.create(PlayerId(callum), PlayerId(asher), game: .pool, style: style).value!
        try app.repository.save(Match.start(id: MatchId(id), setup: s, firstColour: Colour.create("red").value!,
                                            secondColour: Colour.create("blue").value!, at: t0)
            .finish(at: t0.addingTimeInterval(60), anyway: true).value!)
        let before = try app.store.readStream(id.uuidString).count

        #expect(throws: MatchCommandError.correctionNeedsConfirmation(["Set 1 doesn't end with one player on the frames target."])) {
            try app.commands.correctMatchScore(id, to: .sets([SetScore(first: 2, second: 2), SetScore(first: 3, second: 0), SetScore(first: 3, second: 1)]), confirmed: false)
        }
        #expect(try app.store.readStream(id.uuidString).count == before)

        try app.commands.correctMatchScore(id, to: .sets([SetScore(first: 2, second: 2), SetScore(first: 3, second: 0), SetScore(first: 3, second: 1)]), confirmed: true)
        #expect(try app.store.readStream(id.uuidString).count == before + 1)
    }

    @Test func aCancelledMatchCannotBeCorrected() throws {
        let app = try Stack.inMemory()
        let id = try app.commands.startMatch(setup())
        try app.commands.cancelMatch(id)
        #expect(throws: MatchCommandError.notAllowedNow) {
            try app.commands.correctMatchScore(id, to: .frames(first: 1, second: 0), confirmed: true)
        }
    }

    // MARK: Mark finished (S31)

    @Test func anAbandonedMatchCanBeMarkedFinishedWithTheLeaderWinning() throws {
        let app = try Stack.inMemory()
        nonisolated(unsafe) var received: [String] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { received.append($0.type) }
        let id = try app.commands.startMatch(setup(style: .raceTo(5)))
        try app.commands.chooseBreaker(id, player: callum)
        try app.commands.awardFrame(id, to: asher)
        try app.commands.abandonMatch(id)

        try app.commands.markMatchFinished(id)

        let match = try #require(try app.repository.getById(id))
        #expect(match.status == .finished)
        #expect(match.result == .win(match.second))
        #expect(received.last == "MatchMarkedFinished")
        #expect(throws: MatchCommandError.notAllowedNow) { try app.commands.markMatchFinished(id) }
    }

    @Test func storedEventsArePublishedAfterTheSave() throws {
        let app = try Stack.inMemory()
        nonisolated(unsafe) var received: [MatchEventPublished] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { received.append($0) }

        let id = try app.commands.startMatch(setup())
        try app.commands.chooseBreaker(id, player: callum)

        #expect(received.map(\.type) == ["MatchStarted", "BreakerChosen"])
        #expect(received.map(\.streamVersion) == [1, 2])
        let stored = try app.store.readStream(id.uuidString)
        #expect(received.map(\.eventId) == stored.map(\.eventId))
    }
}
