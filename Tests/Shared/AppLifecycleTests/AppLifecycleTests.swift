import EventDispatch
import Foundation
import iOSAdapters
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import SQLiteSupport
import Testing

// The lifecycle adapter driving AutoPauseLiveMatches on launch (S27, ADR-0004), outside-in: real
// UserDefaults (a scratch suite) and a real SQLite file. A new `Process` over both is a relaunch.

private let callum = UUID()
private let asher = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

@MainActor
private final class Players: MatchPlayerDirectory {
    let all = [MatchPlayer(id: callum, name: "Callum", colour: "blue"), MatchPlayer(id: asher, name: "Asher", colour: "orange")]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

private final class Clock: @unchecked Sendable {
    var now = t0
}

/// One app process: the launch sequence as the composition root runs it, then the live list.
@MainActor
private struct Process {
    let lifecycle: AppLifecycle
    let store: SQLiteMatchEventStore
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases

    init(url: URL, defaults: UserDefaults, clock: Clock, afterAutoPause: [@MainActor () throws -> Void] = []) throws {
        let db = try SQLiteDatabase(url: url)
        store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = Players()
        readModel = LiveMatchesProjection(players: players)
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)),
            players: players, readModel: readModel, dispatcher: EventDispatcher(), now: { clock.now })
        lifecycle = AppLifecycle(defaults: defaults, now: { clock.now })
        try AppLaunchSequence(lifecycle: lifecycle, matches: commands, afterAutoPause: afterAutoPause).run()
        try commands.loadLiveMatches()
    }

    func startInPlay(clock: Clock, at: Date) throws -> MatchID {
        clock.now = at
        let id = try commands.startMatch(MatchSetup(players: [callum, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        try commands.chooseBreaker(id, player: callum)
        return id
    }

    func autoPausedAt(_ id: MatchID) throws -> Date? {
        try store.readStream(id.uuidString).compactMap {
            if case .matchAutoPaused(let e) = $0.event { e.at } else { nil }
        }.last
    }
}

@MainActor
@Suite struct AppLifecycleTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "lifecycle-\(UUID().uuidString).sqlite")
    let suite = "lifecycle-tests-\(UUID().uuidString)"
    fileprivate let clock = Clock()

    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: url)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func theFirstLaunchHasNoPreviousSession() {
        defer { cleanUp() }
        #expect(AppLifecycle(defaults: defaults).beginSession() == .none)
    }

    @Test func goingToTheBackgroundAndReturningLeavesLiveMatchesRunning() throws {
        defer { cleanUp() }
        let app = try Process(url: url, defaults: defaults, clock: clock)
        let id = try app.startInPlay(clock: clock, at: minutes(0))

        clock.now = minutes(5)
        app.lifecycle.didEnterBackground()
        clock.now = minutes(40)
        app.lifecycle.didBecomeActive()

        #expect(try app.autoPausedAt(id) == nil)
        #expect(app.readModel.liveMatches.map(\.isPaused) == [false])
        #expect(abs((app.readModel.liveMatchScreen(id)?.matchTimer.elapsed(at: clock.now) ?? 0) - 40 * 60) < 0.001)
    }

    @Test func aKillInTheBackgroundThenARelaunchPausesAtTheBackgroundTime() throws {
        defer { cleanUp() }
        let id: MatchID
        do {
            let app = try Process(url: url, defaults: defaults, clock: clock)
            id = try app.startInPlay(clock: clock, at: minutes(0))
            clock.now = minutes(12)
            app.lifecycle.didEnterBackground()
        }  // killed while suspended

        clock.now = minutes(200)
        let relaunched = try Process(url: url, defaults: defaults, clock: clock)

        #expect(try relaunched.autoPausedAt(id) == minutes(12))
        #expect(relaunched.readModel.liveMatches.map(\.isPaused) == [true])
    }

    @Test func aLockScreenActionAfterBackgroundingThenAKillPausesAtThatAction() throws {
        defer { cleanUp() }
        let id: MatchID
        do {
            let app = try Process(url: url, defaults: defaults, clock: clock)
            id = try app.startInPlay(clock: clock, at: minutes(0))
            clock.now = minutes(12)
            app.lifecycle.didEnterBackground()
            clock.now = minutes(18)
            try app.commands.awardFrame(id, to: asher)  // from the lock screen
        }

        clock.now = minutes(200)
        let relaunched = try Process(url: url, defaults: defaults, clock: clock)

        #expect(try relaunched.autoPausedAt(id) == minutes(18))
    }

    @Test func aKillWhileOnScreenPausesAtTheLastAction() throws {
        defer { cleanUp() }
        let id: MatchID
        do {
            let app = try Process(url: url, defaults: defaults, clock: clock)
            id = try app.startInPlay(clock: clock, at: minutes(0))
            clock.now = minutes(3)
            app.lifecycle.didEnterBackground()
            clock.now = minutes(9)
            app.lifecycle.didBecomeActive()  // back on screen: the background time is cleared
            clock.now = minutes(15)
            try app.commands.awardFrame(id, to: callum)
        }  // crashed on screen

        clock.now = minutes(200)
        let relaunched = try Process(url: url, defaults: defaults, clock: clock)

        #expect(try relaunched.autoPausedAt(id) == minutes(15))
    }

    @Test func autoPauseRunsBeforeTheChecksThatFollowIt() throws {
        defer { cleanUp() }
        let id: MatchID
        do {
            let app = try Process(url: url, defaults: defaults, clock: clock)
            id = try app.startInPlay(clock: clock, at: minutes(0))
            clock.now = minutes(30)
            app.lifecycle.didEnterBackground()
        }

        clock.now = minutes(8 * 60)
        var seenByStaleCheck: [Bool] = []
        let store = try SQLiteMatchEventStore(db: SQLiteDatabase(url: url), originDevice: UUID())
        _ = try Process(url: url, defaults: defaults, clock: clock, afterAutoPause: [{
            let match = try EventSourcedMatchRepository(store: store).getById(id)
            seenByStaleCheck.append(match?.isPaused == true)
        }])

        #expect(seenByStaleCheck == [true])
    }
}
