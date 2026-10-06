import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import Testing

// Outside-in (S33, ADR-0009): Players' `PlayersMerged` (in its real wire shape) reaches
// `MovePlayerMatches` through the dispatcher; matches are read back from the real SQLite event
// store, and the open-host queries answer over it. The only stand-in is the Players supplier port.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
private let cal = UUID()  // a second record of Callum, folded into him by the merge

@MainActor
private final class MergePlayers: MatchPlayerDirectory {
    let all = [
        MatchPlayer(id: callum, name: "Callum", colour: "blue"),
        MatchPlayer(id: asher, name: "Asher", colour: "orange"),
        MatchPlayer(id: dev, name: "Dev", colour: "green"),
        MatchPlayer(id: cal, name: "Cal", colour: "red"),
    ]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

private final class MergeClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func tick() { now = now.addingTimeInterval(60) }
}

/// Matches and `MovePlayerMatches`, wired as the composition root does.
@MainActor
private struct MergeStack {
    let clock = MergeClock()
    let dispatcher = EventDispatcher()
    let readModel: LiveMatchesProjection
    let matches: MatchUseCases
    let repository: EventSourcedMatchRepository
    let queries: MatchesForPlayers
    let policy: MovePlayerMatches
    var published: [MatchEventPublished] { recorder.events }
    private let recorder = Recorder()

    final class Recorder: @unchecked Sendable { var events: [MatchEventPublished] = [] }

    init() throws {
        let db = try SQLiteDatabase.inMemory()
        let clock = clock
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db))
        settings.changeLiveMatchLimit(100)
        let players = MergePlayers()
        repository = EventSourcedMatchRepository(store: store)
        readModel = LiveMatchesProjection(players: players)
        matches = MatchUseCases(
            repository: repository, settings: settings, players: players,
            readModel: readModel, dispatcher: dispatcher, now: { clock.now })
        queries = MatchesForPlayers(matches: matches)
        policy = MovePlayerMatches(matches: matches, now: { clock.now })
        policy.subscribe(to: dispatcher)
        let recorder = recorder
        dispatcher.subscribe(MatchEventPublished.self) { recorder.events.append($0) }
    }

    @discardableResult
    func start(_ a: UUID, _ b: UUID) throws -> MatchID {
        clock.tick()
        return try matches.startMatch(MatchSetup(players: [a, b], game: .pool, style: .raceTo(3), breakRule: .alternate))
    }

    /// A match won 1–0 by `a`, finished short of its target.
    @discardableResult
    func play(_ a: UUID, _ b: UUID) throws -> MatchID {
        let id = try start(a, b)
        try matches.chooseBreaker(id, player: a)
        try matches.awardFrame(id, to: a)
        try matches.finishMatch(id, anyway: true)
        return id
    }

    /// Players publishes `PlayersMerged` (the payload as `PlayerEventWire` encodes it).
    func merged(keep: UUID, foldIn: UUID) {
        clock.tick()
        let json = #"{"foldedInPlayerId":"\#(foldIn.uuidString)","keptPlayerId":"\#(keep.uuidString)","occurredAt":\#(clock.now.timeIntervalSince1970)}"#
        dispatcher.dispatch([PlayerEventPublished(
            playerId: foldIn, type: "PlayersMerged", schemaVersion: 1, payload: Data(json.utf8), occurredAt: clock.now)])
    }

    func match(_ id: MatchID) throws -> Match { try #require(try repository.getById(id)) }
}

@Suite("MovePlayerMatches (integration)") @MainActor
struct MovePlayerMatchesIntegrationTests {
    @Test func aMergeMovesEachOfTheFoldedInPlayersMatchesToTheKeptPlayer() throws {
        let s = try MergeStack()
        let ended = try s.play(cal, dev)
        let other = try s.play(asher, cal)
        let untouched = try s.play(asher, dev)

        s.merged(keep: callum, foldIn: cal)

        #expect(try s.match(ended).setup.players == [PlayerId(callum), PlayerId(dev)])
        #expect(try s.match(ended).result == .win(Side(player: PlayerId(callum), colour: Colour.create("red").get())))
        #expect(try s.match(other).setup.players == [PlayerId(asher), PlayerId(callum)])
        #expect(try s.match(untouched).version == 4)  // started, breaker, frame, finished
        #expect(try s.repository.findByPlayer(cal).isEmpty)
        #expect(try s.repository.findByPlayer(callum).map(\.id) == [MatchId(ended), MatchId(other)])
    }

    @Test func theOpenHostQueriesFollowTheMove() throws {
        let s = try MergeStack()
        try s.play(cal, dev)
        try s.play(callum, asher)
        #expect(s.queries.matchCount(of: callum) == 1)
        #expect(!s.queries.havePlayedEachOther(callum, dev))

        s.merged(keep: callum, foldIn: cal)

        #expect(s.queries.matchCount(of: callum) == 2)
        #expect(s.queries.matchCount(of: cal) == 0)
        #expect(s.queries.havePlayedEachOther(callum, dev))
        #expect(s.queries.havePlayedEachOther(dev, callum))
        #expect(!s.queries.havePlayedEachOther(cal, dev))
    }

    @Test func eachMoveIsStoredAndPublishedAsMatchPlayerMoved() throws {
        let s = try MergeStack()
        let id = try s.play(cal, dev)
        s.merged(keep: callum, foldIn: cal)

        let moved = try #require(s.published.last)
        #expect(moved.matchId == id && moved.type == "MatchPlayerMoved" && moved.schemaVersion == 1)
        #expect(moved.streamVersion == 5)
        let event = try MatchEventWire.decode(type: moved.type, schemaVersion: moved.schemaVersion, payload: moved.payload)
        #expect(event == .matchPlayerMoved(MatchPlayerMoved(from: PlayerId(cal), to: PlayerId(callum), at: s.clock.now)))
        // The stored stream rebuilds the moved match.
        #expect(try s.match(id).version == 5)
        #expect(try s.match(id).side(of: PlayerId(callum)) != nil)
    }

    @Test func aLiveMatchMovesAndPlayCarriesOnWithTheKeptPlayer() throws {
        let s = try MergeStack()
        let id = try s.start(asher, cal)
        try s.matches.chooseBreaker(id, player: cal)
        try s.matches.awardFrame(id, to: cal)

        s.merged(keep: callum, foldIn: cal)

        #expect(s.queries.isPlayerInLiveMatch(callum))
        #expect(!s.queries.isPlayerInLiveMatch(cal))
        let screen = try #require(s.readModel.liveMatchScreen(id))
        #expect(screen.sides.map(\.id) == [asher, callum])
        #expect(screen.sides.map(\.frames) == [0, 1])
        #expect(throws: MatchCommandError.notAllowedNow) { try s.matches.awardFrame(id, to: cal) }
        try s.matches.awardFrame(id, to: callum)
        #expect(try s.match(id).score == Score(firstFrames: 0, secondFrames: 2))
    }

    @Test func aDeletedMatchIsLeftAsItIs() throws {
        let s = try MergeStack()
        let id = try s.play(cal, dev)
        try s.matches.deleteMatch(id)
        let before = s.published.count

        s.merged(keep: callum, foldIn: cal)

        #expect(s.published.count == before)
        #expect(try s.match(id).setup.players.contains(PlayerId(cal)))
        #expect(s.queries.matchCount(of: callum) == 0)
    }

    @Test func otherPlayerEventsMoveNothing() throws {
        let s = try MergeStack()
        let id = try s.play(cal, dev)
        s.dispatcher.dispatch([PlayerEventPublished(
            playerId: cal, type: "PlayersMerged", schemaVersion: 2, payload: Data("{}".utf8), occurredAt: s.clock.now)])
        #expect(try s.match(id).setup.players.contains(PlayerId(cal)))
    }
}
