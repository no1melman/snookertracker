import Foundation

public enum PlayerError: Error, Equatable, Sendable {
    /// The name belongs to an active player (case-insensitively).
    case nameTaken(by: PlayerId)
    /// The name belongs to an archived player. The caller should offer `RemovePlayer` for that player.
    case nameHeldByArchivedPlayer(PlayerId)
    /// The lifecycle does not allow this move (see `PlayerStatus.canTransition(to:)`).
    case invalidTransition(from: PlayerStatus, to: PlayerStatus)
    /// Rename / colour change on a player who was merged away or removed.
    case playerNoLongerExists(status: PlayerStatus)
    /// Archiving is refused while the player is in a live match.
    case inLiveMatch
    /// A player cannot be merged into themselves.
    case cannotMergeIntoSelf
    /// The player being kept must be active.
    case keptPlayerNotActive(PlayerId, status: PlayerStatus)
    /// The two players have played each other, so a merge would create a match against yourself.
    case havePlayedEachOther(PlayerId, PlayerId)
}

/// The `Player` aggregate root.
///
/// Guards that need facts from outside this aggregate take them as plain arguments:
/// - name uniqueness: `sameNamed`, the player the repository's `findByName` returned (or `nil`);
/// - Matches' open-host queries: `isInLiveMatch` (`IsPlayerInLiveMatch`) and
///   `havePlayedEachOther` (`HavePlayedEachOther`), answered by the application layer.
///
/// Transitions are non-mutating: each returns a new `Player` or a `PlayerError`.
public struct Player: Equatable, Identifiable, Sendable {
    public let id: PlayerId
    public private(set) var name: PlayerName
    public private(set) var colour: Colour
    public private(set) var status: PlayerStatus
    /// Set once this player has been merged away: the player they were folded into.
    public private(set) var mergedInto: PlayerId?
    /// Raised since load; the application layer dispatches then calls `clearingDomainEvents()`.
    public private(set) var domainEvents: [PlayerEvent]

    private init(
        id: PlayerId, name: PlayerName, colour: Colour, status: PlayerStatus,
        mergedInto: PlayerId?, domainEvents: [PlayerEvent]
    ) {
        self.id = id
        self.name = name
        self.colour = colour
        self.status = status
        self.mergedInto = mergedInto
        self.domainEvents = domainEvents
    }

    // MARK: Factory

    /// Adds a new, active player. `colour` is normally `Palette.standard.nextUnusedColour(given:)`.
    /// - Parameter sameNamed: any existing player with this name (case-insensitive), as found by the repository.
    public static func add(
        id: PlayerId, name: PlayerName, colour: Colour, sameNamed: Player?, at now: Date
    ) -> Result<Player, PlayerError> {
        if let clash = nameClash(for: name, sameNamed: sameNamed, excluding: nil) {
            return .failure(clash)
        }
        let added = PlayerAdded(playerId: id, name: name, colour: colour, occurredAt: now)
        return .success(Player(
            id: id, name: name, colour: colour, status: .active,
            mergedInto: nil, domainEvents: [.added(added)]
        ))
    }

    /// Rebuilds a player from storage. Runs no rules and raises no events.
    public static func reconstitute(
        id: PlayerId, name: PlayerName, colour: Colour, status: PlayerStatus, mergedInto: PlayerId?
    ) -> Player {
        Player(id: id, name: name, colour: colour, status: status, mergedInto: mergedInto, domainEvents: [])
    }

    // MARK: Behaviours

    /// Renames the player. The new name must not belong to another active or archived player.
    /// Changing only the case of the player's own name is allowed. An identical name is a no-op.
    public func rename(to newName: PlayerName, sameNamed: Player?, at now: Date) -> Result<Player, PlayerError> {
        guard status.holdsName else { return .failure(.playerNoLongerExists(status: status)) }
        if let clash = Player.nameClash(for: newName, sameNamed: sameNamed, excluding: id) {
            return .failure(clash)
        }
        guard newName.value != name.value else { return .success(self) }

        var next = self
        next.name = newName
        next.domainEvents.append(.renamed(PlayerRenamed(
            playerId: id, oldName: name, newName: newName, occurredAt: now
        )))
        return .success(next)
    }

    /// Changes the player's colour. Colours may repeat across players. The same colour is a no-op.
    public func changeColour(to newColour: Colour, at now: Date) -> Result<Player, PlayerError> {
        guard status.holdsName else { return .failure(.playerNoLongerExists(status: status)) }
        guard newColour != colour else { return .success(self) }

        var next = self
        next.colour = newColour
        next.domainEvents.append(.colourChanged(PlayerColourChanged(
            playerId: id, oldColour: colour, newColour: newColour, occurredAt: now
        )))
        return .success(next)
    }

    /// Folds this player into `kept`. Both must be active and must never have played each other.
    /// This player becomes MergedAway; `kept` is not changed here (its matches move via Matches' policy).
    public func mergeInto(_ kept: Player, havePlayedEachOther: Bool, at now: Date) -> Result<Player, PlayerError> {
        guard kept.id != id else { return .failure(.cannotMergeIntoSelf) }
        guard status.canTransition(to: .mergedAway) else {
            return .failure(.invalidTransition(from: status, to: .mergedAway))
        }
        guard kept.status == .active else {
            return .failure(.keptPlayerNotActive(kept.id, status: kept.status))
        }
        guard !havePlayedEachOther else { return .failure(.havePlayedEachOther(kept.id, id)) }

        var next = self
        next.status = .mergedAway
        next.mergedInto = kept.id
        next.domainEvents.append(.merged(PlayersMerged(
            keptPlayerId: kept.id, foldedInPlayerId: id, occurredAt: now
        )))
        return .success(next)
    }

    /// Archives an active player. Refused while they are in a live match.
    public func archive(isInLiveMatch: Bool, at now: Date) -> Result<Player, PlayerError> {
        guard status.canTransition(to: .archived) else {
            return .failure(.invalidTransition(from: status, to: .archived))
        }
        guard !isInLiveMatch else { return .failure(.inLiveMatch) }

        var next = self
        next.status = .archived
        next.domainEvents.append(.archived(PlayerArchived(playerId: id, occurredAt: now)))
        return .success(next)
    }

    /// Brings an archived player back to active.
    public func unarchive(at now: Date) -> Result<Player, PlayerError> {
        guard status == .archived else {
            return .failure(.invalidTransition(from: status, to: .active))
        }

        var next = self
        next.status = .active
        next.domainEvents.append(.unarchived(PlayerUnarchived(playerId: id, occurredAt: now)))
        return .success(next)
    }

    /// Permanently removes an archived player; their name becomes free.
    /// Confirmation is the application layer's concern.
    public func remove(at now: Date) -> Result<Player, PlayerError> {
        guard status.canTransition(to: .removed) else {
            return .failure(.invalidTransition(from: status, to: .removed))
        }

        var next = self
        next.status = .removed
        next.domainEvents.append(.removed(PlayerRemoved(playerId: id, occurredAt: now)))
        return .success(next)
    }

    /// Called by the application layer once the events have been dispatched.
    public func clearingDomainEvents() -> Player {
        var next = self
        next.domainEvents = []
        return next
    }

    // MARK: Invariant: names unique case-insensitively across active and archived players

    private static func nameClash(for name: PlayerName, sameNamed: Player?, excluding ownId: PlayerId?) -> PlayerError? {
        guard let other = sameNamed, other.id != ownId, other.name == name else { return nil }
        switch other.status {
        case .active: return .nameTaken(by: other.id)
        case .archived: return .nameHeldByArchivedPlayer(other.id)
        case .mergedAway, .removed: return nil
        }
    }
}
