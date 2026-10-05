import EventDispatch
import Foundation
import MatchesApplication
import MatchesDomain
import MatchesInfrastructure
import SQLiteSupport
import Testing

// Outside-in: StartMatch publishes MatchStarted, the template policy reacts, and the list is read
// back from the real SQLite store. The only stand-in is the Players supplier port.

private let callum = UUID()
private let asher = UUID()
private let dev = UUID()

@MainActor
private final class TemplatePlayers: MatchPlayerDirectory {
    var all = [
        MatchPlayer(id: callum, name: "Callum", colour: "blue"),
        MatchPlayer(id: asher, name: "Asher", colour: "orange"),
        MatchPlayer(id: dev, name: "Dev", colour: "green"),
    ]
    var suggestions: [MatchPlayer] { all }
    var me: PlayerRef? { callum }
    func player(_ id: PlayerRef) -> MatchPlayer? { all.first { $0.id == id } }
    func addPlayer(named name: String, colour: String) throws -> MatchPlayer { throw MatchCommandError.notAllowedNow }
}

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func tick() { now = now.addingTimeInterval(60) }
}

/// Matches + templates, wired as the composition root does.
@MainActor
private struct TemplateStack {
    let db: SQLiteDatabase
    let clock = TestClock()
    let players = TemplatePlayers()
    let matches: MatchUseCases
    let templates: TemplateUseCases
    let list: TemplateListProjection
    let repository: SQLiteTemplateRepository

    init() throws {
        db = try .inMemory()
        let clock = clock
        let store = try SQLiteMatchEventStore(db: db, originDevice: try DeviceIdentity.id(in: db))
        let settings = try MatchSettingsService(store: SQLiteMatchSettingsStore(db: db))
        settings.changeLiveMatchLimit(100)
        let dispatcher = EventDispatcher()
        matches = MatchUseCases(
            repository: EventSourcedMatchRepository(store: store), settings: settings, players: players,
            readModel: LiveMatchesProjection(players: players), dispatcher: dispatcher, now: { clock.now })
        repository = try SQLiteTemplateRepository(db: db, now: { clock.now })
        list = TemplateListProjection(reader: repository, players: players)
        templates = TemplateUseCases(repository: repository, list: list)
        templates.subscribe(to: dispatcher)
        try templates.loadTemplates()
    }

    @discardableResult
    func start(_ a: UUID, _ b: UUID, game: MatchesApplication.Game = .pool,
               style: MatchesApplication.MatchStyle = .raceTo(5)) throws -> MatchID {
        clock.tick()
        return try matches.startMatch(MatchSetup(players: [a, b], game: game, style: style, breakRule: .alternate))
    }

    func storedRows() throws -> [(id: String, count: Int)] {
        try db.query("SELECT template_id, use_count FROM templates ORDER BY rowid")
            .map { ($0.string("template_id")!, $0.int("use_count")!) }
    }
}

@Suite("Templates (integration)") @MainActor
struct TemplateIntegrationTests {
    @Test func startingANewSetupCreatesItsTemplateWithOneUse() throws {
        let s = try TemplateStack()
        try s.start(asher, callum)
        let rows = try s.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.count == 1)
        let row = try #require(s.list.templates.first)
        #expect(row.players.map(\.name) == ["Asher", "Callum"])
        #expect(row.players.map(\.colour) == ["orange", "blue"])
        #expect(row.game == .pool)
        #expect(row.style == .raceTo(5))
        #expect(row.breakRule == .alternate)
        #expect(row.useCount == 1)
    }

    @Test func startingAKnownSetupAgainAddsAUseToTheSameTemplate() throws {
        let s = try TemplateStack()
        try s.start(asher, callum, style: .bestOf(9))
        // Players the other way round and race to 5 are the same setup; the template keeps "best of 9".
        try s.start(callum, asher, style: .raceTo(5))
        let rows = try s.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.count == 2)
        #expect(s.list.templates.first?.style == .bestOf(9))
        #expect(s.list.templates.first?.players.map(\.name) == ["Asher", "Callum"])
    }

    @Test func startingFromATemplateRowPlaysItsSetupAndCountsAUse() throws {
        let s = try TemplateStack()
        try s.start(dev, callum, game: .snooker, style: .mostFramesWins)
        let row = try #require(s.list.templates.first)
        try s.matches.startMatch(row.setup)
        #expect(try s.storedRows().map(\.count) == [2])
    }

    @Test func aDeletedTemplateIsRecreatedWithOneUseWhenItsSetupIsPlayedAgain() throws {
        let s = try TemplateStack()
        try s.start(asher, callum)
        try s.start(asher, callum)
        let old = try #require(s.list.templates.first)
        try s.templates.deleteTemplate(old.id)
        #expect(try s.storedRows().isEmpty)
        #expect(try s.repository.getById(old.id) == nil)
        #expect(s.list.templates.isEmpty)

        try s.start(asher, callum)
        let rows = try s.storedRows()
        #expect(rows.count == 1)
        #expect(rows.first?.count == 1)
        #expect(s.list.templates.first?.id != old.id)
    }

    @Test func theListIsMostUsedFirstThenMostRecentlyUsed() throws {
        let s = try TemplateStack()
        try s.start(callum, dev)                       // A: 1 use
        try s.start(asher, callum)                     // B
        try s.start(asher, callum)                     // B: 2 uses
        try s.start(asher, dev, game: .snooker)        // C: 1 use, used after A
        try s.start(asher, callum, style: .bestOf(3))  // D: 1 use, most recent
        let order = s.list.templates.map { "\($0.players.map(\.name).joined(separator: "-")) \($0.style.title)" }
        #expect(order == ["Asher-Callum Race to 5", "Asher-Callum Best of 3", "Asher-Dev Race to 5", "Callum-Dev Race to 5"])
        #expect(s.list.templates.map(\.useCount) == [2, 1, 1, 1])

        // A few more uses move a template up.
        try s.start(callum, dev)
        try s.start(dev, callum)
        #expect(s.list.templates.first?.players.map(\.name) == ["Callum", "Dev"])
        #expect(s.list.templates.first?.useCount == 3)
    }

    @Test func anEmptyListOpensNewGameOnTheDetailsStep() throws {
        let s = try TemplateStack()
        #expect(s.list.opensOnDetails)
        try s.start(asher, callum)
        #expect(!s.list.opensOnDetails)
        try s.templates.deleteTemplate(try #require(s.list.templates.first).id)
        #expect(s.list.opensOnDetails)
    }

    @Test func theListSurvivesARelaunchAndFindsTemplatesByPlayer() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "templates-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteDatabase(url: url)
        let repo = try SQLiteTemplateRepository(db: db)
        let setup = try Setup.create(PlayerId(asher), PlayerId(callum), game: .pool, style: .mostFramesWins).get()
        try repo.save(Template.create(id: TemplateId(UUID()), setup: setup))

        let reopened = try SQLiteTemplateRepository(db: SQLiteDatabase(url: url))
        #expect(try reopened.findBySetup(setup)?.useCount == .one)
        #expect(try reopened.findByPlayer(callum).count == 1)
        #expect(try reopened.findByPlayer(dev).isEmpty)
        // A second active template for the same setup is refused by the store.
        #expect(throws: TemplateRepositoryError.setupAlreadyHasTemplate) {
            try reopened.save(Template.create(id: TemplateId(UUID()), setup: setup))
        }
    }

    @Test func aTemplateWhosePlayerIsNoLongerKnownIsLeftOutOfTheList() throws {
        let s = try TemplateStack()
        try s.start(asher, dev)
        try s.start(asher, callum)
        s.players.all.removeAll { $0.id == dev }
        try s.list.reload()
        #expect(s.list.templates.map { $0.players.map(\.name) } == [["Asher", "Callum"]])
    }
}
