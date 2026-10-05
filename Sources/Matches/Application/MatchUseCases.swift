import EventDispatch
import Foundation
import MatchesDomain
import MatchesPublished

/// The live-play use cases (spec 010) behind `MatchCommands`. Each one is
/// load → domain behaviour → save → dispatch Stage 2 events → update the read model.
@MainActor
public final class MatchUseCases: MatchCommands {
    let repository: any MatchRepository
    private let settings: MatchSettingsService
    private let players: any MatchPlayerDirectory
    private let readModel: LiveMatchesProjection
    private let dispatcher: EventDispatcher
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> UUID

    public init(
        repository: any MatchRepository, settings: MatchSettingsService, players: any MatchPlayerDirectory,
        readModel: LiveMatchesProjection, dispatcher: EventDispatcher,
        now: @escaping @Sendable () -> Date = Date.init, newID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.settings = settings
        self.players = players
        self.readModel = readModel
        self.dispatcher = dispatcher
        self.now = now
        self.newID = newID
    }

    /// Rebuilds the read model from the stored live matches (launch).
    public func loadLiveMatches() throws {
        readModel.load(try repository.findLive(), at: now())
    }

    // MARK: StartMatch

    public func startMatch(_ request: MatchSetup) throws -> MatchID {
        guard request.players.count == 2 else { throw MatchCommandError.samePlayerTwice }
        let style = try request.style.domain()
        guard case .success(let setup) = Setup.create(
            PlayerId(ref: request.players[0]), PlayerId(ref: request.players[1]),
            game: request.game.domain, style: style, breakRule: request.breakRule.domain)
        else { throw MatchCommandError.samePlayerTwice }

        let limit = settings.values.liveMatchLimit
        guard limit.allowsAnother(liveCount: try repository.findLive().count) else {
            throw MatchCommandError.liveMatchLimitReached(limit.value)
        }

        let id = newID()
        let match = Match.start(
            id: MatchId(id), setup: setup,
            firstColour: colour(of: request.players[0]), secondColour: colour(of: request.players[1]),
            at: now())
        try commit(match)
        return id
    }

    // MARK: Live play

    public func chooseBreaker(_ match: MatchID, player: PlayerRef) throws {
        try change(match) { $0.chooseBreaker(PlayerId(ref: player), at: $1) }
    }

    public func awardFrame(_ match: MatchID, to player: PlayerRef) throws {
        try change(match) { $0.awardFrame(to: PlayerId(ref: player), at: $1) }
    }

    public func removeFrame(_ match: MatchID, from player: PlayerRef) throws {
        try change(match) { $0.removeFrame(from: PlayerId(ref: player), at: $1) }
    }

    public func pauseMatch(_ match: MatchID) throws {
        try change(match) { $0.pause(at: $1) }
    }

    public func resumeMatch(_ match: MatchID) throws {
        try change(match) { $0.resume(at: $1) }
    }

    // MARK: Ending

    public func finishMatch(_ match: MatchID, anyway: Bool) throws {
        try change(match) { $0.finish(at: $1, anyway: anyway) }
    }

    public func abandonMatch(_ match: MatchID) throws {
        try change(match) { $0.abandon(at: $1) }
    }

    public func cancelMatch(_ match: MatchID) throws {
        try change(match) { $0.cancel(at: $1) }
    }

    // MARK: Plumbing

    private func change(_ id: MatchID, _ behaviour: (Match, Date) -> Result<Match, MatchError>) throws {
        guard let match = try repository.getById(id) else { throw MatchCommandError.notAllowedNow }
        switch behaviour(match, now()) {
        case .success(let changed): try commit(changed)
        case .failure(let error): throw MatchCommandError(error)
        }
    }

    /// save → dispatch → project. Events are dispatched only once they are stored.
    func commit(_ match: Match) throws {
        let recorded: [RecordedMatchEvent]
        do {
            recorded = try repository.save(match)
        } catch MatchRepositoryError.concurrencyConflict {
            throw MatchCommandError.changedElsewhere
        }
        readModel.project(match.committed(), at: now())
        dispatcher.dispatch(recorded.filter { MatchEventWire.isPublished($0.event) }.compactMap { Self.published($0, match: match.id) })
    }

    private static func published(_ r: RecordedMatchEvent, match: MatchId) -> MatchEventPublished? {
        guard let matchId = match.uuid, let wire = try? MatchEventWire.encode(r.event) else { return nil }
        return MatchEventPublished(
            matchId: matchId, eventId: r.eventId, originDevice: r.originDevice, streamVersion: r.streamVersion,
            type: wire.type, schemaVersion: wire.schemaVersion, payload: wire.payload, occurredAt: r.event.at)
    }

    private func colour(of player: PlayerRef) -> Colour {
        if case .success(let colour) = Colour.create(players.player(player)?.colour ?? "") { return colour }
        guard case .success(let gray) = Colour.create("gray") else { preconditionFailure("gray is a valid colour") }
        return gray
    }
}
