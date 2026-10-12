import EventDispatch
import Foundation
import PlayersApplication
import PlayersDomain
import PlayersInfrastructure
import SQLiteSupport
import Testing
import UpgradePublished

// Spec 024: Players' edition guards (S3, S22, S35, S48, S52), the real use cases over real SQLite with
// a `FixedEdition` flipped by hand to simulate an unlock or a revocation. The cap is read from
// `FreeLimits`, never hard-coded.

private let cap = FreeLimits.standard.activePlayers

@MainActor
private func service(_ db: SQLiteDatabase, edition: FixedEdition) throws -> PlayersService {
    let repository = try SQLitePlayerRepository(db: db)
    let app = try PlayersService(
        repository: repository, reader: repository, meStore: SQLiteMeSettingStore(db: db),
        dispatcher: EventDispatcher(), edition: edition)
    app.matchQueries = FakePlayerMatchQueries()
    return app
}

@MainActor
@discardableResult
private func addPlayers(_ count: Int, to app: PlayersService, from start: Int = 0) throws -> [PlayerID] {
    try (start..<start + count).map { try app.addPlayer(named: "Player \($0)", colour: "blue") }
}

@MainActor
@Suite struct PlayersEditionIntegrationTests {
    @Test func countActiveExcludesArchivedMergedAwayAndRemovedPlayers() throws {
        let db = try SQLiteDatabase.inMemory()
        let repository = try SQLitePlayerRepository(db: db)
        let app = try service(db, edition: .unlocked)
        let ids = try addPlayers(5, to: app)
        try app.archivePlayer(ids[0])
        try app.archivePlayer(ids[1])
        try app.removePlayer(ids[1])
        try app.mergePlayers(keep: ids[3], foldIn: ids[2])

        #expect(try repository.countActive() == 2)
    }

    @Test func freeRefusesAddingPastTheCapWithMeIncluded() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, edition: .free)
        let me = try Welcome.player(named: "Callum", colour: "blue", list: app, commands: app)
        try app.setMe(me)
        try addPlayers(cap - 1, to: app)

        #expect(throws: UpgradeRequired(.extraPlayers)) { try app.addPlayer(named: "One Too Many", colour: "red") }
        #expect(throws: UpgradeRequired(.extraPlayers)) {
            try Welcome.player(named: "Also Too Many", colour: "red", list: app, commands: app)
        }
        #expect(app.players.count == cap)
        #expect(app.players.contains { $0.name == "One Too Many" } == false)
    }

    @Test func archivedPlayersDoNotCountTowardsTheCap() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, edition: .free)
        let ids = try addPlayers(cap, to: app)
        try app.archivePlayer(ids[0])

        try app.addPlayer(named: "Newcomer", colour: "red")
        #expect(app.players.filter { !$0.isArchived }.count == cap)
        #expect(app.players.filter(\.isArchived).map(\.id) == [ids[0]])
    }

    @Test func freeRefusesUnarchivingAtTheCapAndAllowsItBelow() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, edition: .free)
        let ids = try addPlayers(cap, to: app)
        try app.archivePlayer(ids[0])
        try app.addPlayer(named: "Newcomer", colour: "red")

        #expect(throws: UpgradeRequired(.extraPlayers)) { try app.unarchivePlayer(ids[0]) }
        #expect(app.players.first { $0.id == ids[0] }?.isArchived == true)

        try app.archivePlayer(ids[1])
        try app.unarchivePlayer(ids[0])
        #expect(app.players.first { $0.id == ids[0] }?.isArchived == false)
    }

    @Test func unarchivingAnActivePlayerIsStillTheDomainsRefusalNotAnOffer() throws {
        let app = try service(.inMemory(), edition: .free)
        let ids = try addPlayers(cap, to: app)
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.unarchivePlayer(ids[0]) }
    }

    @Test func unlockedHasNoCap() throws {
        let app = try service(.inMemory(), edition: .unlocked)
        try addPlayers(cap + 3, to: app)
        #expect(app.players.count == cap + 3)
    }

    @Test func playersOverTheCapAfterARevocationStay() throws {
        let db = try SQLiteDatabase.inMemory()
        let edition = FixedEdition.unlocked
        let app = try service(db, edition: edition)
        let ids = try addPlayers(cap + 2, to: app)
        try app.archivePlayer(ids[0])

        edition.status = .free
        let relaunched = try service(db, edition: edition)
        for current in [app, relaunched] {
            #expect(current.players.filter { !$0.isArchived }.count == cap + 1, "nobody is archived or removed")
            #expect(current.players.count == cap + 2)
        }
        // Still usable: renaming and archiving work; only a new active player is refused.
        try app.renamePlayer(ids[1], to: "Renamed")
        try app.archivePlayer(ids[2])
        #expect(throws: UpgradeRequired(.extraPlayers)) { try app.addPlayer(named: "Newcomer", colour: "red") }
        #expect(throws: UpgradeRequired(.extraPlayers)) { try app.unarchivePlayer(ids[0]) }

        edition.status = .unlocked
        try app.unarchivePlayer(ids[0])
        try app.addPlayer(named: "Newcomer", colour: "red")
        #expect(app.players.filter { !$0.isArchived }.count == cap + 2)
    }

    @Test func coloursAreRefusedAndOmittedWhileFreeAndAllShownAgainOnUnlock() throws {
        let db = try SQLiteDatabase.inMemory()
        let repository = try SQLitePlayerRepository(db: db)
        let edition = FixedEdition.unlocked
        let app = try service(db, edition: edition)
        let callum = try app.addPlayer(named: "Callum", colour: "purple")
        let asher = try app.addPlayer(named: "Asher", colour: "orange")
        try app.archivePlayer(asher)
        let unlockedList = app.players
        let unlockedSuggestions = app.suggestions(prefix: "")
        #expect(unlockedList.map(\.shownColour) == ["purple", "orange"])

        edition.status = .free
        #expect(app.players.allSatisfy { $0.shownColour == nil })
        #expect(app.suggestions(prefix: "c").map(\.shownColour) == [nil])
        #expect(throws: UpgradeRequired(.colours)) { try app.changePlayerColour(callum, to: "green") }
        #expect(try repository.getById(PlayerId(callum))?.colour.rawValue == "purple", "the colour is kept")

        // A new player while Free gets the next unused colour, not the chosen one (choosing is paid).
        let dev = try app.addPlayer(named: "Dev", colour: "purple")
        let devColour = try #require(try repository.getById(PlayerId(dev))?.colour)
        #expect(devColour.rawValue != "purple" && devColour.rawValue != "orange")

        edition.status = .unlocked
        #expect(app.players.filter { $0.id != dev } == unlockedList, "every colour is shown again, nothing changed")
        #expect(app.suggestions(prefix: "").filter { $0.id != dev } == unlockedSuggestions)
        #expect(app.players.first { $0.id == dev }?.shownColour == devColour.rawValue)
        try app.changePlayerColour(callum, to: "green")
        #expect(app.players.first { $0.id == callum }?.shownColour == "green")
    }

    @Test func theStoredColourStaysOnTheRosterForMatchesAndStats() throws {
        let edition = FixedEdition.unlocked
        let app = try service(.inMemory(), edition: edition)
        try app.addPlayer(named: "Callum", colour: "purple")
        edition.status = .free
        #expect(app.players.map(\.colour) == ["purple"])
        #expect(app.players.map(\.shownColour) == [nil])
    }
}
