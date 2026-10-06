import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import SQLiteSupport
import Testing

// AutoPauseLiveMatches (S27, ADR-0004, ADR-0005), outside-in over a real SQLite database. The kill and
// the background time come in as the use case's input, as the lifecycle adapter supplies them on launch;
// a lock-screen action is the same AwardFrame use case the lock-screen buttons will call (S47).

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

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

private final class Clock: @unchecked Sendable {
    var now = t0
}

/// One process's Matches composition. A new `App` over the same file is a relaunch.
@MainActor
private struct App {
    let store: SQLiteMatchEventStore
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases

    init(url: URL, clock: Clock) throws {
        let db = try SQLiteDatabase(url: url)
        store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = Players()
        readModel = LiveMatchesProjection(players: players)
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)),
            players: players, readModel: readModel, dispatcher: EventDispatcher(), now: { clock.now })
    }

    /// Starts a match with a breaker chosen at `at`, so it is in play.
    func startInPlay(_ a: UUID, _ b: UUID, clock: Clock, at: Date) throws -> MatchID {
        clock.now = at
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        try commands.chooseBreaker(id, player: a)
        return id
    }

    /// When the stored stream says the match was auto-paused, if it was.
    func autoPausedAt(_ id: MatchID) throws -> Date? {
        try store.readStream(id.uuidString).compactMap {
            if case .matchAutoPaused(let e) = $0.event { e.at } else { nil }
        }.last
    }
}

@MainActor
@Suite struct AutoPauseLiveMatchesTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "autopause-\(UUID().uuidString).sqlite")
    fileprivate let clock = Clock()

    private func relaunch(at: Date) throws -> App {
        clock.now = at
        return try App(url: url, clock: clock)
    }

    @Test func aKillInTheBackgroundPausesEachRunningMatchAtTheBackgroundTime() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let first: MatchID, second: MatchID
        do {
            let app = try App(url: url, clock: clock)
            first = try app.startInPlay(callum, asher, clock: clock, at: minutes(0))
            second = try app.startInPlay(dev, asher, clock: clock, at: minutes(3))
            clock.now = minutes(10)
            try app.commands.awardFrame(first, to: callum)
        }

        let app = try relaunch(at: minutes(300))
        let paused = try app.commands.autoPauseLiveMatches(lastBackgroundAt: minutes(20))
        try app.commands.loadLiveMatches()

        #expect(Set(paused) == [first, second])
        #expect(try app.autoPausedAt(first) == minutes(20))
        #expect(try app.autoPausedAt(second) == minutes(20))
        #expect(app.readModel.liveMatches.map(\.isPaused) == [true, true])
        // The timers stopped at the background time, not at the relaunch.
        #expect(abs((app.readModel.liveMatchScreen(first)?.matchTimer.elapsed(at: clock.now) ?? 0) - 20 * 60) < 0.001)
    }

    @Test func aLockScreenActionAfterBackgroundingMovesThePauseToThatAction() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let scored: MatchID, untouched: MatchID
        do {
            let app = try App(url: url, clock: clock)
            scored = try app.startInPlay(callum, asher, clock: clock, at: minutes(0))
            untouched = try app.startInPlay(dev, asher, clock: clock, at: minutes(1))
            // Backgrounded at 20; a frame is scored from the lock screen at 25; then killed.
            clock.now = minutes(25)
            try app.commands.awardFrame(scored, to: asher)
        }

        let app = try relaunch(at: minutes(120))
        try app.commands.autoPauseLiveMatches(lastBackgroundAt: minutes(20))

        #expect(try app.autoPausedAt(scored) == minutes(25))
        #expect(try app.autoPausedAt(untouched) == minutes(20))
    }

    @Test func aKillWhileOnScreenPausesEachMatchAtItsLastAction() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let first: MatchID, second: MatchID
        do {
            let app = try App(url: url, clock: clock)
            first = try app.startInPlay(callum, asher, clock: clock, at: minutes(0))
            second = try app.startInPlay(dev, asher, clock: clock, at: minutes(2))
            clock.now = minutes(14)
            try app.commands.awardFrame(second, to: dev)
        }

        let app = try relaunch(at: minutes(90))
        try app.commands.autoPauseLiveMatches(lastBackgroundAt: nil)
        try app.commands.loadLiveMatches()

        #expect(try app.autoPausedAt(first) == minutes(0))
        #expect(try app.autoPausedAt(second) == minutes(14))
        #expect(app.readModel.liveMatches.map(\.isPaused) == [true, true])
    }

    @Test func anAlreadyPausedMatchIsLeftUntouched() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let paused: MatchID, running: MatchID
        do {
            let app = try App(url: url, clock: clock)
            paused = try app.startInPlay(callum, asher, clock: clock, at: minutes(0))
            running = try app.startInPlay(dev, asher, clock: clock, at: minutes(1))
            clock.now = minutes(5)
            try app.commands.pauseMatch(paused)
        }

        let app = try relaunch(at: minutes(60))
        let before = try app.store.readStream(paused.uuidString).count
        let result = try app.commands.autoPauseLiveMatches(lastBackgroundAt: minutes(30))

        #expect(result == [running])
        #expect(try app.store.readStream(paused.uuidString).count == before)
        #expect(try app.autoPausedAt(paused) == nil)
        #expect(try app.autoPausedAt(running) == minutes(30))
    }

    @Test func aMatchStillWaitingForItsBreakerIsPausedToo() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let id: MatchID
        do {
            let app = try App(url: url, clock: clock)
            clock.now = minutes(0)
            id = try app.commands.startMatch(MatchSetup(players: [callum, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        }

        let app = try relaunch(at: minutes(60))
        try app.commands.autoPauseLiveMatches(lastBackgroundAt: minutes(7))

        #expect(try app.autoPausedAt(id) == minutes(7))
    }
}
