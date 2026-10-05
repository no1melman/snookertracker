import EventDispatch
import Foundation
import MatchesApplication
import MatchesInfrastructure
import SQLiteSupport
import Testing

// `LockScreenState` (spec 009 / 018, S47, ADR-0004), outside-in over real use cases and SQLite.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()

@MainActor
private final class LockScreenPlayers: MatchPlayerDirectory {
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

private final class StepClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

@MainActor
private struct LockScreenStack {
    let clock = StepClock()
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases

    init(db: SQLiteDatabase) throws {
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = LockScreenPlayers()
        readModel = LiveMatchesProjection(players: players)
        let clock = clock
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)), players: players,
            readModel: readModel, dispatcher: EventDispatcher(), now: { clock.now })
        try commands.loadLiveMatches()
    }

    var state: LockScreenState? { (readModel as any LockScreenStateQuery).lockScreenState }

    func start(_ a: UUID, _ b: UUID) throws -> MatchID {
        clock.advance(minutes: 1)
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        try commands.chooseBreaker(id, player: a)
        return id
    }
}

@MainActor
@Suite("LockScreenState")
struct LockScreenStateTests {
    @Test func noLiveMatchShowsNothing() throws {
        let stack = try LockScreenStack(db: .inMemory())
        #expect(stack.state == nil)
    }

    @Test func showsTheOldestLiveMatchWithScoreBreakerAndControls() throws {
        let stack = try LockScreenStack(db: .inMemory())
        let first = try stack.start(callum, asher)
        _ = try stack.start(dev, asher)
        stack.clock.advance(minutes: 5)
        try stack.commands.awardFrame(first, to: callum)

        let state = try #require(stack.state)
        #expect(state.matchID == first)
        #expect(state.sides.map(\.name) == ["Callum", "Asher"])
        #expect(state.sides.map(\.colour) == ["blue", "orange"])
        #expect(state.sides.map(\.frames) == [1, 0])
        // Alternate break: Asher breaks frame 2.
        #expect(state.sides.map(\.isBreaker) == [false, true])
        #expect(!state.isPaused && state.frameTimer.isRunning)
        #expect(state.controls == .init(award: true, pause: true, resume: false))
    }

    @Test func aLaterMatchDoesNotReplaceTheShownOne() throws {
        let stack = try LockScreenStack(db: .inMemory())
        let first = try stack.start(callum, asher)
        let second = try stack.start(dev, asher)
        try stack.commands.awardFrame(second, to: dev)
        #expect(stack.state?.matchID == first)
        #expect(stack.state?.sides.map(\.frames) == [0, 0])
    }

    @Test func pausedStateFreezesTheFrameTimerAndOffersResume() throws {
        let stack = try LockScreenStack(db: .inMemory())
        let id = try stack.start(callum, asher)
        stack.clock.advance(minutes: 3)
        try stack.commands.pauseMatch(id)

        let state = try #require(stack.state)
        #expect(state.isPaused)
        #expect(!state.frameTimer.isRunning)
        #expect(state.frameTimer.accumulated == 180)
        #expect(state.controls == .init(award: false, pause: false, resume: true))
    }

    @Test(arguments: ["finish", "abandon", "cancel"])
    func endingTheShownMatchHandsOverToTheNextOldest(_ ending: String) throws {
        let stack = try LockScreenStack(db: .inMemory())
        let first = try stack.start(callum, asher)
        let second = try stack.start(dev, asher)
        let third = try stack.start(callum, dev)
        try stack.commands.awardFrame(first, to: callum)

        switch ending {
        case "finish": try stack.commands.finishMatch(first)
        case "abandon": try stack.commands.abandonMatch(first)
        default: try stack.commands.cancelMatch(first)
        }
        #expect(stack.state?.matchID == second)

        try stack.commands.cancelMatch(second)
        #expect(stack.state?.matchID == third)
        try stack.commands.cancelMatch(third)
        #expect(stack.state == nil)
    }

    @Test func survivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lock-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let first: MatchID
        do {
            let stack = try LockScreenStack(db: SQLiteDatabase(url: url))
            first = try stack.start(callum, asher)
            _ = try stack.start(dev, asher)
        }
        let relaunched = try LockScreenStack(db: SQLiteDatabase(url: url))
        #expect(relaunched.state?.matchID == first)
    }
}
