import EventDispatch
import Foundation
import MatchesApplication
import MatchesInfrastructure
import SQLiteSupport
import Testing

// `WarnLongFrame` (spec 015 / 019, S37), outside-in: real use cases over in-memory SQLite, the policy
// subscribed as the composition root subscribes it, and the in-memory `NotificationScheduler`.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()

@MainActor
private final class LongFramePlayers: MatchPlayerDirectory {
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
private struct LongFrameStack {
    let clock: StepClock
    let scheduler: InMemoryNotificationScheduler
    let policy: WarnLongFrame
    let commands: MatchUseCases

    init(db: SQLiteDatabase, clock: StepClock = StepClock()) throws {
        self.clock = clock
        let scheduler = InMemoryNotificationScheduler()
        self.scheduler = scheduler
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let players = LongFramePlayers()
        let readModel = LiveMatchesProjection(players: players)
        let dispatcher = EventDispatcher()
        commands = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store),
            settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)), players: players,
            readModel: readModel, dispatcher: dispatcher, now: { clock.now })
        policy = WarnLongFrame(matches: readModel, scheduler: scheduler)
        policy.subscribe(to: dispatcher)
        try commands.loadLiveMatches()
    }

    /// Starts a match and chooses the breaker straight away: frame 1 is in play from `clock.now`.
    func start(_ a: UUID, _ b: UUID, style: MatchStyle = .mostFramesWins) throws -> MatchID {
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: style, breakRule: .alternate))
        try commands.chooseBreaker(id, player: a)
        return id
    }

    func pending(_ match: MatchID) -> [ScheduledNotification] {
        let ids = Set(WarnLongFrame.ids(for: match))
        return scheduler.queue.filter { ids.contains($0.id) }
    }

    /// Minutes from `origin` to each pending warning of `match`.
    func minutes(_ match: MatchID, from origin: Date) -> [Double] {
        pending(match).map { $0.fireAt.timeIntervalSince(origin) / 60 }
    }
}

private let batch: [Double] = (0..<WarnLongFrame.batchSize).map { 30 + Double($0) * 10 }

@MainActor
@Suite("WarnLongFrame")
struct LongFrameWarningTests {
    @Test func inPlaySchedulesAt30MinutesThenEvery10() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let t0 = stack.clock.now
        let match = try stack.start(callum, asher)

        #expect(stack.minutes(match, from: t0) == batch)
        let first = try #require(stack.pending(match).first)
        #expect(first.title == "Long-running frame")
        #expect(first.body == "Frame 1, Callum v Asher: 30 minutes.")
    }

    @Test func nothingIsScheduledWhileAwaitingTheBreaker() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.commands.startMatch(
            MatchSetup(players: [callum, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        #expect(stack.pending(match).isEmpty)
    }

    @Test func choosingTheBreakerLateCountsFromTheFrameStart() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let t0 = stack.clock.now
        let match = try stack.commands.startMatch(
            MatchSetup(players: [callum, asher], game: .pool, style: .mostFramesWins, breakRule: .alternate))
        stack.clock.advance(minutes: 4)
        try stack.commands.chooseBreaker(match, player: callum)
        // Frame 1's timer started with the match.
        #expect(stack.minutes(match, from: t0) == batch)
    }

    @Test func frameWonRestartsTheSchedule() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        stack.clock.advance(minutes: 35)
        try stack.commands.awardFrame(match, to: callum)

        let t1 = stack.clock.now
        #expect(stack.minutes(match, from: t1) == batch)
        #expect(stack.pending(match).first?.body == "Frame 2, Callum v Asher: 30 minutes.")
    }

    @Test func pauseCancelsAndResumeCarriesOnFromThePausedFrameTime() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        stack.clock.advance(minutes: 10)
        try stack.commands.pauseMatch(match)
        #expect(stack.pending(match).isEmpty)

        stack.clock.advance(minutes: 60)  // paused time does not count
        try stack.commands.resumeMatch(match)
        let resumed = stack.clock.now
        #expect(stack.minutes(match, from: resumed) == batch.map { $0 - 10 })
    }

    @Test func resumingPast30MinutesWarnsAtTheNext10MinuteMark() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        stack.clock.advance(minutes: 45)
        try stack.commands.pauseMatch(match)
        stack.clock.advance(minutes: 5)
        try stack.commands.resumeMatch(match)

        let resumed = stack.clock.now
        let minutes = stack.minutes(match, from: resumed)
        #expect(minutes.first == 5)  // 50 min of frame time
        #expect(minutes == (0..<WarnLongFrame.batchSize).map { 5 + Double($0) * 10 })
        #expect(stack.pending(match).first?.body == "Frame 1, Callum v Asher: 50 minutes.")
    }

    @Test func autoPauseCancels() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        stack.clock.advance(minutes: 5)
        try stack.commands.autoPauseLiveMatches(lastBackgroundAt: stack.clock.now)
        #expect(stack.pending(match).isEmpty)
    }

    @Test(arguments: ["finish", "abandon", "cancel"])
    func endingTheMatchCancels(_ ending: String) throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        stack.clock.advance(minutes: 5)
        switch ending {
        case "finish": try stack.commands.finishMatch(match)
        case "abandon": try stack.commands.abandonMatch(match)
        default: try stack.commands.cancelMatch(match)
        }
        #expect(stack.pending(match).isEmpty)
    }

    @Test func deletingTheMatchCancels() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher)
        try stack.commands.abandonMatch(match)
        // Anything left over for the match (e.g. from an earlier run) goes with the delete.
        stack.scheduler.schedule(WarnLongFrame.ids(for: match).map {
            ScheduledNotification(id: $0, title: "", body: "", fireAt: stack.clock.now)
        })
        try stack.commands.deleteMatch(match)
        #expect(stack.pending(match).isEmpty)
    }

    @Test func targetReachedCancelsAndUndoReschedules() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let match = try stack.start(callum, asher, style: .raceTo(1))
        stack.clock.advance(minutes: 20)
        try stack.commands.awardFrame(match, to: callum)
        #expect(stack.pending(match).isEmpty)  // waiting on Finish?

        stack.clock.advance(minutes: 1)
        try stack.commands.removeFrame(match, from: callum)  // Undo Last Frame
        #expect(!stack.pending(match).isEmpty)
    }

    @Test func otherMatchesAreUnaffected() throws {
        let stack = try LongFrameStack(db: .inMemory())
        let first = try stack.start(callum, asher)
        stack.clock.advance(minutes: 2)
        let t1 = stack.clock.now
        let second = try stack.start(dev, asher)
        let secondBefore = stack.pending(second)

        stack.clock.advance(minutes: 8)
        try stack.commands.awardFrame(first, to: callum)
        #expect(stack.pending(second) == secondBefore)
        try stack.commands.pauseMatch(first)
        #expect(stack.pending(second) == secondBefore)
        try stack.commands.cancelMatch(first)
        #expect(stack.pending(first).isEmpty)
        #expect(stack.minutes(second, from: t1) == batch)
        #expect(stack.scheduler.queue.count == WarnLongFrame.batchSize)
    }

    @Test func rescheduleAllRestoresWarningsAfterARelaunch() throws {
        let db = try SQLiteDatabase.inMemory()
        let clock = StepClock()
        let t0 = clock.now
        let before = try LongFrameStack(db: db, clock: clock)
        let match = try before.start(callum, asher)

        clock.advance(minutes: 12)
        let after = try LongFrameStack(db: db, clock: clock)  // fresh scheduler: nothing pending
        #expect(after.pending(match).isEmpty)
        after.policy.rescheduleAll()
        #expect(after.minutes(match, from: t0) == batch)
    }
}
