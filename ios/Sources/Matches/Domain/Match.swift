import Foundation

/// The behaviours of a match, for error reporting.
public enum MatchAction: String, Hashable, Sendable, Codable, CaseIterable {
    case chooseBreaker
    case correctBreaker
    case awardFrame
    case removeFrame
    case pause
    case autoPause
    case resume
    case overrideColour
    case finish
    case abandon
    case cancel
    case flagStale
    case resolveStale
    case warnLongFrame
    case correctScore
    case markFinished
    case delete
    case movePlayer
}

public enum MatchError: Error, Equatable, Sendable {
    /// The action is not allowed in the match's current status (incl. anything but the allowed few while paused).
    case notAllowed(MatchAction, status: MatchStatus)
    case playerNotInMatch(PlayerId)
    /// − on a side with no frames.
    case noFrameToRemove(PlayerId)
    /// No breaker has been chosen yet, so there is nothing to correct.
    case noBreakerToCorrect
    /// A temporary colour is only offered when both sides share a colour.
    case coloursAlreadyDiffer
    /// The temporary colour must differ from the shared one.
    case overrideColourNotDifferent(Colour)
    /// An automatic pause can't be placed before the match's last recorded action.
    case pauseBeforeLastAction(pauseAt: Date, lastActionAt: Date)
    /// A race-to or sets match short of its target: finishing it now means it will be abandoned,
    /// unless finished anyway.
    case finishShortOfTarget
    /// Stale-match handling needs the last action to be at least 6 h ago.
    case notStale(idle: PlayDuration)
    /// A stale match's chosen end time is outside last action ≤ t ≤ now.
    case invalidEndTime(ChosenEndTimeError)
    /// The current frame hasn't reached the next long-frame threshold yet.
    case longFrameThresholdNotReached(next: PlayDuration, elapsed: PlayDuration)
    /// The correction is invalid for this match's style.
    case invalidScoreCorrection(ScoreCorrectionError)
}

public enum MatchHistoryError: Error, Equatable, Sendable {
    case empty
    case doesNotBeginWithMatchStarted
}

/// Where the break rule counts from: the player breaking `frameNumber`. Set by choosing or correcting the breaker.
public struct BreakerOrigin: Hashable, Sendable, Codable {
    public let player: PlayerId
    public let frameNumber: Int
}

/// A pause, closed when the match resumes.
public struct Pause: Hashable, Sendable, Codable {
    public let startedAt: Date
    public let endedAt: Date?
    public let isAutomatic: Bool
}

/// The Match aggregate, event-sourced.
///
/// Every behaviour is non-mutating: it checks its guards, builds the events, applies them to a copy and
/// returns that copy with the events added to `uncommittedEvents`. State is only ever changed by
/// `applying(_:)`, so `Match.rehydrate(history)` rebuilds exactly the same match.
public struct Match: Hashable, Sendable, Identifiable {
    public let id: MatchId
    /// As started; only a player merge (`MatchPlayerMoved`) changes who is in it.
    public private(set) var setup: Setup
    public let startTime: StartTime
    public private(set) var first: Side
    public private(set) var second: Side
    public private(set) var status: MatchStatus
    public private(set) var breakerOrigin: BreakerOrigin?
    public private(set) var frames: [Frame]
    /// When the current frame's timer started: match start for frame 1, else the previous +. Never moved by −.
    public private(set) var currentFrameStartedAt: Date
    public private(set) var pauses: [Pause]
    public private(set) var lastActionAt: Date
    /// Set when the match ends as finished (or is marked finished); recalculated by a score correction.
    public private(set) var result: MatchResult?
    /// When the match ended: finished, abandoned or cancelled.
    public private(set) var endedAt: Date?
    /// The match length recorded at the end (capped for a stale match ended that way).
    public private(set) var finalLength: PlayDuration?
    /// The latest score correction of the ended match, if any; the score and frames follow it.
    public private(set) var scoreCorrection: ScoreCorrection?
    /// The current frame's length at its last long-frame warning; nil until warned.
    private var lastLongFrameWarning: PlayDuration?
    /// Events raised since the match was loaded or last committed.
    public private(set) var uncommittedEvents: [MatchEvent]
    /// Number of events in the stored history this match was rebuilt from (the expected version on save).
    public private(set) var version: Int

    private init(started e: MatchStarted) {
        id = e.matchId
        setup = e.setup
        startTime = StartTime(e.at)
        first = e.first
        second = e.second
        status = .awaitingBreaker
        breakerOrigin = nil
        frames = []
        currentFrameStartedAt = e.at
        pauses = []
        lastActionAt = e.at
        result = nil
        endedAt = nil
        finalLength = nil
        scoreCorrection = nil
        lastLongFrameWarning = nil
        uncommittedEvents = []
        version = 0
    }

    // MARK: - Factory

    /// Starts a live match at 0–0, awaiting its first breaker, with the match and frame-1 timers starting at `at`.
    /// Distinct players and valid targets are guaranteed by `Setup` and `Target`.
    /// Colours are the players' current colours, supplied by the caller.
    public static func start(id: MatchId, setup: Setup, firstColour: Colour, secondColour: Colour, at: Date) -> Match {
        let started = MatchStarted(
            matchId: id, setup: setup,
            first: Side(player: setup.first, colour: firstColour),
            second: Side(player: setup.second, colour: secondColour),
            at: at)
        var match = Match(started: started)
        match.uncommittedEvents = [.matchStarted(started)]
        return match
    }

    // MARK: - Event sourcing

    /// Rebuilds a match from its stored history; `version` becomes the history's length.
    public static func rehydrate(_ history: [MatchEvent]) -> Result<Match, MatchHistoryError> {
        guard let head = history.first else { return .failure(.empty) }
        guard case .matchStarted(let started) = head else { return .failure(.doesNotBeginWithMatchStarted) }
        var match = history.dropFirst().reduce(Match(started: started)) { $0.applying($1) }
        match.version = history.count
        return .success(match)
    }

    /// Clears the uncommitted events once they are stored, advancing `version`.
    public func committed() -> Match {
        var copy = self
        copy.version += uncommittedEvents.count
        copy.uncommittedEvents = []
        return copy
    }

    /// Pure and total: applies one event to the state. No rules are checked here.
    public func applying(_ event: MatchEvent) -> Match {
        var m = self
        if event.isAction { m.lastActionAt = max(lastActionAt, event.at) }
        switch event {
        case .matchStarted:
            break  // only ever the first event; handled by `rehydrate`
        case .breakerChosen(let e):
            m.breakerOrigin = BreakerOrigin(player: e.player, frameNumber: frames.count + 1)
            m.status = .inPlay
        case .breakerCorrected(let e):
            m.breakerOrigin = BreakerOrigin(player: e.player, frameNumber: e.frameNumber)
        case .frameWon(let e):
            guard let winner = side(of: e.player) else { break }
            let frame = Frame(
                winner: winner, number: 0, setNumber: 0, length: e.length,
                breaker: e.breaker.flatMap(side(of:)), wonAt: e.at)
            m.frames = Tally.renumber(frames + [frame], setup: setup)
            m.currentFrameStartedAt = e.at
            m.lastLongFrameWarning = nil
            m.status = .inPlay
        case .setWon:
            break  // a consequence of the frame; the tally derives it
        case .matchTargetReached:
            m.status = .awaitingConfirmation
        case .frameRemoved(let e):
            guard let index = frames.lastIndex(where: { $0.winner.player == e.player }) else { break }
            var remaining = frames
            remaining.remove(at: index)
            m.frames = Tally.renumber(remaining, setup: setup)
            if m.status == .awaitingConfirmation, !m.isMatchTargetReached { m.status = .inPlay }
        case .matchPaused(let e):
            m.pauses.append(Pause(startedAt: e.at, endedAt: nil, isAutomatic: false))
            m.status = .paused
        case .matchAutoPaused(let e):
            m.pauses.append(Pause(startedAt: e.at, endedAt: nil, isAutomatic: true))
            m.status = .paused
        case .matchResumed(let e):
            if let last = m.pauses.last, last.endedAt == nil {
                m.pauses[m.pauses.count - 1] = Pause(startedAt: last.startedAt, endedAt: e.at, isAutomatic: last.isAutomatic)
            }
            // Resuming a stale match that wasn't paused only records the action.
            if status == .paused { m.status = breakerOrigin == nil ? .awaitingBreaker : .inPlay }
        case .matchColourOverridden(let e):
            if first.player == e.player { m.first = first.recoloured(e.colour) }
            if second.player == e.player { m.second = second.recoloured(e.colour) }
        case .matchFinished(let e):
            m.result = e.result
            m.endedAt = e.endedAt
            m.finalLength = e.length
            m.status = .finished
        case .matchAbandoned(let e):
            m.endedAt = e.endedAt
            m.finalLength = e.length
            m.status = .abandoned
        case .matchCancelled(let e):
            m.endedAt = e.at
            m.status = .cancelled
        case .staleMatchFlagged:
            break  // drives the prompt only
        case .longFrameWarned(let e):
            m.lastLongFrameWarning = e.elapsed
        case .matchScoreCorrected(let e):
            m.scoreCorrection = e.correction
            m.frames = correctedFrames(e.correction)
            if status == .finished { m.result = e.result }
        case .matchMarkedFinished(let e):
            m.result = e.result
            m.status = .finished
        case .matchDeleted:
            m.status = .deleted
        case .matchPlayerMoved(let e):
            m = movingPlayer(from: e.from, to: e.to)
        }
        return m
    }

    /// Every reference to `from` (setup, sides, frames, breaker origin, result) becomes `to`.
    /// Total: an event that doesn't fit the match leaves it as it is.
    private func movingPlayer(from: PlayerId, to: PlayerId) -> Match {
        let repoint = { (id: PlayerId) in id == from ? to : id }
        let move = { (side: Side) in Side(player: repoint(side.player), colour: side.colour) }
        guard case .success(let moved) = Setup.create(
            repoint(setup.first), repoint(setup.second),
            game: setup.game, style: setup.style, breakRule: setup.breakRule)
        else { return self }
        var m = self
        m.setup = moved
        m.first = move(first)
        m.second = move(second)
        m.frames = frames.map {
            Frame(winner: move($0.winner), number: $0.number, setNumber: $0.setNumber,
                  length: $0.length, breaker: $0.breaker.map(move), wonAt: $0.wonAt)
        }
        m.breakerOrigin = breakerOrigin.map { BreakerOrigin(player: repoint($0.player), frameNumber: $0.frameNumber) }
        if case .win(let side) = result { m.result = .win(move(side)) }
        return m
    }

    private func raising(_ events: [MatchEvent]) -> Match {
        var m = self
        for event in events {
            m = m.applying(event)
            m.uncommittedEvents.append(event)
        }
        return m
    }

    private func guardStatus(_ action: MatchAction, in allowed: Set<MatchStatus>) -> MatchError? {
        allowed.contains(status) ? nil : .notAllowed(action, status: status)
    }

    // MARK: - Behaviours

    /// Chooses the first breaker. Nothing else but pausing is possible until then.
    public func chooseBreaker(_ player: PlayerId, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.chooseBreaker, in: [.awaitingBreaker]) { return .failure(e) }
        guard side(of: player) != nil else { return .failure(.playerNotInMatch(player)) }
        return .success(raising([.breakerChosen(BreakerChosen(player: player, at: at))]))
    }

    /// Sets who is breaking now; the break rule carries on from them. Allowed while paused.
    public func correctBreaker(_ player: PlayerId, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.correctBreaker, in: [.inPlay, .paused]) { return .failure(e) }
        guard breakerOrigin != nil else { return .failure(.noBreakerToCorrect) }
        guard side(of: player) != nil else { return .failure(.playerNotInMatch(player)) }
        return .success(raising([.breakerCorrected(
            BreakerCorrected(player: player, frameNumber: frames.count + 1, at: at))]))
    }

    /// + : the player wins the current frame. Raises `SetWon` on a set target and `MatchTargetReached`
    /// (→ AwaitingConfirmation) on the match target.
    public func awardFrame(to player: PlayerId, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.awardFrame, in: [.inPlay]) { return .failure(e) }
        guard side(of: player) != nil else { return .failure(.playerNotInMatch(player)) }

        let won = FrameWon(
            player: player,
            frameNumber: frames.count + 1,
            setNumber: tally.currentSetNumber,
            length: frameLength(at: at),
            breaker: nextBreaker?.player,
            at: at)
        var events: [MatchEvent] = [.frameWon(won)]
        let after = applying(.frameWon(won))
        let afterTally = after.tally
        if let setWin = afterTally.setWins.last, setWin.frameIndex == after.frames.count - 1 {
            events.append(.setWon(SetWon(player: player, setNumber: setWin.setNumber, setScore: setWin.score, at: at)))
        }
        if after.isMatchTargetReached {
            events.append(.matchTargetReached(MatchTargetReached(player: player, score: after.score, at: at)))
        }
        return .success(raising(events))
    }

    /// − : removes the player's most recent frame, reverting any set win it caused. Never touches the timers.
    public func removeFrame(from player: PlayerId, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.removeFrame, in: [.inPlay, .awaitingConfirmation]) { return .failure(e) }
        guard side(of: player) != nil else { return .failure(.playerNotInMatch(player)) }
        guard let index = frames.lastIndex(where: { $0.winner.player == player }) else {
            return .failure(.noFrameToRemove(player))
        }
        let frame = frames[index]
        let reverted = tally.setWins.first(where: { $0.frameIndex == index })?.setNumber
        return .success(raising([.frameRemoved(FrameRemoved(
            player: player, frameNumber: frame.number, setNumber: frame.setNumber,
            revertedSetWin: reverted, at: at))]))
    }

    /// The scorer pauses the match.
    public func pause(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.pause, in: [.awaitingBreaker, .inPlay]) { return .failure(e) }
        return .success(raising([.matchPaused(MatchPaused(at: at))]))
    }

    /// Pauses after the app was killed, at a supplied time that may be earlier than now but never
    /// before the last recorded action (ADR-0004, ADR-0005).
    public func autoPause(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.autoPause, in: [.awaitingBreaker, .inPlay]) { return .failure(e) }
        guard at >= lastActionAt else { return .failure(.pauseBeforeLastAction(pauseAt: at, lastActionAt: lastActionAt)) }
        return .success(raising([.matchAutoPaused(MatchAutoPaused(at: at))]))
    }

    /// Resumes to InPlay, or to AwaitingBreaker if no breaker has been chosen yet.
    public func resume(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.resume, in: [.paused]) { return .failure(e) }
        return .success(raising([.matchResumed(MatchResumed(at: at))]))
    }

    /// Gives one side a different colour for this match only, when both sides share a colour.
    /// The colour (picked at random from the palette) is chosen by the caller, keeping the domain deterministic.
    public func overrideColour(of player: PlayerId, to colour: Colour, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.overrideColour, in: [.awaitingBreaker]) { return .failure(e) }
        guard side(of: player) != nil else { return .failure(.playerNotInMatch(player)) }
        guard first.colour == second.colour else { return .failure(.coloursAlreadyDiffer) }
        guard colour != first.colour else { return .failure(.overrideColourNotDifferent(colour)) }
        return .success(raising([.matchColourOverridden(MatchColourOverridden(player: player, colour: colour, at: at))]))
    }

    /// Ends the match as finished (S10). Most frames wins may finish any time; level is a draw.
    /// Race to and sets finish from AwaitingConfirmation, ending at the winning frame's time; short of
    /// the target they refuse with `.finishShortOfTarget` ("will be abandoned") unless `anyway`, and
    /// whoever is ahead wins. A frame in progress is dropped: only won frames count.
    public func finish(at: Date, anyway: Bool = false) -> Result<Match, MatchError> {
        finishing(at: at, anyway: anyway, endedAt: nil, cappedLength: nil)
    }

    /// Ends the match as abandoned (S25): it doesn't count in stats.
    public func abandon(at: Date) -> Result<Match, MatchError> {
        if let e = guardTransition(.abandon, to: .abandoned) { return .failure(e) }
        return .success(raising([.matchAbandoned(MatchAbandoned(
            score: score, endedAt: at, length: matchLength(at: at), at: at))]))
    }

    /// Ends the match as cancelled (S26): as if it never happened, and it never changes again (except deletion).
    public func cancel(at: Date) -> Result<Match, MatchError> {
        if let e = guardTransition(.cancel, to: .cancelled) { return .failure(e) }
        return .success(raising([.matchCancelled(MatchCancelled(at: at))]))
    }

    /// Flags a live match idle for 6 h or more (S28), for the stale prompt. The suggested end time
    /// (see `suggestedStaleEndTime`) is kept within last action ≤ t ≤ now; the capped length comes from Stats.
    public func flagStale(at: Date, suggestedEndTime: Date, cappedLength: CappedLength) -> Result<Match, MatchError> {
        guard status.isLive else { return .failure(.notAllowed(.flagStale, status: status)) }
        guard isStale(at: at) else { return .failure(.notStale(idle: idleTime(at: at))) }
        let suggested = ChosenEndTime.create(
            min(max(suggestedEndTime, lastActionAt), at), lastAction: lastActionAt, now: at)
        guard case .success(let end) = suggested else { return .failure(.notStale(idle: idleTime(at: at))) }
        return .success(raising([.staleMatchFlagged(StaleMatchFlagged(
            idle: idleTime(at: at), ranFor: matchLength(at: at),
            suggestedEndTime: end, cappedLength: cappedLength, at: at))]))
    }

    /// Carries out the scorer's choice in the stale prompt (S28): resume, finish at a chosen time,
    /// finish with a capped length (the only way a length is ever capped), abandon or cancel.
    /// `anyway` is passed to `finish` for a target style short of its target.
    public func resolveStale(_ resolution: StaleResolution, at: Date, anyway: Bool = false) -> Result<Match, MatchError> {
        guard status.isLive else { return .failure(.notAllowed(.resolveStale, status: status)) }
        guard isStale(at: at) else { return .failure(.notStale(idle: idleTime(at: at))) }
        switch resolution {
        case .resume:
            if status == .paused { return resume(at: at) }
            return .success(raising([.matchResumed(MatchResumed(at: at))]))
        case .endAt(let chosen):
            switch ChosenEndTime.create(chosen.date, lastAction: lastActionAt, now: at) {
            case .failure(let e): return .failure(.invalidEndTime(e))
            case .success(let end): return finishing(at: at, anyway: anyway, endedAt: end.date, cappedLength: nil)
            }
        case .endCapped(let capped):
            // Ends when play last happened; only the length is capped.
            return finishing(at: at, anyway: anyway, endedAt: lastActionAt, cappedLength: capped)
        case .abandon:
            return abandon(at: at)
        case .cancel:
            return cancel(at: at)
        }
    }

    /// Warns that the current frame is running long (S37): at 30 min (minus paused time), then every 10 min.
    public func warnLongFrame(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.warnLongFrame, in: [.inPlay]) { return .failure(e) }
        let elapsed = frameLength(at: at), threshold = nextLongFrameWarning
        guard elapsed >= threshold else {
            return .failure(.longFrameThresholdNotReached(next: threshold, elapsed: elapsed))
        }
        return .success(raising([.longFrameWarned(LongFrameWarned(
            frameNumber: frames.count + 1, threshold: threshold, elapsed: elapsed, at: at))]))
    }

    /// Corrects a finished or abandoned match's score (S29) as a new event; the original events stay.
    /// Kept frames keep their details; added frames have no time, length or breaker. A finished match's
    /// winner is recalculated. Sets inconsistencies are the correction's warnings, never refusals.
    public func correctScore(_ correction: ScoreCorrection, at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.correctScore, in: [.finished, .abandoned]) { return .failure(e) }
        let revalidated: Result<ScoreCorrection, ScoreCorrectionError>
        switch correction.scores {
        case .frames(let f, let s): revalidated = ScoreCorrection.frames(first: f, second: s, for: setup.style)
        case .sets(let perSet): revalidated = ScoreCorrection.sets(perSet, for: setup.style)
        }
        if case .failure(let e) = revalidated { return .failure(.invalidScoreCorrection(e)) }
        let after = correctedScore(correction)
        return .success(raising([.matchScoreCorrected(MatchScoreCorrected(
            before: score, after: after, correction: correction,
            result: status == .finished ? leader(of: after) : nil, at: at))]))
    }

    /// Turns an abandoned match into a finished one (S31): whoever is ahead wins, level is a draw.
    public func markFinished(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.markFinished, in: [.abandoned]) { return .failure(e) }
        return .success(raising([.matchMarkedFinished(MatchMarkedFinished(result: leader(of: score), at: at))]))
    }

    /// Deletes an ended match (S30, S42).
    public func delete(at: Date) -> Result<Match, MatchError> {
        if let e = guardStatus(.delete, in: [.finished, .abandoned, .cancelled]) { return .failure(e) }
        return .success(raising([.matchDeleted(MatchDeleted(at: at))]))
    }

    /// After a player merge (S33, ADR-0009): the folded-in player `from` becomes the kept player `to`
    /// everywhere in the match. A correction, not play: allowed in every status but deleted (live
    /// included), the side keeps this match's colour and the idle time is not reset. Refused when `to`
    /// is already in the match, since they would play themselves.
    public func movePlayer(from: PlayerId, to: PlayerId, at: Date) -> Result<Match, MatchError> {
        guard status != .deleted else { return .failure(.notAllowed(.movePlayer, status: status)) }
        guard side(of: from) != nil else { return .failure(.playerNotInMatch(from)) }
        guard side(of: to) == nil else { return .failure(.notAllowed(.movePlayer, status: status)) }
        return .success(raising([.matchPlayerMoved(MatchPlayerMoved(from: from, to: to, at: at))]))
    }

    /// `endedAt`: an explicit end (stale match); nil to end at `at`, or at the winning frame from
    /// AwaitingConfirmation. `cappedLength`: only ever passed by `resolveStale`.
    private func finishing(at: Date, anyway: Bool, endedAt explicitEnd: Date?, cappedLength: CappedLength?) -> Result<Match, MatchError> {
        if let e = guardTransition(.finish, to: .finished) { return .failure(e) }
        let shortOfTarget: Bool
        switch setup.style {
        case .mostFramesWins: shortOfTarget = false
        case .raceTo, .sets: shortOfTarget = !isMatchTargetReached
        }
        if shortOfTarget, !anyway { return .failure(.finishShortOfTarget) }
        let end = explicitEnd
            ?? (status == .awaitingConfirmation ? frames.last?.wonAt : nil)
            ?? at
        return .success(raising([.matchFinished(MatchFinished(
            result: leader(of: score), score: score, endedAt: end,
            length: cappedLength?.length ?? matchLength(at: end),
            shortOfTarget: shortOfTarget, at: at))]))
    }

    private func guardTransition(_ action: MatchAction, to next: MatchStatus) -> MatchError? {
        status.canTransition(to: next) ? nil : .notAllowed(action, status: status)
    }

    /// Whoever is ahead wins; level is a draw. Sets: sets won, then current-set frames.
    func leader(of score: Score) -> MatchResult {
        let a: (Int, Int), b: (Int, Int)
        if let s = score.sets {
            a = (s.firstSets, s.firstCurrentSetFrames); b = (s.secondSets, s.secondCurrentSetFrames)
        } else {
            a = (score.firstFrames, 0); b = (score.secondFrames, 0)
        }
        if a == b { return .draw }
        return .win(a > b ? first : second)
    }

    /// Frames for a corrected score: per side (and per set), that side's earliest frames are kept up to
    /// the corrected count and the rest are added as corrected-in frames.
    func correctedFrames(_ correction: ScoreCorrection) -> [Frame] {
        func build(_ pool: [Frame], firstCount: Int, secondCount: Int) -> [Frame] {
            let firstKept = pool.filter { $0.winner.player == first.player }.prefix(firstCount)
            let secondKept = pool.filter { $0.winner.player == second.player }.prefix(secondCount)
            let kept = pool.filter { f in firstKept.contains(f) || secondKept.contains(f) }
            let added = { (side: Side, n: Int) in
                (0..<max(0, n)).map { _ in Frame(winner: side, number: 0, setNumber: 0, length: nil, breaker: nil, wonAt: nil) }
            }
            return kept + added(first, firstCount - firstKept.count) + added(second, secondCount - secondKept.count)
        }
        let perSet: [[Frame]]
        switch correction.scores {
        case .frames(let f, let s):
            perSet = [build(frames, firstCount: f, secondCount: s)]
        case .sets(let sets):
            perSet = sets.enumerated().map { i, set in
                build(frames.filter { $0.setNumber == i + 1 }, firstCount: set.first, secondCount: set.second)
            }
        }
        var number = 0
        return perSet.enumerated().flatMap { i, set in
            set.map { frame in
                number += 1
                return frame.renumbered(number: number, setNumber: i + 1)
            }
        }
    }

    /// The score a correction gives. Sets: a set counts for the side on the frames target with the
    /// other below it; an unwon last set is the current set.
    func correctedScore(_ correction: ScoreCorrection) -> Score {
        switch correction.scores {
        case .frames(let f, let s):
            return Score(firstFrames: f, secondFrames: s)
        case .sets(let sets):
            guard case .sets(_, let framesTarget) = setup.style else { return Score(firstFrames: 0, secondFrames: 0) }
            let n = framesTarget.value
            let firstSets = sets.filter { $0.first == n && $0.second < n }.count
            let secondSets = sets.filter { $0.second == n && $0.first < n }.count
            let current = sets.last.flatMap { last in
                (last.first == n) != (last.second == n) && max(last.first, last.second) == n ? nil : last
            }
            return Score(
                firstFrames: sets.reduce(0) { $0 + $1.first }, secondFrames: sets.reduce(0) { $0 + $1.second },
                sets: Score.Sets(
                    firstSets: firstSets, secondSets: secondSets,
                    firstCurrentSetFrames: current?.first ?? 0, secondCurrentSetFrames: current?.second ?? 0))
        }
    }

    // MARK: - Derived state

    /// A live match is stale once its last action is 6 h or more ago.
    public static let staleAfter: PlayDuration = .hours(6)
    public static let firstLongFrameWarning: PlayDuration = .minutes(30)
    public static let longFrameWarningInterval: PlayDuration = .minutes(10)

    /// Time since the last recorded action (score change, breaker choice, pause or resume).
    public func idleTime(at now: Date) -> PlayDuration {
        PlayDuration.elapsed(from: lastActionAt, to: now, minusPaused: 0)
    }

    public func isStale(at now: Date) -> Bool { status.isLive && idleTime(at: now) >= Self.staleAfter }

    /// The stale prompt's suggested end: the last frame's time plus the average frame length of whoever
    /// won it (from Stats; this match's own average for them if nil), within last action ≤ t ≤ now.
    public func suggestedStaleEndTime(winnerAverageFrameLength: PlayDuration?, at now: Date) -> Date {
        guard let last = frames.last, let wonAt = last.wonAt else { return min(lastActionAt, now) }
        let theirs = frames.filter { $0.winner.player == last.winner.player }.compactMap(\.length)
        let average = winnerAverageFrameLength?.seconds
            ?? (theirs.isEmpty ? 0 : theirs.reduce(0) { $0 + $1.seconds } / Double(theirs.count))
        return min(max(wonAt.addingTimeInterval(average), lastActionAt), max(now, lastActionAt))
    }

    /// The current frame length at which the next long-frame warning is due: 30 min, then every 10 min
    /// after the last warning's threshold.
    public var nextLongFrameWarning: PlayDuration {
        let first = 30, step = 10  // minutes: `firstLongFrameWarning`, `longFrameWarningInterval`
        guard let last = lastLongFrameWarning, last >= Self.firstLongFrameWarning else { return Self.firstLongFrameWarning }
        let passed = Int((last.seconds / 60 - Double(first)) / Double(step)) + 1
        return .minutes(first + passed * step)
    }

    public var sides: [Side] { [first, second] }

    public func side(of player: PlayerId) -> Side? {
        if first.player == player { return first }
        if second.player == player { return second }
        return nil
    }

    public func opponent(of player: PlayerId) -> Side? {
        if first.player == player { return second }
        if second.player == player { return first }
        return nil
    }

    public var isPaused: Bool { status == .paused }

    /// Who breaks the next frame, derived from the frames and the break rule; nil before a breaker is chosen.
    /// Alternate: the origin breaks the odd frames counted from the origin.
    /// Winner breaks: the last remaining frame's winner (since the origin), else the origin. Sets don't affect it.
    public var nextBreaker: Side? {
        guard let origin = breakerOrigin,
              let originSide = side(of: origin.player),
              let other = opponent(of: origin.player) else { return nil }
        switch setup.breakRule {
        case .alternate:
            let offset = frames.count + 1 - origin.frameNumber
            return offset % 2 == 0 ? originSide : other
        case .winnerBreaks:
            guard let last = frames.last, last.number >= origin.frameNumber else { return originSide }
            return side(of: last.winner.player)
        }
    }

    /// The live tally, or the corrected score once an ended match has been corrected.
    public var score: Score { scoreCorrection.map(correctedScore) ?? tally.score }

    public var isMatchTargetReached: Bool { tally.isMatchTargetReached(style: setup.style) }

    /// The current frame's timer at `now`: since the frame started, minus paused time.
    public func frameLength(at now: Date) -> PlayDuration {
        PlayDuration.elapsed(from: currentFrameStartedAt, to: now, minusPaused: pausedTime(from: currentFrameStartedAt, to: now))
    }

    /// The match timer at `now`: since the start, minus paused time.
    public func matchLength(at now: Date) -> PlayDuration {
        PlayDuration.elapsed(from: startTime.date, to: now, minusPaused: pausedTime(from: startTime.date, to: now))
    }

    /// Paused time overlapping `[start, end]`; an open pause runs to `end`.
    func pausedTime(from start: Date, to end: Date) -> TimeInterval {
        pauses.reduce(0) { total, pause in
            let from = max(pause.startedAt, start)
            let to = min(pause.endedAt ?? end, end)
            return total + max(0, to.timeIntervalSince(from))
        }
    }

    var tally: Tally { Tally(frames: frames, setup: setup) }
}

extension MatchEvent {
    /// A recorded action (score change, breaker choice, pause/resume, ending, …) that resets the idle time.
    /// Warnings, stale flags and a merge's player move are not actions.
    var isAction: Bool {
        switch self {
        case .staleMatchFlagged, .longFrameWarned, .matchPlayerMoved: false
        default: true
        }
    }
}
