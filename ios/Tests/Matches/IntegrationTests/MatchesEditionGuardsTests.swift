import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import SQLiteSupport
import Testing
import UpgradePublished

// Matches edition guards (spec 025, ADR-0010, ADR-0011), outside-in: the real use cases, projection
// and event store over in-memory SQLite. The edition is Upgrade's `FixedEdition` test double; the
// Players supplier port and the Live Activity port are the only other stand-ins.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
/// Shares Callum's colour (S46).
private let eve = UUID()
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

@MainActor
private final class Players: MatchPlayerDirectory {
    let all = [
        MatchPlayer(id: callum, name: "Callum", colour: "blue"),
        MatchPlayer(id: asher, name: "Asher", colour: "orange"),
        MatchPlayer(id: dev, name: "Dev", colour: "green"),
        MatchPlayer(id: eve, name: "Eve", colour: "blue"),
    ]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

private final class Clock: @unchecked Sendable {
    var now = t0
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

@MainActor
private final class RecordingLiveActivity: LiveActivityPort {
    var removed = 0
    func removeLiveActivity() { removed += 1 }
}

@MainActor
private struct Stack {
    let clock = Clock()
    let edition: FixedEdition
    let repository: EventSourcedMatchRepository
    let readModel: LiveMatchesProjection
    let commands: MatchUseCases
    let dispatcher = EventDispatcher()

    init(_ status: EditionStatus) throws {
        let db = try SQLiteDatabase.inMemory()
        edition = FixedEdition(status)
        repository = EventSourcedMatchRepository(store: try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db)))
        let players = Players()
        readModel = LiveMatchesProjection(players: players, edition: edition)
        readModel.subscribeToEdition(dispatcher)
        let clock = clock
        commands = MatchUseCases(
            repository: repository, settings: try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db)),
            players: players, readModel: readModel, dispatcher: dispatcher, edition: edition, now: { clock.now })
    }

    /// The free limits the guards read: never hard-coded in these tests either.
    var limits: FreeLimits { FreeLimits.standard }

    @discardableResult
    func start(_ a: UUID = callum, _ b: UUID = asher, style: MatchesApplication.MatchStyle = .mostFramesWins,
               breakRule: MatchesApplication.BreakRule = .alternate, breaker: Bool = true) throws -> MatchID {
        clock.advance(minutes: 1)
        let id = try commands.startMatch(MatchSetup(players: [a, b], game: .pool, style: style, breakRule: breakRule))
        if breaker { try commands.chooseBreaker(id, player: a) }
        return id
    }

    /// Starts and finishes a most-frames-wins match 1–0, one after the other.
    func ended() throws -> MatchID {
        let id = try start()
        clock.advance(minutes: 5)
        try commands.awardFrame(id, to: callum)
        try commands.finishMatch(id)
        return id
    }

    func live() throws -> Int { try repository.findLive().count }
}

// MARK: - StartMatch

@MainActor
@Suite("Edition guards: StartMatch")
struct StartMatchEditionTests {
    @Test func freeRefusesASecondLiveMatchWhateverTheStoredLimit() throws {
        let stack = try Stack(.free)
        try stack.start()
        #expect(throws: UpgradeRequired(.severalLiveMatches)) { try stack.start(dev, eve) }
        #expect(try stack.live() == stack.limits.liveMatches)
    }

    @Test func unlockedUsesTheStoredLimit() throws {
        let stack = try Stack(.unlocked)
        try stack.start()
        try stack.start(dev, eve)
        #expect(try stack.live() == 2)
    }

    @Test(arguments: [MatchesApplication.MatchStyle.raceTo(3), .bestOf(5)])
    func freeRefusesRaceToAndBestOf(_ style: MatchesApplication.MatchStyle) throws {
        let stack = try Stack(.free)
        #expect(throws: UpgradeRequired(.raceTo)) { try stack.start(style: style) }
        #expect(try stack.live() == 0)
    }

    @Test func freeRefusesSets() throws {
        let stack = try Stack(.free)
        #expect(throws: UpgradeRequired(.sets)) { try stack.start(style: .sets(sets: 2, frames: 3)) }
        #expect(try stack.live() == 0)
    }

    @Test func freeRefusesWinnerBreaks() throws {
        let stack = try Stack(.free)
        #expect(throws: UpgradeRequired(.winnerBreaks)) { try stack.start(breakRule: .winnerBreaks) }
        #expect(try stack.live() == 0)
    }

    @Test func freeStartsMostFramesWinsWithAlternateBreaks() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        #expect(stack.readModel.liveMatchScreen(id)?.style == .mostFramesWins)
    }

    @Test func unlockedStartsEveryStyleAndBreakRule() throws {
        let stack = try Stack(.unlocked)
        try stack.start(style: .sets(sets: 2, frames: 3), breakRule: .winnerBreaks)
        #expect(try stack.live() == 1)
    }
}

// MARK: - Pause and resume

@MainActor
@Suite("Edition guards: PauseMatch / ResumeMatch")
struct PauseEditionTests {
    @Test func freeRefusesAPauseByHand() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        #expect(throws: UpgradeRequired(.manualPause)) { try stack.commands.pauseMatch(id) }
        #expect(try stack.repository.getById(id)?.status == .inPlay)
    }

    @Test func freeRefusesResumingAPauseByHand() throws {
        let stack = try Stack(.unlocked)
        let id = try stack.start()
        try stack.commands.pauseMatch(id)
        stack.edition.status = .free  // revoked while paused (S51)

        #expect(throws: UpgradeRequired(.manualPause)) { try stack.commands.resumeMatch(id) }
        let match = try #require(try stack.repository.getById(id))
        #expect(match.status == .paused)
        #expect(match.pauseKind == .byHand)
        #expect(stack.readModel.liveMatchScreen(id)?.controls.resumeOffersUpgrade == true)
    }

    @Test func freeAllowsAutoPauseAfterAKillAndItsResume() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        stack.clock.advance(minutes: 10)
        #expect(try stack.commands.autoPauseLiveMatches(lastBackgroundAt: stack.clock.now) == [id])
        #expect(try stack.repository.getById(id)?.pauseKind == .automatic)
        #expect(stack.readModel.liveMatchScreen(id)?.controls.resumeOffersUpgrade == false)

        stack.clock.advance(minutes: 30)
        try stack.commands.resumeMatch(id)
        #expect(try stack.repository.getById(id)?.status == .inPlay)
    }

    @Test func unlockedPausesAndResumesByHand() throws {
        let stack = try Stack(.unlocked)
        let id = try stack.start()
        try stack.commands.pauseMatch(id)
        try stack.commands.resumeMatch(id)
        #expect(try stack.repository.getById(id)?.status == .inPlay)
    }
}

// MARK: - Finish all, temporary colour

@MainActor
@Suite("Edition guards: FinishAllMatches, OverrideMatchColour")
struct PaidMatchActionsTests {
    @Test func finishAllIsPaid() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        #expect(throws: UpgradeRequired(.severalLiveMatches)) { try stack.commands.finishAllMatchesPreview() }
        #expect(throws: UpgradeRequired(.severalLiveMatches)) { try stack.commands.finishAllMatches() }
        #expect(try stack.repository.getById(id)?.status == .inPlay)
    }

    @Test func theTemporaryColourIsNotOfferedOrAllowedWhileFree() throws {
        let stack = try Stack(.free)
        let id = try stack.start(callum, eve, breaker: false)
        #expect(stack.readModel.liveMatchScreen(id)?.coloursClash == false)
        #expect(throws: UpgradeRequired(.colours)) { try stack.commands.overrideMatchColour(id, of: eve, to: "red") }
        // Kept, not shown: the match still has both players' own colours.
        #expect(try stack.repository.getById(id)?.sides.map(\.colour.name) == ["blue", "blue"])
    }
}

// MARK: - Corrections and deletions (newest ended matches)

@MainActor
@Suite("Edition guards: CorrectMatchScore, DeleteMatch")
struct NewestEndedEditionTests {
    /// One more ended match than Free shows; returns them oldest first.
    private func pastTheLimit(_ stack: Stack) throws -> [MatchID] {
        try (0...stack.limits.visibleEndedMatches).map { _ in try stack.ended() }
    }

    @Test func isAmongNewestEndedCountsEndedMatchesNewestFirst() throws {
        let stack = try Stack(.unlocked)
        let ended = try pastTheLimit(stack)
        let n = stack.limits.visibleEndedMatches
        #expect(try !stack.repository.isAmongNewestEnded(ended[0], n))
        #expect(try ended.dropFirst().allSatisfy { try stack.repository.isAmongNewestEnded($0, n) })
        let live = try stack.start()
        #expect(try !stack.repository.isAmongNewestEnded(live, n))
        #expect(try !stack.repository.isAmongNewestEnded(UUID(), n))
        // A deleted match leaves the newest; the next one in line takes its place.
        try stack.commands.deleteMatch(ended[n])
        #expect(try !stack.repository.isAmongNewestEnded(ended[n], n))
        #expect(try stack.repository.isAmongNewestEnded(ended[0], n))
    }

    @Test func freeRefusesCorrectingAMatchBeyondTheNewestAndChangesNothing() throws {
        let stack = try Stack(.free)
        let ended = try pastTheLimit(stack)
        let before = try stack.repository.getById(ended[0])

        #expect(throws: UpgradeRequired(.fullHistory)) {
            try stack.commands.correctMatchScore(ended[0], to: .frames(first: 3, second: 1), confirmed: true)
        }
        #expect(try stack.repository.getById(ended[0]) == before)

        try stack.commands.correctMatchScore(ended[1], to: .frames(first: 3, second: 1), confirmed: true)
        #expect(try stack.repository.getById(ended[1])?.score.firstFrames == 3)
    }

    @Test func freeRefusesDeletingAMatchBeyondTheNewestAndDeletesNothing() throws {
        let stack = try Stack(.free)
        let ended = try pastTheLimit(stack)

        #expect(throws: UpgradeRequired(.fullHistory)) { try stack.commands.deleteMatch(ended[0]) }
        #expect(try stack.repository.getById(ended[0])?.status == .finished)

        try stack.commands.deleteMatch(ended[1])
        #expect(try stack.repository.getById(ended[1])?.status == .deleted)
    }

    @Test func unlockedCorrectsAndDeletesAnyEndedMatch() throws {
        let stack = try Stack(.unlocked)
        let ended = try pastTheLimit(stack)
        try stack.commands.correctMatchScore(ended[0], to: .frames(first: 2, second: 0), confirmed: true)
        try stack.commands.deleteMatch(ended[0])
        #expect(try stack.repository.getById(ended[0])?.status == .deleted)
    }

    @Test func thePlayerRemovalCascadeIsNeverLimited() throws {
        let stack = try Stack(.free)
        let ended = try pastTheLimit(stack)
        DeleteMatchesOnPlayerRemoved(matches: stack.commands).deleteMatches(of: asher)
        for id in ended { #expect(try stack.repository.getById(id)?.status == .deleted) }
    }
}

// MARK: - Reads

@MainActor
@Suite("Edition guards: LiveMatches, LiveMatchScreen, LockScreenState")
struct EditionReadsTests {
    @Test func freeOmitsColoursLocksHeadToHeadAndOffersUpgradeOnPause() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        #expect(stack.readModel.liveMatches.first?.sides.map(\.showsColour) == [false, false])
        let screen = try #require(stack.readModel.liveMatchScreen(id))
        #expect(!screen.showsColours)
        #expect(screen.sides.map(\.colour) == [LiveSide.noColour, LiveSide.noColour])
        #expect(screen.headToHeadLocked)
        #expect(screen.controls.pause && screen.controls.pauseOffersUpgrade)
        #expect(stack.readModel.lockScreenState == nil)
    }

    @Test func unlockedShowsEverything() throws {
        let stack = try Stack(.unlocked)
        let id = try stack.start()
        #expect(stack.readModel.liveMatches.first?.sides.map(\.colour) == ["blue", "orange"])
        let screen = try #require(stack.readModel.liveMatchScreen(id))
        #expect(screen.showsColours && !screen.headToHeadLocked && !screen.controls.pauseOffersUpgrade)
        #expect(stack.readModel.lockScreenState?.matchID == id)
    }

    @Test func unlockingShowsTheColoursAgainWithoutRebuilding() throws {
        let stack = try Stack(.free)
        let id = try stack.start()
        stack.edition.status = .unlocked
        stack.dispatcher.dispatch([AppUnlockedPublished(occurredAt: stack.clock.now)])
        #expect(stack.readModel.liveMatchScreen(id)?.sides.map(\.colour) == ["blue", "orange"])
        #expect(stack.readModel.lockScreenState?.matchID == id)
    }
}

// MARK: - RemoveLiveActivityOnLock

@MainActor
@Suite("Edition guards: RemoveLiveActivityOnLock")
struct RemoveLiveActivityOnLockTests {
    @Test func appLockedRemovesTheLiveActivityAndLeavesLiveMatchesUnchanged() throws {
        let stack = try Stack(.unlocked)
        let liveActivity = RecordingLiveActivity()
        let policy = RemoveLiveActivityOnLock(liveActivity: liveActivity)
        policy.subscribe(to: stack.dispatcher)
        let raceTo = try stack.start(style: .raceTo(5), breakRule: .winnerBreaks)
        try stack.commands.awardFrame(raceTo, to: callum)
        let paused = try stack.start(dev, eve, style: .sets(sets: 2, frames: 3))
        try stack.commands.pauseMatch(paused)
        let before = try stack.repository.findLive()
        #expect(stack.readModel.lockScreenState != nil)

        stack.edition.status = .free
        stack.dispatcher.dispatch([AppLockedPublished(occurredAt: stack.clock.now)])

        #expect(liveActivity.removed == 1)
        #expect(stack.readModel.lockScreenState == nil)
        let after = try stack.repository.findLive()
        #expect(after == before)
        #expect(after.map(\.setup.breakRule) == [.winnerBreaks, .alternate])
        #expect(after.last?.pauseKind == .byHand)
        // They run to the end: scoring and finishing still work.
        try stack.commands.awardFrame(raceTo, to: callum)
        try stack.commands.finishMatch(raceTo, anyway: true)
        withExtendedLifetime(policy) {}
    }
}
