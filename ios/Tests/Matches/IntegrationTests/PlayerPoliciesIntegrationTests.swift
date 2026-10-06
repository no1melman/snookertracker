import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import MatchesPublished
import PlayersPublished
import SQLiteSupport
import Testing

// Outside-in: Players' published events (in their real wire shape) reach the Matches-side policies
// through the dispatcher; matches and templates are read back from the real SQLite stores. The only
// stand-in is the Players supplier port.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()
private let cal = UUID()  // a second record of Callum, folded into him by a merge

@MainActor
private final class PolicyPlayers: MatchPlayerDirectory {
    var all = [
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

private final class PolicyClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func tick() { now = now.addingTimeInterval(60) }
}

/// Matches, templates, the open-host queries and every player policy, wired as the composition root does.
@MainActor
private struct PolicyStack {
    let db: SQLiteDatabase
    let clock = PolicyClock()
    let players = PolicyPlayers()
    let dispatcher = EventDispatcher()
    let matches: MatchUseCases
    let repository: EventSourcedMatchRepository
    let templates: TemplateUseCases
    let list: TemplateListProjection
    let queries: MatchesForPlayers
    let policies: [AnyObject]
    var published: [MatchEventPublished] { recorder.events }
    private let recorder = Recorder()

    final class Recorder: @unchecked Sendable { var events: [MatchEventPublished] = [] }

    init() throws {
        db = try .inMemory()
        let clock = clock
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db))
        settings.changeLiveMatchLimit(100)
        repository = EventSourcedMatchRepository(store: store)
        matches = MatchUseCases(
            repository: repository, settings: settings, players: players,
            readModel: LiveMatchesProjection(players: players), dispatcher: dispatcher, now: { clock.now })
        let templateRepository = try SQLiteTemplateRepository(db: db, now: { clock.now })
        list = TemplateListProjection(reader: templateRepository, players: players)
        templates = TemplateUseCases(repository: templateRepository, list: list)
        templates.subscribe(to: dispatcher)
        try templates.loadTemplates()
        queries = MatchesForPlayers(matches: matches)

        let deleteMatches = DeleteMatchesOnPlayerRemoved(matches: matches)
        let deleteTemplates = DeleteTemplatesOnPlayerRemoved(templates: templates)
        let combine = CombineTemplatesAfterMerge(templates: templates)
        let hide = HideArchivedPlayersTemplates(list: list)
        deleteMatches.subscribe(to: dispatcher)
        deleteTemplates.subscribe(to: dispatcher)
        combine.subscribe(to: dispatcher)
        hide.subscribe(to: dispatcher)
        policies = [deleteMatches, deleteTemplates, combine, hide]
        let recorder = recorder
        dispatcher.subscribe(MatchEventPublished.self) { recorder.events.append($0) }
    }

    @discardableResult
    func start(_ a: UUID, _ b: UUID, style: MatchesApplication.MatchStyle = .raceTo(5)) throws -> MatchID {
        clock.tick()
        return try matches.startMatch(MatchSetup(players: [a, b], game: .pool, style: style, breakRule: .alternate))
    }

    /// A match played to the end.
    @discardableResult
    func play(_ a: UUID, _ b: UUID) throws -> MatchID {
        let id = try start(a, b, style: .raceTo(1))
        try matches.chooseBreaker(id, player: a)
        try matches.awardFrame(id, to: a)
        try matches.finishMatch(id)
        return id
    }

    /// Players publishes a player event (the payload as `PlayerEventWire` encodes it).
    func publish(_ type: String, player: UUID, payload: [String: String] = [:]) {
        var body = payload
        body["occurredAt"] = "\(clock.now.timeIntervalSince1970)"
        let json = "{" + body.sorted { $0.key < $1.key }.map { key, value in
            "\"\(key)\":" + (key == "occurredAt" ? value : "\"\(value)\"")
        }.joined(separator: ",") + "}"
        dispatcher.dispatch([PlayerEventPublished(
            playerId: player, type: type, schemaVersion: 1, payload: Data(json.utf8), occurredAt: clock.now)])
    }

    func removed(_ player: UUID) { publish("PlayerRemoved", player: player, payload: ["playerId": player.uuidString]) }
    func archived(_ player: UUID) { publish("PlayerArchived", player: player, payload: ["playerId": player.uuidString]) }
    func unarchived(_ player: UUID) { publish("PlayerUnarchived", player: player, payload: ["playerId": player.uuidString]) }
    func merged(keep: UUID, foldIn: UUID) {
        publish("PlayersMerged", player: foldIn,
                payload: ["keptPlayerId": keep.uuidString, "foldedInPlayerId": foldIn.uuidString])
    }

    func status(_ id: MatchID) throws -> MatchStatus? { try repository.getById(id)?.status }

    func storedTemplates() throws -> [(players: Set<String>, count: Int)] {
        try db.query("SELECT first_player, second_player, use_count FROM templates ORDER BY use_count DESC, rowid")
            .map { (Set([$0.string("first_player")!, $0.string("second_player")!]), $0.int("use_count")!) }
    }
}

@Suite("PlayerMatchQueries (integration)") @MainActor
struct PlayerMatchQueriesIntegrationTests {
    @Test func aPlayerIsInALiveMatchOnlyWhileOneOfTheirMatchesIsLive() throws {
        let s = try PolicyStack()
        #expect(!s.queries.isPlayerInLiveMatch(asher))
        let id = try s.start(asher, callum)
        #expect(s.queries.isPlayerInLiveMatch(asher))
        #expect(s.queries.isPlayerInLiveMatch(callum))
        #expect(!s.queries.isPlayerInLiveMatch(dev))
        try s.matches.pauseMatch(id)
        #expect(s.queries.isPlayerInLiveMatch(asher))
        try s.matches.cancelMatch(id)
        #expect(!s.queries.isPlayerInLiveMatch(asher))
    }

    @Test func twoPlayersHavePlayedEachOtherWhileAMatchBetweenThemExists() throws {
        let s = try PolicyStack()
        try s.play(asher, dev)
        #expect(!s.queries.havePlayedEachOther(asher, callum))
        let id = try s.play(callum, asher)
        #expect(s.queries.havePlayedEachOther(asher, callum))
        #expect(s.queries.havePlayedEachOther(callum, asher))
        try s.matches.deleteMatch(id)
        #expect(!s.queries.havePlayedEachOther(asher, callum))
        // A cancelled match still counts: a merge would leave a player against themselves.
        try s.matches.cancelMatch(try s.start(callum, asher))
        #expect(s.queries.havePlayedEachOther(asher, callum))
    }

    @Test func theMatchCountLeavesOutDeletedMatches() throws {
        let s = try PolicyStack()
        #expect(s.queries.matchCount(of: asher) == 0)
        let first = try s.play(asher, callum)
        try s.play(dev, asher)
        try s.start(asher, callum)
        #expect(s.queries.matchCount(of: asher) == 3)
        #expect(s.queries.matchCount(of: dev) == 1)
        try s.matches.deleteMatch(first)
        #expect(s.queries.matchCount(of: asher) == 2)
    }
}

@Suite("Player policies (integration)") @MainActor
struct PlayerPoliciesIntegrationTests {
    @Test func removingAPlayerDeletesEachOfTheirMatchesThroughDeleteMatch() throws {
        let s = try PolicyStack()
        let a = try s.play(dev, asher)
        let b = try s.play(callum, dev)
        let cancelled = try s.start(dev, callum)
        try s.matches.cancelMatch(cancelled)
        let other = try s.play(asher, callum)

        s.removed(dev)
        #expect(try s.status(a) == .deleted)
        #expect(try s.status(b) == .deleted)
        #expect(try s.status(cancelled) == .deleted)
        #expect(try s.status(other) == .finished)
        #expect(s.queries.matchCount(of: dev) == 0)
        // Each deletion is published, so Stats drops the match.
        #expect(Set(s.published.filter { $0.type == "MatchDeleted" }.map(\.matchId)) == [a, b, cancelled])
    }

    @Test func aLiveMatchOfARemovedPlayerIsCancelledThenDeleted() throws {
        let s = try PolicyStack()
        let live = try s.start(dev, asher)
        s.removed(dev)
        #expect(try s.status(live) == .deleted)
        #expect(!s.queries.isPlayerInLiveMatch(asher))
    }

    @Test func removingAPlayerDeletesTheirTemplates() throws {
        let s = try PolicyStack()
        try s.start(dev, asher)
        try s.start(callum, dev, style: .mostFramesWins)
        try s.start(asher, callum)
        s.removed(dev)
        #expect(try s.storedTemplates().map(\.players) == [[asher.uuidString, callum.uuidString]])
        #expect(s.list.templates.map { $0.players.map(\.name) } == [["Asher", "Callum"]])
    }

    @Test func archivedPlayersTemplatesAreHiddenAndReappearOnUnarchive() throws {
        let s = try PolicyStack()
        try s.start(dev, asher)
        try s.start(asher, callum)
        s.archived(dev)
        #expect(s.list.templates.map { $0.players.map(\.name) } == [["Asher", "Callum"]])
        #expect(try s.storedTemplates().count == 2)  // hidden, not deleted

        s.unarchived(dev)
        #expect(s.list.templates.count == 2)
    }

    @Test func playersArchivedBeforeLaunchAreHiddenOnceSeeded() throws {
        let s = try PolicyStack()
        try s.start(dev, asher)
        try s.start(asher, callum)
        s.list.seedArchived([dev])
        #expect(s.list.templates.map { $0.players.map(\.name) } == [["Asher", "Callum"]])
    }

    @Test func aMergeMovesTheFoldedInPlayersTemplatesAndCombinesThoseThatBecomeIdentical() throws {
        let s = try PolicyStack()
        try s.start(callum, asher)
        try s.start(callum, asher)                      // Callum v Asher: 2 uses
        try s.start(asher, cal)                         // Asher v Cal: becomes Callum v Asher
        try s.start(cal, dev, style: .mostFramesWins)   // Cal v Dev: moves to Callum v Dev

        s.merged(keep: callum, foldIn: cal)
        let stored = try s.storedTemplates()
        #expect(stored.map(\.count) == [3, 1])
        #expect(stored.map(\.players) == [[callum.uuidString, asher.uuidString], [callum.uuidString, dev.uuidString]])
        // The moved template keeps Cal's place in the entry order, now as Callum.
        s.players.all.removeAll { $0.id == cal }
        let rows = s.list.templates
        #expect(rows.map { $0.players.map(\.name) } == [["Callum", "Asher"], ["Callum", "Dev"]])
        #expect(rows.map(\.useCount) == [3, 1])
        // Playing the merged setup counts on the combined template.
        try s.start(asher, callum)
        #expect(try s.storedTemplates().map(\.count) == [4, 1])
    }

    @Test func aTemplateOfTheTwoMergedPlayersTogetherIsDeleted() throws {
        let s = try PolicyStack()
        let id = try s.play(cal, callum)
        try s.matches.deleteMatch(id)                   // so they no longer count as having played
        try s.start(asher, callum)
        s.merged(keep: callum, foldIn: cal)
        #expect(try s.storedTemplates().map(\.players) == [[asher.uuidString, callum.uuidString]])
    }

    @Test func eventsMatchesDoesNotReactToAreIgnored() throws {
        let s = try PolicyStack()
        let id = try s.play(dev, asher)
        s.publish("PlayerRenamed", player: dev, payload: ["playerId": dev.uuidString])
        s.dispatcher.dispatch([PlayerEventPublished(
            playerId: dev, type: "PlayerRemoved", schemaVersion: 2, payload: Data("{}".utf8), occurredAt: s.clock.now)])
        #expect(try s.status(id) == .finished)
        #expect(try s.storedTemplates().count == 1)
    }
}
