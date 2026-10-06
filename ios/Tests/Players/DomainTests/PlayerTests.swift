import Foundation
import Testing
import PlayersDomain

private let noon = Date(timeIntervalSince1970: 1_790_000_000)

private func name(_ raw: String) throws -> PlayerName { try PlayerName.create(raw).get() }

/// A freshly added player with its `PlayerAdded` already dispatched.
private func activePlayer(_ raw: String, colour: Colour = .red) throws -> Player {
    try Player.add(id: .new(), name: name(raw), colour: colour, sameNamed: nil, at: noon).get()
        .clearingDomainEvents()
}

private func player(_ raw: String, status: PlayerStatus) throws -> Player {
    try Player.reconstitute(id: .new(), name: name(raw), colour: .blue, status: status, mergedInto: nil)
}

@Suite("Player › add")
struct AddPlayerTests {
    @Test("adding a player creates an active player and raises PlayerAdded")
    func addRaisesEvent() throws {
        let id = PlayerId.new()
        let callum = try name("Callum")

        let player = try Player.add(id: id, name: callum, colour: .orange, sameNamed: nil, at: noon).get()

        #expect(player.status == .active)
        #expect(player.name == callum)
        #expect(player.colour == .orange)
        #expect(player.domainEvents == [.added(PlayerAdded(playerId: id, name: callum, colour: .orange, occurredAt: noon))])
    }

    @Test("a name already used by an active player is refused, whatever its case")
    func nameUniqueCaseInsensitive() throws {
        let existing = try activePlayer("Callum")

        let result = try Player.add(id: .new(), name: name("callum"), colour: .red, sameNamed: existing, at: noon)

        #expect(result == .failure(.nameTaken(by: existing.id)))
    }

    @Test("an archived player's name is blocked, pointing at that player for removal")
    func archivedNameBlocked() throws {
        let archived = try player("Asher", status: .archived)

        let result = try Player.add(id: .new(), name: name("ASHER"), colour: .red, sameNamed: archived, at: noon)

        #expect(result == .failure(.nameHeldByArchivedPlayer(archived.id)))
    }

    @Test("a removed or merged-away player's name is free again", arguments: [PlayerStatus.removed, .mergedAway])
    func freedNameReusable(status: PlayerStatus) throws {
        let gone = try player("Asher", status: status)

        let result = try Player.add(id: .new(), name: name("Asher"), colour: .red, sameNamed: gone, at: noon)

        #expect(try result.get().name.value == "Asher")
    }
}

@Suite("Player › rename")
struct RenamePlayerTests {
    @Test("renaming raises PlayerRenamed with the old and new names")
    func renameRaisesEvent() throws {
        let cal = try activePlayer("Cal")
        let callum = try name("Callum")

        let renamed = try cal.rename(to: callum, sameNamed: nil, at: noon).get()

        #expect(renamed.name.value == "Callum")
        #expect(renamed.domainEvents == [.renamed(PlayerRenamed(
            playerId: cal.id, oldName: try name("Cal"), newName: callum, occurredAt: noon))])
    }

    @Test("renaming to another active player's name is refused, case-insensitively")
    func renameToTakenName() throws {
        let cal = try activePlayer("Cal")
        let asher = try activePlayer("Asher")

        #expect(try cal.rename(to: name("asher"), sameNamed: asher, at: noon) == .failure(.nameTaken(by: asher.id)))
    }

    @Test("renaming to an archived player's name is blocked")
    func renameToArchivedName() throws {
        let cal = try activePlayer("Cal")
        let archived = try player("Asher", status: .archived)

        #expect(try cal.rename(to: name("Asher"), sameNamed: archived, at: noon)
            == .failure(.nameHeldByArchivedPlayer(archived.id)))
    }

    @Test("a player may change the case of their own name")
    func recaseOwnName() throws {
        let cal = try activePlayer("cal")

        let renamed = try cal.rename(to: name("Cal"), sameNamed: cal, at: noon).get()

        #expect(renamed.name.value == "Cal")
        #expect(renamed.domainEvents.count == 1)
    }

    @Test("renaming to the identical name changes nothing and raises nothing")
    func identicalNameNoOp() throws {
        let cal = try activePlayer("Cal")
        #expect(try cal.rename(to: name("Cal"), sameNamed: cal, at: noon) == .success(cal))
    }

    @Test("a merged-away or removed player cannot be renamed", arguments: [PlayerStatus.mergedAway, .removed])
    func goneCannotRename(status: PlayerStatus) throws {
        let gone = try player("Cal", status: status)
        #expect(try gone.rename(to: name("Callum"), sameNamed: nil, at: noon)
            == .failure(.playerNoLongerExists(status: status)))
    }
}

@Suite("Player › changeColour")
struct ChangeColourTests {
    @Test("changing colour raises PlayerColourChanged")
    func changeColourRaisesEvent() throws {
        let cal = try activePlayer("Cal", colour: .red)

        let changed = try cal.changeColour(to: .teal, at: noon).get()

        #expect(changed.colour == .teal)
        #expect(changed.domainEvents == [.colourChanged(PlayerColourChanged(
            playerId: cal.id, oldColour: .red, newColour: .teal, occurredAt: noon))])
    }

    @Test("picking the current colour changes nothing")
    func sameColourNoOp() throws {
        let cal = try activePlayer("Cal", colour: .red)
        #expect(cal.changeColour(to: .red, at: noon) == .success(cal))
    }

    @Test("an archived player's colour can change")
    func archivedCanChangeColour() throws {
        let archived = try player("Cal", status: .archived)
        #expect(try archived.changeColour(to: .pink, at: noon).get().colour == .pink)
    }

    @Test("a merged-away or removed player's colour cannot change", arguments: [PlayerStatus.mergedAway, .removed])
    func goneCannotRecolour(status: PlayerStatus) throws {
        let gone = try player("Cal", status: status)
        #expect(gone.changeColour(to: .pink, at: noon) == .failure(.playerNoLongerExists(status: status)))
    }
}

@Suite("Player › mergeInto")
struct MergePlayersTests {
    @Test("merging folds the player into the kept one and raises PlayersMerged")
    func mergeRaisesEvent() throws {
        let cal = try activePlayer("Cal")
        let callum = try activePlayer("Callum")

        let merged = try cal.mergeInto(callum, havePlayedEachOther: false, at: noon).get()

        #expect(merged.status == .mergedAway)
        #expect(merged.mergedInto == callum.id)
        #expect(merged.domainEvents == [.merged(PlayersMerged(
            keptPlayerId: callum.id, foldedInPlayerId: cal.id, occurredAt: noon))])
    }

    @Test("merging two players who have played each other is refused")
    func refusedWhenPlayedEachOther() throws {
        let cal = try activePlayer("Cal")
        let callum = try activePlayer("Callum")

        #expect(cal.mergeInto(callum, havePlayedEachOther: true, at: noon)
            == .failure(.havePlayedEachOther(callum.id, cal.id)))
    }

    @Test("a player cannot be merged into themselves")
    func refusedIntoSelf() throws {
        let cal = try activePlayer("Cal")
        #expect(cal.mergeInto(cal, havePlayedEachOther: false, at: noon) == .failure(.cannotMergeIntoSelf))
    }

    @Test("only an active player can be folded in",
          arguments: [PlayerStatus.archived, .mergedAway, .removed])
    func foldedInMustBeActive(status: PlayerStatus) throws {
        let cal = try player("Cal", status: status)
        let callum = try activePlayer("Callum")

        #expect(cal.mergeInto(callum, havePlayedEachOther: false, at: noon)
            == .failure(.invalidTransition(from: status, to: .mergedAway)))
    }

    @Test("the kept player must be active",
          arguments: [PlayerStatus.archived, .mergedAway, .removed])
    func keptMustBeActive(status: PlayerStatus) throws {
        let cal = try activePlayer("Cal")
        let callum = try player("Callum", status: status)

        #expect(cal.mergeInto(callum, havePlayedEachOther: false, at: noon)
            == .failure(.keptPlayerNotActive(callum.id, status: status)))
    }
}

@Suite("Player › archive, unarchive, remove")
struct PlayerLifecycleTests {
    @Test("archiving an active player raises PlayerArchived")
    func archiveRaisesEvent() throws {
        let cal = try activePlayer("Cal")

        let archived = try cal.archive(isInLiveMatch: false, at: noon).get()

        #expect(archived.status == .archived)
        #expect(archived.domainEvents == [.archived(PlayerArchived(playerId: cal.id, occurredAt: noon))])
    }

    @Test("archiving is refused while the player is in a live match")
    func archiveRefusedInLiveMatch() throws {
        let cal = try activePlayer("Cal")
        #expect(cal.archive(isInLiveMatch: true, at: noon) == .failure(.inLiveMatch))
    }

    @Test("only an active player can be archived", arguments: [PlayerStatus.archived, .mergedAway, .removed])
    func archiveRefusedUnlessActive(status: PlayerStatus) throws {
        let p = try player("Cal", status: status)
        #expect(p.archive(isInLiveMatch: false, at: noon) == .failure(.invalidTransition(from: status, to: .archived)))
    }

    @Test("unarchiving an archived player makes them active and raises PlayerUnarchived")
    func unarchiveRaisesEvent() throws {
        let archived = try player("Cal", status: .archived)

        let active = try archived.unarchive(at: noon).get()

        #expect(active.status == .active)
        #expect(active.domainEvents == [.unarchived(PlayerUnarchived(playerId: archived.id, occurredAt: noon))])
    }

    @Test("only an archived player can be unarchived", arguments: [PlayerStatus.active, .mergedAway, .removed])
    func unarchiveRefusedUnlessArchived(status: PlayerStatus) throws {
        let p = try player("Cal", status: status)
        #expect(p.unarchive(at: noon) == .failure(.invalidTransition(from: status, to: .active)))
    }

    @Test("removing an archived player raises PlayerRemoved")
    func removeRaisesEvent() throws {
        let archived = try player("Cal", status: .archived)

        let removed = try archived.remove(at: noon).get()

        #expect(removed.status == .removed)
        #expect(removed.domainEvents == [.removed(PlayerRemoved(playerId: archived.id, occurredAt: noon))])
    }

    @Test("only an archived player can be removed", arguments: [PlayerStatus.active, .mergedAway, .removed])
    func removeRefusedUnlessArchived(status: PlayerStatus) throws {
        let p = try player("Cal", status: status)
        #expect(p.remove(at: noon) == .failure(.invalidTransition(from: status, to: .removed)))
    }

    @Test("a transition returns a new player and leaves the original untouched")
    func transitionsDoNotMutate() throws {
        let cal = try activePlayer("Cal")
        _ = try cal.archive(isInLiveMatch: false, at: noon).get()
        #expect(cal.status == .active)
        #expect(cal.domainEvents.isEmpty)
    }

    @Test("player events round-trip through Codable")
    func eventsCodable() throws {
        let events: [PlayerEvent] = try [
            .added(PlayerAdded(playerId: .new(), name: name("Cal"), colour: .mint, occurredAt: noon)),
            .merged(PlayersMerged(keptPlayerId: .new(), foldedInPlayerId: .new(), occurredAt: noon)),
            .removed(PlayerRemoved(playerId: .new(), occurredAt: noon)),
        ]
        let data = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([PlayerEvent].self, from: data) == events)
    }
}
