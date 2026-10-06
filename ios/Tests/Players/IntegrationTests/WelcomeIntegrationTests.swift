import EventDispatch
import Foundation
import PlayersApplication
import PlayersInfrastructure
import PlayersPublished
import SQLiteSupport
import Testing

// The welcome (S48) and `WhoAmI` (spec 012): the real use cases over the real SQLite adapters.

@MainActor
private func service(_ db: SQLiteDatabase, dispatcher: EventDispatcher = EventDispatcher()) throws -> PlayersService {
    let repository = try SQLitePlayerRepository(db: db)
    return try PlayersService(
        repository: repository, reader: repository, meStore: SQLiteMeSettingStore(db: db), dispatcher: dispatcher)
}

@MainActor
@Suite struct WelcomeIntegrationTests {
    @Test func theWelcomeCreatesThePlayerThenSetsMe() throws {
        let db = try SQLiteDatabase.inMemory()
        let dispatcher = EventDispatcher()
        var published: [String] = []
        dispatcher.subscribe(PlayerEventPublished.self) { published.append($0.type) }
        let app = try service(db, dispatcher: dispatcher)

        let id = try Welcome.player(named: " Callum ", colour: "blue", list: app, commands: app)
        #expect(published == ["PlayerAdded"])
        #expect(app.whoAmI == nil, "Me waits for the walkthrough, so the welcome stays up")

        try app.setMe(id)
        #expect(try service(db).whoAmI == WhoAmI(id: id, name: "Callum"))
    }

    @Test func anInterruptedWelcomeTakesThePlayerItAlreadyCreated() throws {
        let db = try SQLiteDatabase.inMemory()
        let first = try Welcome.player(named: "Callum", colour: "blue", list: try service(db), commands: try service(db))

        let relaunched = try service(db)
        let again = try Welcome.player(named: "CALLUM", colour: "red", list: relaunched, commands: relaunched)
        #expect(again == first)
        #expect(relaunched.players.count == 1)
    }

    @Test func theWelcomeRefusesABlankOrArchivedName() throws {
        let app = try service(.inMemory())
        #expect(throws: PlayerCommandError.emptyName) {
            try Welcome.player(named: "  ", colour: "blue", list: app, commands: app)
        }
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        app.matchQueries = FakePlayerMatchQueries()
        try app.archivePlayer(callum)
        #expect(throws: PlayerCommandError.nameHeldByArchivedPlayer("Callum", archived: callum)) {
            try Welcome.player(named: "Callum", colour: "blue", list: app, commands: app)
        }
    }

    @Test func whoAmIIsDisplayedAsMeAndName() throws {
        let app = try service(.inMemory())
        #expect(app.whoAmI == nil)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        try app.setMe(callum)
        #expect(app.whoAmI?.displayName == "Me (Callum)")
        try app.renamePlayer(callum, to: "Cal")
        #expect(app.whoAmI == WhoAmI(id: callum, name: "Cal"))
    }
}
