import Foundation
import MatchesDomain
import StatsPublished

/// `FlagStaleMatches` and `ResolveStaleMatch` (S28). Load → `flagStale` / `resolveStale` → save →
/// dispatch → project, through `MatchUseCases`' own repository and `commit`, so the stale flow saves
/// and publishes exactly like every other match command.
///
/// The averages come from Stats' open host (`MatchStatsQueries`, ADR-0003): the winner of the last
/// frame's average frame time for the suggested end, and the pair's same-weekday average match length
/// for the cap (3 h when there is none).
@MainActor
public final class StaleMatchUseCases: StaleMatchCommands {
    private let matches: MatchUseCases
    private let stats: any MatchStatsQueries
    private let players: any MatchPlayerDirectory
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        matches: MatchUseCases, stats: any MatchStatsQueries, players: any MatchPlayerDirectory,
        calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.matches = matches
        self.stats = stats
        self.players = players
        self.calendar = calendar
        self.now = now
    }

    // MARK: FlagStaleMatches

    public func flagStaleMatches() throws -> [StaleMatchPrompt] {
        let at = now()
        var prompts: [StaleMatchPrompt] = []
        for match in try matches.repository.findLive() where match.isStale(at: at) {
            let winnerAverage = match.frames.last?.winner.player.ref
                .flatMap { stats.averageFrameTime($0) }
                .flatMap { try? PlayDuration.create(seconds: $0).get() }
            let suggested = match.suggestedStaleEndTime(winnerAverageFrameLength: winnerAverage, at: at)
            let (capped, fromHistory) = cappedLength(of: match)
            guard case .success(let flagged) = match.flagStale(at: at, suggestedEndTime: suggested, cappedLength: capped),
                  let id = match.id.uuid
            else { continue }
            try matches.commit(flagged)
            guard let event = flagged.uncommittedEvents.lazy.compactMap({ e -> StaleMatchFlagged? in
                if case .staleMatchFlagged(let f) = e { f } else { nil }
            }).first else { continue }
            prompts.append(prompt(id: id, match: match, flagged: event, fromHistory: fromHistory))
        }
        return prompts
    }

    // MARK: ResolveStaleMatch

    public func resolveStaleMatch(_ id: MatchID, _ choice: StaleChoice, anyway: Bool) throws {
        guard let match = try matches.repository.getById(id), match.status.isLive else {
            throw StaleMatchError.noLongerStale
        }
        let at = now()
        let resolution: StaleResolution
        switch choice {
        case .resume: resolution = .resume
        case .abandon: resolution = .abandon
        case .cancel: resolution = .cancel
        case .endCapped: resolution = .endCapped(cappedLength(of: match).length)
        case .endAt(let date):
            guard case .success(let end) = ChosenEndTime.create(date, lastAction: match.lastActionAt, now: at) else {
                throw StaleMatchError.endTimeOutOfBounds
            }
            resolution = .endAt(end)
        }
        switch match.resolveStale(resolution, at: at, anyway: anyway) {
        case .success(let changed):
            try matches.commit(changed)
        case .failure(.notStale), .failure(.notAllowed(.resolveStale, _)):
            throw StaleMatchError.noLongerStale
        case .failure(.invalidEndTime):
            throw StaleMatchError.endTimeOutOfBounds
        case .failure(let error):
            throw MatchCommandError(error)
        }
    }

    // MARK: Helpers

    /// The same two players' average length on the start's weekday, else the 3 h fallback.
    private func cappedLength(of match: Match) -> (length: CappedLength, fromHistory: Bool) {
        let weekday = calendar.component(.weekday, from: match.startTime.date)
        let average = match.setup.first.ref.flatMap { a in
            match.setup.second.ref.flatMap { b in stats.averageMatchLength(a, b, weekday: weekday) }
        }.flatMap { try? PlayDuration.create(seconds: $0).get() }
        return (CappedLength.from(samePairSameWeekdayAverage: average), average != nil)
    }

    private func prompt(id: MatchID, match: Match, flagged: StaleMatchFlagged, fromHistory: Bool) -> StaleMatchPrompt {
        let frames = [match.score.firstFrames, match.score.secondFrames]
        let sides = zip([match.first, match.second], frames).compactMap { side, count -> StaleMatchPrompt.Side? in
            guard let ref = side.player.ref else { return nil }
            let player = players.player(ref)
            return StaleMatchPrompt.Side(
                id: ref, name: player?.name ?? "Unknown player", colour: side.colour.name, frames: count)
        }
        return StaleMatchPrompt(
            id: id, sides: sides, score: match.score.description, startedAt: match.startTime.date,
            isPaused: match.status == .paused, idle: flagged.idle.seconds, ranFor: flagged.ranFor.seconds,
            cappedLength: flagged.cappedLength.length.seconds, cappedFromHistory: fromHistory,
            weekday: calendar.component(.weekday, from: match.startTime.date),
            suggestedEndTime: flagged.suggestedEndTime.date, earliestEndTime: match.lastActionAt,
            latestEndTime: flagged.at,
            canAbandonOrCancel: match.status.canTransition(to: .abandoned) && match.status.canTransition(to: .cancelled))
    }
}
