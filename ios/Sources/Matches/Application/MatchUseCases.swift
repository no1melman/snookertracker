import EventDispatch
import Foundation
import MatchesDomain
import MatchesPublished

/// The live-play and maintenance use cases (specs 010, 015) behind `MatchCommands`. Each one is
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

    public func playersAlreadyLive(_ request: MatchSetup) throws -> [MatchPlayer] {
        let live = try repository.findLive()
        return request.players.filter { ref in
            live.contains { $0.setup.players.contains(PlayerId(ref: ref)) }
        }
        .map { players.player($0) ?? MatchPlayer(id: $0, name: "?", colour: "gray") }
    }

    // MARK: Live play

    public func chooseBreaker(_ match: MatchID, player: PlayerRef) throws {
        try change(match) { $0.chooseBreaker(PlayerId(ref: player), at: $1) }
    }

    public func correctBreaker(_ match: MatchID, player: PlayerRef) throws {
        try change(match) { $0.correctBreaker(PlayerId(ref: player), at: $1) }
    }

    public func overrideMatchColour(_ match: MatchID, of player: PlayerRef, to colour: String) throws {
        guard case .success(let colour) = Colour.create(colour) else { throw MatchCommandError.notAllowedNow }
        try change(match) { $0.overrideColour(of: PlayerId(ref: player), to: colour, at: $1) }
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

    // MARK: FinishAllMatches (S43)

    public func finishAllMatchesPreview() throws -> FinishAllPreview {
        let live = try repository.findLive()
        let abandoning = live.filter { isShortOfTarget($0) }.count
        return FinishAllPreview(finishing: live.count - abandoning, abandoning: abandoning)
    }

    /// Each match is its own transaction; a failure does not stop the rest, and the first is rethrown.
    public func finishAllMatches() throws {
        var firstError: (any Error)?
        for match in try repository.findLive() {
            let at = now()
            let ended = isShortOfTarget(match) ? match.abandon(at: at) : match.finish(at: at)
            do {
                switch ended {
                case .success(let changed): try commit(changed)
                case .failure(let error): throw MatchCommandError(error)
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    private func isShortOfTarget(_ match: Match) -> Bool {
        if case .failure(.finishShortOfTarget) = match.finish(at: now()) { return true }
        return false
    }

    // MARK: Maintenance (spec 015)

    public func deleteMatch(_ match: MatchID) throws {
        try change(match) { $0.delete(at: $1) }
    }

    /// One `MatchScoreCorrected` event: it is stored whole or not at all (Q1 default). A second
    /// correction builds on the first, and each is its own timeline entry (Q2 default).
    public func correctMatchScore(_ id: MatchID, to score: CorrectedScore, confirmed: Bool) throws {
        guard let match = try repository.getById(id) else { throw MatchCommandError.notAllowedNow }
        let correction = try score.domain(for: match.setup.style)
        switch match.correctScore(correction, at: now()) {
        case .failure(let error):
            throw MatchCommandError(error)
        case .success(let changed):
            if !correction.warnings.isEmpty, !confirmed {
                throw MatchCommandError.correctionNeedsConfirmation(correction.warnings.map(\.text))
            }
            try commit(changed)
        }
    }

    public func markMatchFinished(_ match: MatchID) throws {
        try change(match) { $0.markFinished(at: $1) }
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
