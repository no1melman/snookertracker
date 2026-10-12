import EventDispatch
import Foundation
import MatchesDomain
import Observation
import UpgradePublished

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
            let sets: LiveSide.SetsScore?
        }

        let id: MatchID
        let startedAt: Date
        let game: Game
        let style: MatchStyle
        let breakRule: BreakRule
        let sides: [Side]
        let breaker: PlayerRef?
        let status: MatchStatus
        let pauseKind: PauseKind?
        let matchTimer: TimerReading
        let frameTimer: TimerReading
        let targetReachedBy: PlayerRef?
        let setWon: SetWonPrompt?
        let coloursClash: Bool
        let hasBreaker: Bool
    }

    private let directory: any MatchPlayerDirectory
    private var rows: [MatchID: Row] = [:]
    /// Upgrade's `CurrentEdition` (ADR-0011): while Free the reads omit colours, lock head-to-head
    /// and pause, and offer no lock-screen state. Unlocked until the composition root hands it over.
    @ObservationIgnored public let edition: any CurrentEdition
    /// Bumped when the edition changes, so views reading these queries re-render (`CurrentEdition`
    /// itself is not observable).
    private var editionStamp = 0

    public init(players: any MatchPlayerDirectory, edition: any CurrentEdition = FixedEdition.unlocked) {
        self.directory = players
        self.edition = edition
    }

    /// The edition changed (`AppUnlocked` / `AppLocked`): every read is redrawn as it now applies.
    public func editionChanged() { editionStamp += 1 }

    /// Redraws on `AppUnlocked` and `AppLocked` (S49, S51).
    public func subscribeToEdition(_ dispatcher: EventDispatcher) {
        dispatcher.subscribe(AppUnlockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.editionChanged() }
        }
        dispatcher.subscribe(AppLockedPublished.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.editionChanged() }
        }
    }

    /// Free: no colours, so the colour-clash offer (S46) isn't made either.
    private var showsColours: Bool {
        _ = editionStamp
        return edition.allows(.colours)
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
        // A set was just won (the current set is back at 0–0 after a frame) and play carries on.
        var setWon: SetWonPrompt?
        if let s = score.sets, m.status == .inPlay, s.firstCurrentSetFrames == 0, s.secondCurrentSetFrames == 0,
           let last = m.frames.last, let winner = last.winner.player.ref {
            setWon = SetWonPrompt(winner: winner, setNumber: last.setNumber)
        }
        return Row(
            id: id,
            startedAt: m.startTime.date,
            game: Game(m.setup.game),
            style: MatchStyle(m.setup.style),
            breakRule: BreakRule(m.setup.breakRule),
            sides: [
                Row.Side(player: first, colour: m.sides[0].colour.name, frames: score.firstFrames,
                         sets: score.sets.map { .init(setsWon: $0.firstSets, currentSetFrames: $0.firstCurrentSetFrames) }),
                Row.Side(player: second, colour: m.sides[1].colour.name, frames: score.secondFrames,
                         sets: score.sets.map { .init(setsWon: $0.secondSets, currentSetFrames: $0.secondCurrentSetFrames) }),
            ],
            breaker: m.nextBreaker?.player.ref,
            status: m.status,
            pauseKind: m.pauseKind,
            matchTimer: timer(m.matchLength(at: now)),
            frameTimer: timer(m.frameLength(at: now)),
            targetReachedBy: m.status == .awaitingConfirmation ? (score.sets == nil ? leader : leaderBySets) : nil,
            setWon: setWon,
            coloursClash: m.status == .awaitingBreaker && m.sides[0].colour == m.sides[1].colour,
            hasBreaker: m.breakerOrigin != nil)
    }

    // MARK: Queries

    public var liveMatches: [LiveMatchRow] {
        _ = editionStamp
        return rows.values.sorted { $0.startedAt < $1.startedAt }.map { row in
            LiveMatchRow(id: row.id, sides: sides(row), matchTimer: row.matchTimer,
                         isPaused: row.status == .paused, startedAt: row.startedAt)
        }
    }

    public func liveMatchScreen(_ id: MatchID) -> LiveMatchScreen? {
        guard let row = rows[id] else { return nil }
        _ = editionStamp
        let manualPause = edition.allows(.manualPause)
        let scoring: Set<MatchStatus> = [.inPlay, .awaitingConfirmation]
        let controls = LiveMatchScreen.Controls(
            chooseBreaker: row.status == .awaitingBreaker,
            award: row.status == .inPlay,
            removeFrom: scoring.contains(row.status) ? Set(row.sides.filter { $0.frames > 0 }.map(\.player)) : [],
            pause: row.status == .awaitingBreaker || row.status == .inPlay,
            resume: row.status == .paused,
            correctBreaker: row.hasBreaker && (row.status == .inPlay || row.status == .paused),
            pauseOffersUpgrade: !manualPause,
            resumeOffersUpgrade: !manualPause && row.pauseKind == .byHand)
        return LiveMatchScreen(
            id: row.id, startedAt: row.startedAt, game: row.game, style: row.style, breakRule: row.breakRule,
            sides: sides(row), matchTimer: row.matchTimer, frameTimer: row.frameTimer,
            isPaused: row.status == .paused, controls: controls, targetReachedBy: row.targetReachedBy,
            setWon: row.setWon, coloursClash: row.coloursClash && showsColours,
            showsColours: showsColours, headToHeadLocked: !edition.allows(.headToHead))
    }

    /// Free: the colour is omitted (empty); it is kept on the match, just not shown (ADR-0010).
    private func sides(_ row: Row) -> [LiveSide] {
        let showsColours = showsColours
        return row.sides.map { side in
            LiveSide(id: side.player, name: directory.player(side.player)?.name ?? "?",
                     colour: showsColours ? side.colour : LiveSide.noColour,
                     frames: side.frames, isBreaker: row.breaker == side.player, sets: side.sets)
        }
    }
}
