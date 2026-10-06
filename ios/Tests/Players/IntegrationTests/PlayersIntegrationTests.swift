import EventDispatch
import Foundation
import MatchesPublished
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
        #expect(throws: PlayerCommandError.nameHeldByArchivedPlayer("callum", archived: id.value)) { try app.addPlayer(named: "callum", colour: "red") }

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

// MARK: - Lifecycle use cases (S33, S34, S35, S42) against a fake Matches open host

/// Matches' `PlayerMatchQueries`, in memory: the matches it knows about, as player pairs.
@MainActor
final class FakePlayerMatchQueries: PlayerMatchQueries {
    var live: Set<UUID> = []
    var matches: [(UUID, UUID)] = []

    func isPlayerInLiveMatch(_ player: UUID) -> Bool { live.contains(player) }
    func havePlayedEachOther(_ a: UUID, _ b: UUID) -> Bool {
        matches.contains { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }
    }
    func matchCount(of player: UUID) -> Int { matches.filter { $0.0 == player || $0.1 == player }.count }
}

@MainActor
private func service(
    _ db: SQLiteDatabase, matches: FakePlayerMatchQueries, dispatcher: EventDispatcher = EventDispatcher()
) throws -> PlayersService {
    let app = try service(db, dispatcher: dispatcher)
    app.matchQueries = matches
    return app
}

@MainActor
@Suite struct PlayerLifecycleIntegrationTests {
    let matches = FakePlayerMatchQueries()

    @Test func archiveIsRefusedWhileInALiveMatch() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        matches.live = [callum]
        #expect(throws: PlayerCommandError.inLiveMatch("Callum")) { try app.archivePlayer(callum) }
        #expect(try service(db).players.map(\.isArchived) == [false])

        matches.live = []
        try app.archivePlayer(callum)
        #expect(try service(db).players.map(\.isArchived) == [true])
    }

    @Test func archiveIsRefusedUntilMatchesIsWiredIn() throws {
        let app = try service(.inMemory())
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.archivePlayer(callum) }
    }

    @Test func unarchiveBringsThePlayerBack() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        try app.archivePlayer(callum)
        #expect(app.suggestions(prefix: "").isEmpty)
        try app.unarchivePlayer(callum)
        #expect(try service(db).players == [PlayerListItem(id: callum, name: "Callum", colour: "blue")])
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.unarchivePlayer(callum) }
    }

    @Test func mergeIsRefusedWhenTheyHavePlayedEachOther() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let cal = try app.addPlayer(named: "Cal", colour: "red")
        matches.matches = [(cal, callum)]
        #expect(throws: PlayerCommandError.havePlayedEachOther("Callum", "Cal")) {
            try app.mergePlayers(keep: callum, foldIn: cal)
        }
        #expect(throws: PlayerCommandError.cannotMergeIntoSelf) { try app.mergePlayers(keep: cal, foldIn: cal) }
        #expect(try service(db).players.count == 2)
    }

    @Test func mergeFoldsThePlayerAwayAndFreesTheName() throws {
        let db = try SQLiteDatabase.inMemory()
        let dispatcher = EventDispatcher()
        nonisolated(unsafe) var received: [PlayerEventPublished] = []
        dispatcher.subscribe(PlayerEventPublished.self) { received.append($0) }
        let app = try service(db, matches: matches, dispatcher: dispatcher)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let cal = try app.addPlayer(named: "Cal", colour: "red")
        try app.mergePlayers(keep: callum, foldIn: cal)

        #expect(try service(db).players.map(\.id) == [callum])
        #expect(received.last?.type == "PlayersMerged")
        #expect(received.last?.playerId == cal)
        let repository = try SQLitePlayerRepository(db: db)
        #expect(try repository.getById(PlayerId(cal))?.mergedInto == PlayerId(callum))
        try app.addPlayer(named: "cal", colour: "green")  // a merged-away name is free again
    }

    @Test func mergingAnArchivedPlayerIsRefused() throws {
        let app = try service(.inMemory(), matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let cal = try app.addPlayer(named: "Cal", colour: "red")
        try app.archivePlayer(cal)
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.mergePlayers(keep: callum, foldIn: cal) }
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.mergePlayers(keep: cal, foldIn: callum) }
    }

    @Test func meFollowsTheKeptPlayerOnMerge() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let cal = try app.addPlayer(named: "Cal", colour: "red")
        try app.setMe(cal)
        try app.mergePlayers(keep: callum, foldIn: cal)
        #expect(app.me?.id == callum)
        #expect(try service(db).me?.id == callum)
    }

    @Test func removeIsForArchivedPlayersOnly() throws {
        let db = try SQLiteDatabase.inMemory()
        let app = try service(db, matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.removePlayer(callum) }

        try app.archivePlayer(callum)
        try app.removePlayer(callum)
        #expect(try service(db).players.isEmpty)
        #expect(throws: PlayerCommandError.notAllowedNow) { try app.removePlayer(callum) }
    }

    @Test func removalClearsMeAndPublishesPlayerRemoved() throws {
        let db = try SQLiteDatabase.inMemory()
        let dispatcher = EventDispatcher()
        nonisolated(unsafe) var received: [String] = []
        dispatcher.subscribe(PlayerEventPublished.self) { received.append($0.type) }
        let app = try service(db, matches: matches, dispatcher: dispatcher)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let asher = try app.addPlayer(named: "Asher", colour: "orange")
        try app.setMe(callum)
        try app.archivePlayer(asher)
        try app.removePlayer(asher)
        #expect(app.me?.id == callum)  // someone else's removal leaves Me alone

        try app.archivePlayer(callum)
        try app.removePlayer(callum)
        #expect(app.me == nil)
        #expect(try service(db).me == nil)
        #expect(received.suffix(2) == ["PlayerArchived", "PlayerRemoved"])
    }

    @Test func matchCountComesFromMatches() throws {
        let app = try service(.inMemory(), matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        let asher = try app.addPlayer(named: "Asher", colour: "orange")
        #expect(app.matchCount(of: callum) == 0)
        matches.matches = [(callum, asher), (asher, callum), (asher, UUID())]
        #expect(app.matchCount(of: callum) == 2)
        #expect(try service(.inMemory()).matchCount(of: callum) == 0)
    }

    @Test func addingAnArchivedNameOffersThatPlayerForRemoval() throws {
        let app = try service(.inMemory(), matches: matches)
        let callum = try app.addPlayer(named: "Callum", colour: "blue")
        try app.archivePlayer(callum)
        do {
            try app.addPlayer(named: "CALLUM", colour: "red")
            Issue.record("expected the archived-name refusal")
        } catch PlayerCommandError.nameHeldByArchivedPlayer(_, let archived) {
            try app.removePlayer(archived)
            try app.addPlayer(named: "CALLUM", colour: "red")
        }
        #expect(app.players.map(\.name) == ["CALLUM"])
    }

    @Test func suggestionsAreActivePlayersByCaseInsensitivePrefix() throws {
        let app = try service(.inMemory(), matches: matches)
        try app.addPlayer(named: "Callum", colour: "blue")
        try app.addPlayer(named: "cal", colour: "red")
        try app.addPlayer(named: "Asher", colour: "orange")
        let carl = try app.addPlayer(named: "Carl", colour: "green")
        try app.archivePlayer(carl)
        #expect(app.suggestions(prefix: " CA").map(\.name) == ["cal", "Callum"])
        #expect(app.suggestions(prefix: "").map(\.name) == ["Asher", "cal", "Callum"])
        #expect(app.suggestions(prefix: "z").isEmpty)
    }
}
