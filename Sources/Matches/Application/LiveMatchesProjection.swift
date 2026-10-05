import Foundation
import MatchesDomain
import Observation

/// The live-match read models (spec 009): `LiveMatches` and `LiveMatchScreen`.
///
/// A projection: it keeps a flat row per live match, rebuilt from the repository at launch
/// (`load`) and replaced after every saved change (`project`). Queries never touch an aggregate;
/// names are resolved at read time from the Players supplier, so a rename shows straight away.
@MainActor @Observable
public final class LiveMatchesProjection: LiveMatchesQuery, LiveMatchScreenQuery {
    /// The flattened state of one live match.
    struct Row: Hashable {
        struct Side: Hashable {
            let player: PlayerRef
            let colour: String
            let frames: Int
        }

        let id: MatchID
        let startedAt: Date
        let game: Game
        let style: MatchStyle
        let breakRule: BreakRule
        let sides: [Side]
        let breaker: PlayerRef?
        let status: MatchStatus
        let matchTimer: TimerReading
        let frameTimer: TimerReading
        let targetReachedBy: PlayerRef?
    }

    private let directory: any MatchPlayerDirectory
    private var rows: [MatchID: Row] = [:]

    public init(players: any MatchPlayerDirectory) {
        self.directory = players
    }

    // MARK: Keeping it current

    /// Replaces every row with the given live matches (launch).
    public func load(_ matches: [Match], at now: Date) {
        rows = [:]
        for match in matches { project(match, at: now) }
    }

    /// Updates one match's row after a save; an ended match leaves the read model.
    public func project(_ match: Match, at now: Date) {
        guard let id = match.id.uuid else { return }
        guard match.status.isLive, let row = Self.row(match, at: now) else {
            rows[id] = nil
            return
        }
        rows[id] = row
    }

    static func row(_ m: Match, at now: Date) -> Row? {
        guard let id = m.id.uuid, let first = m.sides[0].player.ref, let second = m.sides[1].player.ref else { return nil }
        let running = m.status != .paused
        func timer(_ length: PlayDuration) -> TimerReading {
            // Anchored at `now`: frozen while paused, else counting on from the stored timestamps.
            TimerReading(accumulated: length.seconds, runningSince: running ? now : nil)
        }
        let score = m.score
        let leader: PlayerRef? = score.firstFrames == score.secondFrames
            ? nil : (score.firstFrames > score.secondFrames ? first : second)
        let leaderBySets: PlayerRef? = score.sets.flatMap { s in
            s.firstSets == s.secondSets ? nil : (s.firstSets > s.secondSets ? first : second)
        }
        return Row(
            id: id,
            startedAt: m.startTime.date,
            game: Game(m.setup.game),
            style: MatchStyle(m.setup.style),
            breakRule: BreakRule(m.setup.breakRule),
            sides: [
                Row.Side(player: first, colour: m.sides[0].colour.name, frames: score.firstFrames),
                Row.Side(player: second, colour: m.sides[1].colour.name, frames: score.secondFrames),
            ],
            breaker: m.nextBreaker?.player.ref,
            status: m.status,
            matchTimer: timer(m.matchLength(at: now)),
            frameTimer: timer(m.frameLength(at: now)),
            targetReachedBy: m.status == .awaitingConfirmation ? (score.sets == nil ? leader : leaderBySets) : nil)
    }

    // MARK: Queries

    public var liveMatches: [LiveMatchRow] {
        rows.values.sorted { $0.startedAt < $1.startedAt }.map { row in
            LiveMatchRow(id: row.id, sides: sides(row), matchTimer: row.matchTimer,
                         isPaused: row.status == .paused, startedAt: row.startedAt)
        }
    }

    public func liveMatchScreen(_ id: MatchID) -> LiveMatchScreen? {
        guard let row = rows[id] else { return nil }
        let scoring: Set<MatchStatus> = [.inPlay, .awaitingConfirmation]
        let controls = LiveMatchScreen.Controls(
            chooseBreaker: row.status == .awaitingBreaker,
            award: row.status == .inPlay,
            removeFrom: scoring.contains(row.status) ? Set(row.sides.filter { $0.frames > 0 }.map(\.player)) : [],
            pause: row.status == .awaitingBreaker || row.status == .inPlay,
            resume: row.status == .paused)
        return LiveMatchScreen(
            id: row.id, startedAt: row.startedAt, game: row.game, style: row.style, breakRule: row.breakRule,
            sides: sides(row), matchTimer: row.matchTimer, frameTimer: row.frameTimer,
            isPaused: row.status == .paused, controls: controls, targetReachedBy: row.targetReachedBy)
    }

    private func sides(_ row: Row) -> [LiveSide] {
        row.sides.map { side in
            LiveSide(id: side.player, name: directory.player(side.player)?.name ?? "?", colour: side.colour,
                     frames: side.frames, isBreaker: row.breaker == side.player)
        }
    }
}
