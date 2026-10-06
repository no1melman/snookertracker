import EventDispatch
import Foundation
import MatchesDomain
import PlayersPublished

// Matches-side reactions to Players' published events (spec 011, event map, S33, S34, S35, S42).
// Each policy subscribes to `PlayerEventPublished`, which Players dispatches on the main actor once
// the player is saved. A policy failure never undoes or blocks the player change, so each policy
// works item by item and carries on past a single failure.

/// The player events Matches reacts to, decoded from Players' published language (schema 1).
enum PlayerReaction: Equatable {
    case merged(kept: UUID, foldedIn: UUID)
    case archived(UUID)
    case unarchived(UUID)
    case removed(UUID)

    private struct MergedPayload: Decodable {
        let keptPlayerId: UUID
        let foldedInPlayerId: UUID
    }

    init?(_ published: PlayerEventPublished) {
        guard published.schemaVersion == 1 else { return nil }
        switch published.type {
        case "PlayersMerged":
            guard let p = try? JSONDecoder().decode(MergedPayload.self, from: published.payload) else { return nil }
            self = .merged(kept: p.keptPlayerId, foldedIn: p.foldedInPlayerId)
        case "PlayerArchived": self = .archived(published.playerId)
        case "PlayerUnarchived": self = .unarchived(published.playerId)
        case "PlayerRemoved": self = .removed(published.playerId)
        default: return nil
        }
    }
}

extension EventDispatcher {
    /// Subscribes `handle` on the main actor to the player events Matches reacts to.
    @MainActor func onPlayerReaction(_ handle: @escaping @MainActor (PlayerReaction) -> Void) {
        subscribe(PlayerEventPublished.self) { published in
            guard let reaction = PlayerReaction(published) else { return }
            MainActor.assumeIsolated { handle(reaction) }
        }
    }
}

/// `DeleteMatch` on `PlayerRemoved` (S42 → S30): each of the removed player's matches is deleted
/// through the ordinary use case, so `MatchDeleted` is stored and published as usual. A removed
/// player was archived first, so no match of theirs can be live; should one be, it is cancelled
/// first, and one that can be neither cancelled nor deleted is left as it is.
@MainActor
public final class DeleteMatchesOnPlayerRemoved {
    private let repository: any MatchRepository
    private let commands: any MatchCommands

    public init(repository: any MatchRepository, commands: any MatchCommands) {
        self.repository = repository
        self.commands = commands
    }

    public convenience init(matches: MatchUseCases) {
        self.init(repository: matches.repository, commands: matches)
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.onPlayerReaction { [weak self] reaction in
            guard case .removed(let player) = reaction else { return }
            self?.deleteMatches(of: player)
        }
    }

    public func deleteMatches(of player: PlayerRef) {
        guard let matches = try? repository.findByPlayer(player) else { return }
        for match in matches where match.status != .deleted {
            guard let id = match.id.uuid else { continue }
            if match.status.isLive { try? commands.cancelMatch(id) }
            try? commands.deleteMatch(id)
        }
    }
}

/// `MovePlayerMatches` on `PlayersMerged` (S33, ADR-0009): each of the folded-in player's matches is
/// repointed to the kept player (`Match.movePlayer`, raising `MatchPlayerMoved`), then saved, published
/// and projected like any other match change (`MatchUseCases.commit`). Live matches move too, so the
/// live screen shows the kept player. A deleted match is left as it is, and so is one the two played
/// together (the merge guard refuses that merge, so it can only come from a race).
@MainActor
public final class MovePlayerMatches {
    private let matches: MatchUseCases
    private let now: @Sendable () -> Date

    /// `now`: the same clock as `matches`.
    public init(matches: MatchUseCases, now: @escaping @Sendable () -> Date = Date.init) {
        self.matches = matches
        self.now = now
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.onPlayerReaction { [weak self] reaction in
            guard case .merged(let kept, let foldedIn) = reaction else { return }
            self?.moveMatches(from: foldedIn, to: kept)
        }
    }

    public func moveMatches(from foldedIn: PlayerRef, to kept: PlayerRef) {
        guard let found = try? matches.repository.findByPlayer(foldedIn) else { return }
        let (from, to) = (PlayerId(ref: foldedIn), PlayerId(ref: kept))
        for match in found {
            guard case .success(let moved) = match.movePlayer(from: from, to: to, at: now()) else { continue }
            try? matches.commit(moved)
        }
    }
}

/// `DeleteTemplate` on `PlayerRemoved` (S42): each of the removed player's templates goes.
@MainActor
public final class DeleteTemplatesOnPlayerRemoved {
    private let templates: TemplateUseCases

    public init(templates: TemplateUseCases) {
        self.templates = templates
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.onPlayerReaction { [weak self] reaction in
            guard case .removed(let player) = reaction else { return }
            try? self?.templates.deleteTemplates(of: player)
        }
    }
}

/// `CombineTemplatesAfterMerge` on `PlayersMerged` (S33): the folded-in player's templates move to
/// the kept player, and templates that become identical combine (use counts add).
@MainActor
public final class CombineTemplatesAfterMerge {
    private let templates: TemplateUseCases

    public init(templates: TemplateUseCases) {
        self.templates = templates
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.onPlayerReaction { [weak self] reaction in
            guard case .merged(let kept, let foldedIn) = reaction else { return }
            try? self?.templates.combineTemplatesAfterMerge(kept: kept, foldedIn: foldedIn)
        }
    }
}

/// `TemplateList` hides templates with an archived player (S34) and shows them again on unarchive
/// (S35). Read-side only: the templates themselves are untouched. Seed the projection with the
/// players already archived at launch (`TemplateListProjection.seedArchived`).
@MainActor
public final class HideArchivedPlayersTemplates {
    private let list: TemplateListProjection

    public init(list: TemplateListProjection) {
        self.list = list
    }

    public func subscribe(to dispatcher: EventDispatcher) {
        dispatcher.onPlayerReaction { [weak self] reaction in
            switch reaction {
            case .archived(let player): self?.list.hideTemplates(of: player)
            case .unarchived(let player), .removed(let player): self?.list.showTemplates(of: player)
            case .merged: break
            }
        }
    }
}
