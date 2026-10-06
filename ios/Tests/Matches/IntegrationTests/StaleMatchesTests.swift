import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import SQLiteSupport
import StatsPublished
import Testing

// FlagStaleMatches and ResolveStaleMatch (S28), outside-in over a real SQLite database. Stats' open host
// (`MatchStatsQueries`) is an in-memory stand-in: its averages are inputs here, and its own tests
// (StatsQueriesTests) cover how they are computed.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
/// A Friday, 19:00 UTC.
private let t0 = Date(timeIntervalSince1970: 1_790_362_800)
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
private func hours(_ h: Double) -> Date { minutes(h * 60) }

@MainActor
private final class Players: MatchPlayerDirectory {
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

/// Stats' answers, set per test. Records the weekday it was asked about.
@MainActor
private final class StatsAnswers: MatchStatsQueries {
    var frameTimes: [UUID: TimeInterval] = [:]
    var matchLength: TimeInterval?
    var askedWeekdays: [Int] = []

    func headToHead(_ a: UUID, _ b: UUID) -> HeadToHead { .none }
    func averageFrameTime(_ player: UUID) -> TimeInterval? { frameTimes[player] }
    func averageMatchLength(_ a: UUID, _ b: UUID, weekday: Int) -> TimeInterval? {
        askedWeekdays.append(weekday)
        return matchLength
    }
}

private final class Clock: @unchecked Sendable {
    var now = t0
}

@MainActor
private struct App {
    let store: SQLiteMatchEventStore
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases
    let stale: StaleMatchUseCases
    let stats = StatsAnswers()
    let dispatcher = EventDispatcher()
    let clock: Clock

    init(url: URL, clock: Clock) throws {
        self.clock = clock
        let db = try SQLiteDatabase(url: url)
        store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = Players()
        readModel = LiveMatchesProjection(players: players)
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)),
            players: players, readModel: readModel, dispatcher: dispatcher, now: { clock.now })
        stale = StaleMatchUseCases(matches: commands, stats: stats, players: players, calendar: utc, now: { clock.now })
    }

    /// Starts a match with `a` breaking, at `at`.
    func start(_ a: UUID, _ b: UUID, style: MatchesApplication.MatchStyle = .mostFramesWins, at: Date) throws -> MatchID {
        clock.now = at
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: style, breakRule: .alternate))
        try commands.chooseBreaker(id, player: a)
        return id
    }

    func award(_ id: MatchID, to player: UUID, at: Date) throws {
        clock.now = at
        try commands.awardFrame(id, to: player)
    }

    func flag(at: Date) throws -> [StaleMatchPrompt] {
        clock.now = at
        return try stale.flagStaleMatches()
    }

    func events(_ id: MatchID) throws -> [MatchEvent] { try store.readStream(id.uuidString).map(\.event) }

    func finished(_ id: MatchID) throws -> MatchFinished? {
        try events(id).compactMap { if case .matchFinished(let e) = $0 { e } else { nil } }.last
    }
}

@MainActor
@Suite struct StaleMatchesTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "stale-\(UUID().uuidString).sqlite")
    fileprivate let clock = Clock()

    // MARK: FlagStaleMatches

    @Test func staleMatchesArePromptedOneAtATimeOldestStartedFirst() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let oldest = try app.start(callum, asher, at: minutes(0))
        let next = try app.start(dev, asher, at: minutes(5))
        let recent = try app.start(callum, dev, at: minutes(10))
        // The oldest was played later than the next, but prompt order is start order.
        try app.award(oldest, to: callum, at: minutes(30))
        try app.award(recent, to: dev, at: hours(2))

        let prompts = try app.flag(at: hours(7))

        #expect(prompts.map(\.id) == [oldest, next])
        #expect(!prompts.map(\.id).contains(recent))
        #expect(prompts[0].sides.map(\.name) == ["Callum", "Asher"])
        #expect(prompts[0].sides.map(\.frames) == [1, 0])
        #expect(abs(prompts[0].idle - (7 * 3600 - 30 * 60)) < 0.001)
        #expect(abs(prompts[1].idle - (7 * 3600 - 5 * 60)) < 0.001)
    }

    @Test func aMatchIdleForJustUnderSixHoursIsNotPrompted() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))

        #expect(try app.flag(at: minutes(6 * 60 - 1)).isEmpty)
        #expect(try app.flag(at: hours(6)).map(\.id) == [id])
    }

    @Test func flaggingIsStoredButNotPublishedAndDoesNotResetTheIdleTime() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        var published: [String] = []
        app.dispatcher.subscribe(MatchEventPublished.self) { published.append($0.type) }
        let id = try app.start(callum, asher, at: minutes(0))

        _ = try app.flag(at: hours(7))
        let again = try app.flag(at: hours(8))

        #expect(try app.events(id).filter { if case .staleMatchFlagged = $0 { true } else { false } }.count == 2)
        #expect(!published.contains("StaleMatchFlagged"))
        #expect(abs((again.first?.idle ?? 0) - 8 * 3600) < 0.001)
    }

    @Test func withNoHistoryTheCapFallsBackToThreeHours() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        _ = try app.start(callum, asher, at: minutes(0))

        let prompt = try #require(try app.flag(at: hours(30)).first)

        #expect(prompt.cappedLength == 3 * 3600)
        #expect(!prompt.cappedFromHistory)
        #expect(abs(prompt.ranFor - 30 * 3600) < 0.001)
    }

    @Test func theCapIsThePairsAverageOnTheStartsWeekday() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        app.stats.matchLength = 2 * 3600 + 45 * 60
        _ = try app.start(callum, asher, at: minutes(0))

        let prompt = try #require(try app.flag(at: hours(30)).first)

        #expect(prompt.cappedLength == 2 * 3600 + 45 * 60)
        #expect(prompt.cappedFromHistory)
        #expect(prompt.weekday == 6)  // Friday, the start's weekday, not the flag's (Saturday)
        #expect(app.stats.askedWeekdays == [6])
    }

    @Test func theSuggestedEndIsTheLastFrameTimePlusTheWinnersAverageFrameTime() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        app.stats.frameTimes[asher] = 20 * 60
        let id = try app.start(callum, asher, at: minutes(0))
        try app.award(id, to: asher, at: minutes(15))

        let prompt = try #require(try app.flag(at: hours(10)).first)

        #expect(prompt.suggestedEndTime == minutes(35))
        #expect(prompt.earliestEndTime == minutes(15))
        #expect(prompt.latestEndTime == hours(10))
    }

    @Test func withNoFrameHistoryTheSuggestedEndUsesThisMatchsOwnAverage() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        try app.award(id, to: asher, at: minutes(10))
        try app.award(id, to: callum, at: minutes(40))
        try app.award(id, to: asher, at: minutes(60))

        let prompt = try #require(try app.flag(at: hours(10)).first)

        // Asher's frames here took 10 and 20 minutes: 15 on average after the last frame at 60.
        #expect(prompt.suggestedEndTime == minutes(75))
    }

    // MARK: ResolveStaleMatch

    @Test func resumeKeepsTheMatchLiveAndResetsTheIdleTime() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        clock.now = minutes(20)
        try app.commands.pauseMatch(id)
        _ = try app.flag(at: hours(8))

        try app.stale.resolveStaleMatch(id, .resume)

        #expect(app.readModel.liveMatches.map(\.isPaused) == [false])
        #expect(try app.flag(at: hours(9)).isEmpty)
    }

    @Test func endAtAChosenTimeFinishesThereWithTheLengthUpToIt() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        try app.award(id, to: callum, at: minutes(20))
        _ = try app.flag(at: hours(8))

        try app.stale.resolveStaleMatch(id, .endAt(minutes(50)))

        let finished = try #require(try app.finished(id))
        #expect(finished.endedAt == minutes(50))
        #expect(finished.length.seconds == 50 * 60)
        #expect(app.readModel.liveMatches.isEmpty)
    }

    @Test func anEndTimeBeforeTheLastActionOrAfterNowIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        try app.award(id, to: callum, at: minutes(20))
        _ = try app.flag(at: hours(8))

        #expect(throws: StaleMatchError.endTimeOutOfBounds) { try app.stale.resolveStaleMatch(id, .endAt(minutes(19))) }
        #expect(throws: StaleMatchError.endTimeOutOfBounds) { try app.stale.resolveStaleMatch(id, .endAt(hours(9))) }
        #expect(try app.finished(id) == nil)
    }

    @Test func endCappedFinishesAtTheLastActionWithTheCappedLength() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        try app.award(id, to: callum, at: minutes(20))
        _ = try app.flag(at: hours(30))

        try app.stale.resolveStaleMatch(id, .endCapped)

        let finished = try #require(try app.finished(id))
        #expect(finished.length.seconds == 3 * 3600)
        #expect(finished.endedAt == minutes(20))
    }

    @Test func endingARaceShortOfItsTargetAsksFirstThenFinishesAnyway() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, style: .raceTo(3), at: minutes(0))
        try app.award(id, to: callum, at: minutes(20))
        _ = try app.flag(at: hours(8))

        #expect(throws: MatchCommandError.finishShortOfTarget) { try app.stale.resolveStaleMatch(id, .endCapped) }
        try app.stale.resolveStaleMatch(id, .endCapped, anyway: true)

        #expect(try app.finished(id)?.shortOfTarget == true)
    }

    @Test func abandonAndCancelEndTheMatch() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let abandoned = try app.start(callum, asher, at: minutes(0))
        let cancelled = try app.start(dev, asher, at: minutes(1))
        _ = try app.flag(at: hours(8))

        try app.stale.resolveStaleMatch(abandoned, .abandon)
        try app.stale.resolveStaleMatch(cancelled, .cancel)

        #expect(try app.events(abandoned).contains { if case .matchAbandoned = $0 { true } else { false } })
        #expect(try app.events(cancelled).contains { if case .matchCancelled = $0 { true } else { false } })
        #expect(app.readModel.liveMatches.isEmpty)
    }

    @Test func aMatchPlayedSinceItWasFlaggedIsNoLongerStale() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, at: minutes(0))
        _ = try app.flag(at: hours(8))
        try app.award(id, to: asher, at: hours(8) + 60)  // from the lock screen, say

        #expect(throws: StaleMatchError.noLongerStale) { try app.stale.resolveStaleMatch(id, .abandon) }
    }

    // MARK: The prompt's queue

    @Test func theQueueAsksAboutEachMatchInTurnAndSkipsOnesNoLongerStale() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let first = try app.start(callum, asher, at: minutes(0))
        let second = try app.start(dev, asher, at: minutes(1))
        let third = try app.start(callum, dev, at: minutes(2))
        clock.now = hours(8)
        let queue = StaleMatchQueue(commands: app.stale)
        try queue.flag()
        #expect(queue.current?.id == first)

        try queue.resolve(.abandon)
        #expect(queue.current?.id == second)

        // The second is ended elsewhere (its live screen) before it's answered: skipped quietly.
        try app.commands.cancelMatch(second)
        try queue.resolve(.resume)
        #expect(queue.current?.id == third)

        try queue.resolve(.resume)
        #expect(queue.current == nil)
        #expect(app.readModel.liveMatches.map(\.id) == [third])
    }

    @Test func aRefusedChoiceKeepsTheMatchInTheQueue() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let app = try App(url: url, clock: clock)
        let id = try app.start(callum, asher, style: .raceTo(3), at: minutes(0))
        clock.now = hours(8)
        let queue = StaleMatchQueue(commands: app.stale)
        try queue.flag()

        #expect(throws: MatchCommandError.finishShortOfTarget) { try queue.resolve(.endCapped) }
        #expect(queue.current?.id == id)
        try queue.resolve(.endCapped, anyway: true)
        #expect(queue.current == nil)
    }
}
