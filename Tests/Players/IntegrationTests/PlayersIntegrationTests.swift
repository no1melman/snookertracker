import EventDispatch
import Foundation
import PlayersApplication
import PlayersDomain
import PlayersInfrastructure
import PlayersPublished
import SQLiteSupport
import Testing

// Outside-in: the real use cases over the real SQLite adapters.

@MainActor
private func service(_ db: SQLiteDatabase, dispatcher: EventDispatcher = EventDispatcher()) throws -> PlayersService {
    let repository = try SQLitePlayerRepository(db: db)
    return try PlayersService(
        repository: repository, reader: repository, meStore: SQLiteMeSettingStore(db: db), dispatcher: dispatcher)
}

@MainActor
@Suite struct PlayersIntegrationTests {
    @Test func playersAndMeSurviveARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "players-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let app = try service(SQLiteDatabase(url: url))
            let callum = try app.addPlayer(named: "Callum", colour: "blue")
            try app.addPlayer(named: "asher", colour: "orange")
            try app.setMe(callum)
        }
        let relaunched = try service(SQLiteDatabase(url: url))
        #expect(relaunched.players.map(\.name) == ["asher", "Callum"])
        #expect(relaunched.me?.name == "Callum")
    }

    @Test func namesAreUniqueCaseInsensitively() throws {
        let app = try service(.inMemory())
        try app.addPlayer(named: "Callum", colour: "blue")
        #expect(throws: PlayerCommandError.nameTaken("callum")) { try app.addPlayer(named: " callum ", colour: "red") }
        #expect(throws: PlayerCommandError.emptyName) { try app.addPlayer(named: "  ", colour: "red") }
        #expect(app.players.count == 1)
    }

    @Test func renameAndColourChangeArePersisted() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db)
        let id = try app.addPlayer(named: "Ash", colour: "orange")
        let dev = try app.addPlayer(named: "Dev", colour: "green")
        try app.renamePlayer(id, to: "Asher")
        try app.changePlayerColour(id, to: "purple")
        #expect(throws: PlayerCommandError.nameTaken("dev")) { try app.renamePlayer(id, to: "dev") }

        let reopened = try service(db)
        #expect(reopened.players.first { $0.id == id } == PlayerListItem(id: id, name: "Asher", colour: "purple"))
        #expect(reopened.players.first { $0.id == dev }?.name == "Dev")
    }

    @Test func anArchivedPlayersNameIsHeldUntilTheyAreRemoved() throws {
        let db = try SQLiteDatabase.inMemory()
        let repository = try SQLitePlayerRepository(db: db)
        let id = PlayerId.new()
        let name = try PlayerName.create("Callum").get()
        let archived = try Player.add(id: id, name: name, colour: .blue, sameNamed: nil, at: .now).get()
            .archive(isInLiveMatch: false, at: .now).get()
        try repository.save(archived)

        let app = try service(db)
        #expect(app.players.map(\.isArchived) == [true])
        #expect(throws: PlayerCommandError.nameHeldByArchivedPlayer("callum")) { try app.addPlayer(named: "callum", colour: "red") }

        try repository.save(archived.remove(at: .now).get())
        let reopened = try service(db)
        #expect(reopened.players.isEmpty)
        try reopened.addPlayer(named: "callum", colour: "red")
        #expect(try repository.findByName(name)?.status == .active)
    }

    @Test func anUnknownColourTakesTheNextUnusedOne() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db)
        try app.addPlayer(named: "A", colour: "red")
        let b = try app.addPlayer(named: "B", colour: "not-a-colour")
        #expect(app.players.first { $0.id == b }?.colour == Palette.standard.colours[1].rawValue)
    }

    @Test func playerEventsArePublishedAfterTheSave() throws {
        let dispatcher = EventDispatcher()
        nonisolated(unsafe) var received: [String] = []
        dispatcher.subscribe(PlayerEventPublished.self) { received.append($0.type) }
        let app = try service(.inMemory(), dispatcher: dispatcher)
        let id = try app.addPlayer(named: "Callum", colour: "blue")
        try app.renamePlayer(id, to: "Cal")
        try app.setMe(id)  // a setting: raises nothing
        #expect(received == ["PlayerAdded", "PlayerRenamed"])
    }

    @Test func meMustBeAnExistingPlayer() throws {
        let app = try service(.inMemory())
        #expect(throws: PlayerCommandError.unknownPlayer) { try app.setMe(UUID()) }
        #expect(app.me == nil)
    }
}
