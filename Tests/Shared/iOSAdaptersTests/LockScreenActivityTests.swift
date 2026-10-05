import EventDispatch
import Foundation
import iOSAdapters
import LiveActivityShared
import MatchesApplication
import MatchesInfrastructure
import SQLiteSupport
import Testing

// Live Activity adapter (spec 018), outside-in: the real Matches composition over in-memory SQLite,
// wired as the composition root wires it. The only stand-ins are the Players supplier port and the
// ActivityKit presenter, which records what it was asked to show.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()

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

@MainActor
private final class RecordingPresenter: LockScreenPresenter {
    enum Call: Equatable {
        case start(MatchActivityAttributes.ContentState)
        case update(MatchActivityAttributes.ContentState)
        case end
    }

    var calls: [Call] = []
    var refuseStart = false

    func start(_ content: MatchActivityAttributes.ContentState) -> Bool {
        if refuseStart { return false }
        calls.append(.start(content))
        return true
    }

    func update(_ content: MatchActivityAttributes.ContentState) { calls.append(.update(content)) }
    func end() { calls.append(.end) }

    var shown: MatchActivityAttributes.ContentState? {
        switch calls.last {
        case .start(let c)?, .update(let c)?: c
        default: nil
        }
    }
}

private final class StepClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}

@MainActor
private struct App {
    let clock = StepClock()
    let commands: MatchUseCases
    let presenter = RecordingPresenter()
    let activity: LockScreenActivity
    let lockScreen: LockScreenCommands

    init() throws {
        let db = try SQLiteDatabase.inMemory()
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = Players()
        let readModel = LiveMatchesProjection(players: players)
        let dispatcher = EventDispatcher()
        let clock = clock
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)), players: players,
            readModel: readModel, dispatcher: dispatcher, now: { clock.now })
        try commands.loadLiveMatches()
        activity = LockScreenActivity(state: readModel, presenter: presenter)
        activity.subscribe(to: dispatcher)
        activity.refresh()
        lockScreen = LockScreenCommands(commands: commands)
    }

    func start(_ a: UUID, _ b: UUID) throws -> MatchID {
        clock.now += 60
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        try commands.chooseBreaker(id, player: a)
        return id
    }
}

@MainActor
@Suite("Live Activity adapter", .serialized)
struct LockScreenActivityTests {
    @Test func theFirstMatchStartedShowsAnActivity() throws {
        let app = try App()
        #expect(app.presenter.calls == [.end])  // launch: nothing live, any leftover activity goes

        let id = try app.start(callum, asher)
        guard case .start(let content)? = app.presenter.calls.dropFirst().first else {
            Issue.record("expected a start, got \(app.presenter.calls)")
            return
        }
        #expect(content.matchID == id)
        #expect(content.sides.map(\.name) == ["Callum", "Asher"])
        #expect(app.presenter.calls.filter { if case .start = $0 { true } else { false } }.count == 1)
    }

    @Test func aSecondLiveMatchDoesNotReplaceIt() throws {
        let app = try App()
        let first = try app.start(callum, asher)
        let callsBefore = app.presenter.calls.count
        let second = try app.start(dev, asher)
        try app.commands.awardFrame(second, to: dev)
        try app.commands.pauseMatch(second)
        #expect(app.presenter.calls.count == callsBefore)  // other matches' events are ignored
        #expect(app.presenter.shown?.matchID == first)
    }

    @Test func theShownMatchsEventsMapToTheActivity() throws {
        let app = try App()
        let id = try app.start(callum, asher)
        #expect(app.presenter.shown?.sides.map(\.isBreaker) == [true, false])

        app.clock.now += 300
        try app.commands.awardFrame(id, to: callum)
        let afterFrame = try #require(app.presenter.shown)
        #expect(afterFrame.sides.map(\.frames) == [1, 0])
        #expect(afterFrame.sides.map(\.isBreaker) == [false, true])
        #expect(afterFrame.frameTimerStart == app.clock.now)  // new frame, timer from zero
        #expect(!afterFrame.isPaused && afterFrame.canAward && afterFrame.canPause)

        app.clock.now += 120
        try app.commands.pauseMatch(id)
        let paused = try #require(app.presenter.shown)
        #expect(paused.isPaused && !paused.canAward && paused.canResume)
        #expect(abs(paused.pausedAt!.timeIntervalSince(paused.frameTimerStart) - 120) < 0.001)

        try app.commands.resumeMatch(id)
        #expect(app.presenter.shown?.isPaused == false)

        try app.commands.removeFrame(id, from: callum)
        #expect(app.presenter.shown?.sides.map(\.frames) == [0, 0])
        #expect(app.presenter.shown?.sides.map(\.isBreaker) == [true, false])
    }

    @Test func endingTheShownMatchHandsOverOrEnds() throws {
        let app = try App()
        let first = try app.start(callum, asher)
        let second = try app.start(dev, asher)

        try app.commands.finishMatch(first)
        guard case .update(let handedOver)? = app.presenter.calls.last else {
            Issue.record("expected a hand-over update, got \(String(describing: app.presenter.calls.last))")
            return
        }
        #expect(handedOver.matchID == second)
        #expect(handedOver.sides.map(\.name) == ["Dev", "Asher"])

        try app.commands.abandonMatch(second)
        #expect(app.presenter.calls.last == .end)
    }

    @Test func aRefusedStartIsRetriedOnTheNextRefresh() throws {
        let app = try App()
        app.presenter.refuseStart = true
        let id = try app.start(callum, asher)
        #expect(app.presenter.shown == nil)
        app.presenter.refuseStart = false
        app.activity.refresh()  // e.g. back in the foreground
        #expect(app.presenter.shown?.matchID == id)
    }

    @Test func theLockScreenButtonsInvokeTheUseCases() throws {
        let app = try App()
        let id = try app.start(callum, asher)
        MatchActivityCommandRoute.commands = app.lockScreen
        defer { MatchActivityCommandRoute.commands = nil }
        let buttons = try MatchActivityCommandRoute.resolve()

        try buttons.awardFrame(match: id, to: asher)
        #expect(app.presenter.shown?.sides.map(\.frames) == [0, 1])
        try buttons.pauseMatch(id)
        #expect(app.presenter.shown?.isPaused == true)
        #expect(throws: MatchCommandError.self) { try buttons.awardFrame(match: id, to: callum) }
        try buttons.resumeMatch(id)
        #expect(app.presenter.shown?.isPaused == false)
        try buttons.awardFrame(match: id, to: callum)
        #expect(app.presenter.shown?.sides.map(\.frames) == [1, 1])
    }

    @Test func buttonsFailCleanlyWhenTheAppHasNotInstalledThem() {
        MatchActivityCommandRoute.commands = nil
        #expect(throws: MatchActivityCommandError.self) { try MatchActivityCommandRoute.resolve() }
    }
}
